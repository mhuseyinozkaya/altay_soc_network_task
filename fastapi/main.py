import json
import os
from datetime import datetime, timezone

import psycopg
import redis
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel

app = FastAPI(title="SOC Policy Engine")

DB_DSN = os.environ.get(
    "DB_DSN",
    "postgresql://soc_user:changeme@postgres:5432/soc_db",
)
REDIS_HOST = os.environ.get("REDIS_HOST", "redis")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))

# --- Wazuh entegrasyonu ---
AUDIT_LOG_PATH = "/var/log/soc/auth_events.log"
INTERNAL_TOKEN = os.environ.get("INTERNAL_TOKEN", "")
QUARANTINE_MODE = os.environ.get("QUARANTINE_MODE", "block")  # "block" | "quarantine"
QUARANTINE_TTL_SECONDS = int(os.environ.get("QUARANTINE_TTL_SECONDS", "600"))

r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

FAIL_THRESHOLD = 5      # bu kadar art arda hatadan sonra rate-limit devreye girer
FAIL_WINDOW_SECONDS = 60


class AuthRequest(BaseModel):
    username: str
    method: str          # "vpn" | "eap-tls"
    source_ip: str
    cert_valid: bool = True   # EAP-TLS ise sertifika doğrulama sonucu (üst katmanda kontrol edilir)
    cert_serial: str | None = None  # EAP-TLS: TLS-Client-Cert-Serial (varsa iptal kontrolü için)


class AuthResponse(BaseModel):
    result: str           # "success" | "failure" | "blocked"
    profile: str | None = None
    vlan: int | None = None
    reason: str | None = None


def radius_response(result: str, profile: str = "", vlan: int = 0, reason: str = ""):
    # FreeRADIUS/rlm_rest'in otomatik JSON->attribute eşlemesi için
    # anahtarlar doğrudan "<list>:<attribute>" formatında.
    # (bkz. freeradius/dictionary.local - SOC-Result/Profile/Vlan/Reason)
    return {
        "control:SOC-Result": result,
        "control:SOC-Profile": profile or "",
        "control:SOC-Vlan": vlan or 0,
        "control:SOC-Reason": reason or "",
    }


def get_db():
    return psycopg.connect(DB_DSN)


def certificate_revocation_status(serial: str) -> bool | None:
    """certificates tablosunda serial_number'a göre iptal durumunu döner.
    Kayıt bulunamazsa None döner (sertifika Postgres'e henüz kaydedilmemiş -
    bkz. vpn/make-client.sh; production'da bu durumda da reddetmek daha
    güvenlidir, ama lab ortamında sert reddetmiyoruz)."""
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT revoked FROM certificates WHERE serial_number = %s",
                (serial,),
            )
            row = cur.fetchone()
    return None if row is None else bool(row[0])


def is_rate_limited(source_ip: str) -> bool:
    key = f"failcount:{source_ip}"
    count = r.get(key)
    return count is not None and int(count) >= FAIL_THRESHOLD


def register_failure(source_ip: str):
    key = f"failcount:{source_ip}"
    pipe = r.pipeline()
    pipe.incr(key)
    pipe.expire(key, FAIL_WINDOW_SECONDS)
    pipe.execute()


def clear_failures(source_ip: str):
    r.delete(f"failcount:{source_ip}")


def log_event(username, method, result, profile, vlan, source_ip, reason):
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO auth_events
                    (username, method, result, assigned_profile, assigned_vlan, source_ip, reason)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                """,
                (username, method, result, profile, vlan, source_ip, reason),
            )
        conn.commit()

    # Wazuh'un tail ettiği kaynak - Postgres'e ek olarak aynı olayı JSON
    # satırı olarak da yazıyoruz (bkz. wazuh/manager/config/local_rules.xml,
    # fastapi/ossec-agent.conf: log_format=json).
    try:
        os.makedirs(os.path.dirname(AUDIT_LOG_PATH), exist_ok=True)
        event = {
            "event_id": "soc_auth_event",
            "username": username,
            "method": method,
            "result": result,
            "profile": profile,
            "vlan": vlan,
            "source_ip": source_ip,
            "reason": reason,
            "ts": datetime.now(timezone.utc).isoformat(),
        }
        with open(AUDIT_LOG_PATH, "a") as f:
            f.write(json.dumps(event) + "\n")
    except OSError:
        # Audit log yazılamazsa akışı durdurmuyoruz (Postgres asıl kaynak);
        # sadece Wazuh görünürlüğü kaybolur.
        pass


def is_quarantined(source_ip: str) -> bool:
    return QUARANTINE_MODE == "quarantine" and r.get(f"quarantine:{source_ip}") is not None


def quarantine_source(source_ip: str):
    r.setex(f"quarantine:{source_ip}", QUARANTINE_TTL_SECONDS, "1")


class SecurityActionRequest(BaseModel):
    source_ip: str
    username: str | None = None
    action_type: str      # "block_ip" | "quarantine_vlan"
    detail: str | None = None


@app.post("/authorize")
def authorize(req: AuthRequest):
    # 0) Bonus: QUARANTINE_MODE=quarantine ise ve bu source_ip daha önce
    # Wazuh tarafından karantinaya alındıysa, bağlantıyı kesmek yerine
    # sabit karantina profiline/VLAN'ına yönlendir (bağlantıyı canlı tutar
    # ama izole eder). block modunda bu kontrol hiç devrede değil.
    if is_quarantined(req.source_ip):
        log_event(req.username, req.method, "success", "quarantine", 99,
                   req.source_ip, "quarantined")
        return radius_response("success", profile="quarantine", vlan=99, reason="quarantined")

    # 1) Rate-limit kontrolü (Redis)
    if is_rate_limited(req.source_ip):
        log_event(req.username, req.method, "failure", None, None,
                   req.source_ip, "rate_limited")
        return radius_response("blocked", reason="rate_limited")

    # 2) Sertifika geçersizse doğrudan reddet
    if req.method == "eap-tls" and not req.cert_valid:
        register_failure(req.source_ip)
        log_event(req.username, req.method, "failure", None, None,
                   req.source_ip, "invalid_certificate")
        return radius_response("failure", reason="invalid_certificate")

    # 2b) EAP-TLS: sertifika iptal edilmiş mi? (certificates.revoked)
    # TLS handshake sertifikanın geçerliliğini/imzasını zaten doğruladı,
    # ama iptal (revocation) durumunu FreeRADIUS/OpenSSL katmanı kontrol
    # etmiyor (bkz. freeradius/eap.conf notu) - bu kontrol burada, merkezi
    # Postgres kaydı üzerinden yapılıyor.
    if req.method == "eap-tls" and req.cert_serial:
        revoked = certificate_revocation_status(req.cert_serial)
        if revoked is True:
            register_failure(req.source_ip)
            log_event(req.username, req.method, "failure", None, None,
                       req.source_ip, "certificate_revoked")
            return radius_response("failure", reason="certificate_revoked")
        # revoked is None -> sertifika henüz certificates tablosuna
        # kaydedilmemiş; şimdilik reddetmiyoruz, sadece not düşüyoruz.

    # 3) Kullanıcıyı Postgres'te ara
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT profile, vlan_id FROM users WHERE username = %s",
                (req.username,),
            )
            row = cur.fetchone()

    if row is None:
        register_failure(req.source_ip)
        log_event(req.username, req.method, "failure", None, None,
                   req.source_ip, "unknown_user")
        return radius_response("failure", reason="unknown_user")

    profile, vlan = row
    clear_failures(req.source_ip)
    log_event(req.username, req.method, "success", profile, vlan,
               req.source_ip, "ok")
    return radius_response("success", profile=profile, vlan=vlan, reason="ok")


@app.get("/healthz")
def healthz():
    return {"status": "ok", "time": datetime.now(timezone.utc).isoformat()}


@app.post("/internal/security-action")
def security_action(req: SecurityActionRequest, x_internal_token: str = Header(default="")):
    # Wazuh active-response scriptleri (soc-block-radius.sh, soc-block-vpn.sh,
    # soc-log-vpn-action.sh, soc-quarantine.sh) bu endpoint'i çağırıyor.
    # Basit bir paylaşılan token ile korunuyor (bkz. .env: INTERNAL_TOKEN,
    # wazuh-manager/freeradius/vpn-gateway ile aynı değer olmalı).
    if not INTERNAL_TOKEN or x_internal_token != INTERNAL_TOKEN:
        raise HTTPException(status_code=401, detail="invalid internal token")

    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO security_actions (target, action_type, detail)
                VALUES (%s, %s, %s)
                """,
                (req.username or req.source_ip, req.action_type, req.detail),
            )
        conn.commit()

    if req.action_type == "quarantine_vlan":
        quarantine_source(req.source_ip)

    return {"status": "recorded"}
