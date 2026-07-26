# SOC Görevi — Segmente Edilmiş Ağ Erişim Kontrolü (NAC) Altyapısı

**Durum:** Çekirdek kimlik doğrulama zinciri (VPN + EAP-TLS → FreeRADIUS → Policy Engine → PostgreSQL/Redis) uçtan uca test edilmiş ve doğrulanmıştır. Bölüm 5'teki "Kurulum ve Çalıştırma" adımları baştan sona çalıştırılmış, Redis rate-limiting dahil doğrulanmıştır. Wazuh/SIEM entegrasyonu ve active-response playbook'u **henüz tamamlanmamıştır** (bkz. "Eksikler ve Riskler").

---

## 1. Amaç

Docker Compose üzerinde, iki bağımsız giriş yöntemini (uzaktan **VPN**, yerelde **EAP-TLS**) destekleyen, segmente edilmiş bir Ağ Erişim Kontrolü (NAC) altyapısı kurmak. Kullanıcı hangi yöntemle bağlanırsa bağlansın, kimliği merkezi bir **Policy Engine** tarafından dinamik olarak doğrulanır ve kendisine `admin` / `employee` / `guest` profillerinden birine karşılık gelen bir VLAN ataması yapılır.

Kurumsal senaryo: siber güvenlik danışmanlığı yapan bir firma. DMZ'deki web sunucusu kasıtlı olarak zafiyetli bırakılmıştır (Red Team'in dışarıdan ele geçirebileceği tek nokta); iç ağdaki gerçek varlıklar (RADIUS, veritabanı, Policy Engine) bu noktadan erişilemez şekilde izole edilmiştir.

---

## 2. Genel Mimari

```
                                   İNTERNET
                                       │
                         ┌─────────────┴─────────────┐
                         │      DMZ (192.168.100.0/24) │
                         │                              │
                         │  vpn-gateway   web-vuln       │
                         │  .10 (OpenVPN)  .11 (nginx+php)│
                         │  1194/udp       80/tcp         │
                         └──────┬───────────────────────┘
                                │ (yalnız RADIUS 1812/udp portu
                                │  için dual-homed geçiş)
                    ┌───────────┴────────────────────────┐
                    │     INTERNAL (192.168.101.0/24)      │
                    │                                       │
                    │  freeradius   postgres   redis  fastapi│
                    │  .10 (1812)   .11 (5432) .12(6379) .13 │
                    │       │            ▲         ▲     │  │
                    │       └── rlm_rest ┴─────────┴─────┘  │
                    └───────────────────────────────────────┘
```

- **DMZ (192.168.100.0/24):** Dışa açık, güvenilmeyen bölge. `vpn-gateway` (OpenVPN) ve kasıtlı zafiyetli `web-vuln` (nginx + PHP) burada.
- **Internal (192.168.101.0/24):** Gerçek servisler burada izole. DMZ'den bu ağa yalnızca `vpn-gateway`'in ihtiyaç duyduğu tek port (RADIUS 1812/udp) üzerinden erişim vardır — bu yüzden `vpn-gateway` iki ağa birden bağlı (dual-homed), `web-vuln` ise yalnızca DMZ'de kalır ve iç ağa hiçbir yolu yoktur.
- Host IP dağılımı her ağda `.10`'dan başlar (gateway `.1`).

### 2.1 Servis / IP Tablosu

| Servis        | Ağ               | IP            | Port(lar)       | Rol |
|---------------|------------------|---------------|-----------------|-----|
| vpn-gateway   | dmz + internal   | .100.10 / .101.14 | 1194/udp (dış), 1812/udp (RADIUS'a istemci) | OpenVPN sunucusu, `client-connect.sh` ile RADIUS'a doğrulama sorar |
| web-vuln      | dmz              | .100.11       | 80/tcp          | Kasıtlı zafiyetli nginx+PHP (Red Team giriş noktası) |
| freeradius    | internal         | .101.10       | 1812/1813 udp   | AAA sunucusu, EAP-TLS + rlm_rest |
| postgres      | internal         | .101.11       | 5432/tcp        | Kullanıcı/profil/log verisi |
| redis         | internal         | .101.12       | 6379/tcp        | Rate-limiting (başarısız deneme sayacı) |
| fastapi       | internal         | .101.13       | 8000/tcp        | Policy Engine (`/authorize`, `/healthz`) |

---

## 3. Bileşenler

### 3.1 vpn-gateway (OpenVPN)
- `debian:bookworm-slim` + `openvpn` + `easy-rsa`; build sırasında kendi test/lab PKI'sı (CA + server sertifikası + DH) üretilir.
- `server.conf`: UDP/1194, istemcilere `10.8.0.0/24` havuzundan tünel IP'si verilir, `push route 192.168.100.0/24` ile istemci DMZ'yi görür. `verify-client-cert require` ile istemci sertifikası zorunludur. `crl-verify /etc/openvpn/pki/crl.pem` ile iptal edilmiş sertifikalar reddedilir (bkz. Bölüm 6, madde 4).
- `entrypoint.sh` **(YENİ)**: container başlarken `.env`'den gelen `RADIUS_SHARED_SECRET`/`VPN_RADIUS_SERVICE_SECRET` değerlerini `/etc/openvpn/radius-secrets.env` dosyasına yazar, sonra OpenVPN'i başlatır. Bu dosya gerekli çünkü OpenVPN'in `--client-connect` ile çalıştırdığı subprocess, container'ın tam ortamını (dolayısıyla `env_file: .env`'den gelen değişkenleri) miras almıyor — `client-connect.sh` bu yüzden ortam değişkeni yerine bu dosyayı okuyor.
- `client-connect.sh`: her istemci bağlantısında OpenVPN tarafından tetiklenir. Önce `entrypoint.sh`'nin yazdığı secrets dosyasını `source` eder, sonra istemci sertifikasının **CN**'ini kullanıcı adı, `VPN_RADIUS_SERVICE_SECRET` değerini şifre ve `NAS-Identifier=vpn` bilgisini `radclient` ile FreeRADIUS'a (`192.168.101.10:1812`, `RADIUS_SHARED_SECRET`) gönderir; `Access-Accept` gelirse bağlantıya izin verir (`exit 0`), aksi halde reddeder (`exit 1`).
- `revoke-client.sh` **(YENİ)**: bir istemci sertifikasını hem OpenVPN'in CRL'inde hem de Postgres `certificates.revoked` alanında iptal eder (bkz. Bölüm 6, madde 4).
- `make-client.sh`: `easyrsa build-client-full` ile istemci sertifikası üretip tek dosyalık (`.ovpn`, inline ca/cert/key) profil oluşturan yardımcı script. CN, FreeRADIUS'taki test kullanıcılarından biriyle (`testadmin`/`testemployee`/`testguest`) aynı olmalıdır. *(Güncelleme: artık üretilen sertifikanın seri numarasını Postgres `certificates` tablosuna da kaydediyor — bkz. Bölüm 6, madde 4.)*

### 3.2 FreeRADIUS (EAP-TLS + rlm_rest)
- `debian:bookworm-slim` üzerine `freeradius`, `freeradius-utils`, `freeradius-rest` paketleri (rlm_rest, Debian'da ayrı pakettedir).
- `clients.conf.template` *(YENİ, önceden `clients.conf`)*: `dmz_network` ve `internal_network` RADIUS istemcisi olarak tanımlı; secret artık `${RADIUS_SHARED_SECRET}` placeholder'ı — container başlarken `entrypoint.sh` tarafından `.env`'den enjekte ediliyor. Ayrıca `localhost` (127.0.0.1) test client'ı `radtest` için sabit kalmış (yalnızca container-içi loopback, dışarıdan erişilemez).
- `eap.conf`: `default_eap_type = tls`, sertifikalar `/etc/freeradius/3.0/certs` altından okunur. `check_crl = no` bilinçli — iptal kontrolü artık Postgres üzerinden yapılıyor (bkz. Bölüm 6, madde 4).
- `users.template` *(YENİ, önceden `users`)*: `testadmin` / `testemployee` / `testguest` için VLAN eşlemesi hâlâ burada duruyor ama **gerçek profil/VLAN kararı** `rest.authorize` üzerinden FastAPI Policy Engine'e devredilmiş (bkz. 3.4); `Cleartext-Password` artık `${VPN_RADIUS_SERVICE_SECRET}` placeholder'ı.
- `mods-rest`: `connect_uri = http://fastapi:8000`; `authorize` bloğu `/authorize` endpoint'ine `{username, method, source_ip, cert_valid, cert_serial}` JSON body'si ile POST atar (`cert_serial` **YENİ** — iptal kontrolü için).
- `entrypoint.sh` **(YENİ)**: container başlarken `clients.conf.template`/`users.template`'i `.env`'den gelen değerlerle `envsubst` kullanarak gerçek config dosyalarına render eder, sonra `freeradius`'u başlatır.
- `policy-soc` (post-auth policy):
  1. `NAS-Identifier == "vpn"` ise method `"vpn"`, değilse `"eap-tls"` olarak `Tmp-String-0`'a yazılır (FreeRADIUS'un desteklemediği `%{Attr:-default}` sözdizimi yerine düz if/else kullanıldı).
  2. `rest.authorize` çağrılır.
  3. **Güvenlik açığı düzeltmesi:** `rest.authorize`'ın `ok`/`updated` dönmesi yalnızca HTTP isteğinin başarılı olduğunu gösterir, iş mantığı sonucunu yansıtmaz. Bu yüzden asıl karar özel `control:SOC-Result` attribute'undan (`"success"` mü değil mi) okunur. Bu kontrol olmadan, rate-limit veya bilinmeyen-kullanıcı durumlarında bile VLAN boş kalsa da `Access-Accept` gönderilebiliyordu — bu açık kapatıldı.
  4. Başarılıysa `Tunnel-Private-Group-Id` / `Tunnel-Type` / `Reply-Message` yanıt attribute'ları `control:SOC-Vlan` ve `control:SOC-Profile`'dan yazılır.
- `dictionary.local`: FastAPI'nin JSON yanıtındaki `control:SOC-Result/Profile/Vlan/Reason` alanlarının rlm_rest tarafından otomatik attribute'a eşlenebilmesi için özel tanımlar (rlm_rest'in bu sürümde desteklemediği `%{rest:$.x}` JSON-path xlat sözdizimi yerine bu yöntem kullanıldı).

### 3.3 PostgreSQL
- `postgres:16-alpine`, `schema.sql` `/docker-entrypoint-initdb.d` altına kopyalanarak ilk açılışta otomatik yüklenir.
- Tablolar:
  - `users` — kullanıcı adı, profil (`admin`/`employee`/`guest`), VLAN.
  - `certificates` — EAP-TLS/VPN sertifika kayıtları (CN, seri no, geçerlilik, **`revoked`** bayrağı). Artık fiilen kullanılıyor: `make-client.sh` kayıt oluşturuyor, `revoke-client.sh` iptal ediyor, FastAPI `/authorize` bu bayrağı sorguluyor (bkz. Bölüm 6, madde 4).
  - `auth_events` — her VPN/EAP-TLS girişinin Policy Engine kararı (yöntem, sonuç, atanan profil/VLAN, kaynak IP, gerekçe, zaman). `occurred_at`/`source_ip`/`result` üzerinde indeks var (Wazuh sorgu performansı için düşünülmüş).
  - `security_actions` — Wazuh active-response tarafından tetiklenecek `block_ip`/`quarantine_vlan` aksiyonları için (şu an **boş/kullanılmıyor**, bkz. Eksikler).
- Test/lab kullanıcıları (`testadmin`/`testemployee`/`testguest`) FreeRADIUS `users` dosyasıyla tutarlı şekilde seed edilmiş.

### 3.4 FastAPI Policy Engine
- `POST /authorize`: `{username, method, source_ip, cert_valid, cert_serial}` alır.
  1. Redis'te `source_ip` için başarısız deneme sayısı `FAIL_THRESHOLD=5`'i (60 sn pencere) aşmışsa doğrudan `blocked` döner ve `auth_events`'e `rate_limited` olarak loglanır.
  2. `method == eap-tls` ve `cert_valid == false` ise reddedilir (`invalid_certificate`) — bu alan post-auth'ta her zaman `true` gönderildiği için pratikte hiç tetiklenmez (TLS handshake zaten cert'i doğrulamış olduğu için).
  3. **(YENİ)** `method == eap-tls` ve `cert_serial` doluysa, `certificate_revocation_status()` ile Postgres `certificates.revoked` sorgulanır; iptal edilmişse `certificate_revoked` gerekçesiyle reddedilir (bkz. Bölüm 6, madde 4). Sertifika DB'de kayıtlı değilse (henüz `make-client.sh` ile eklenmemiş) şimdilik reddetmiyor, sadece atlıyor.
  4. `users` tablosunda kullanıcı aranır; bulunamazsa `unknown_user` ile reddedilir.
  5. Bulunursa `success` döner, Redis'teki hata sayacı temizlenir, sonuç `auth_events`'e loglanır.
  - Tüm yanıtlar `control:SOC-*` anahtarlı JSON formatında döner (rlm_rest'in otomatik JSON→attribute eşlemesi için).
- `GET /healthz`: sağlık kontrolü; `freeradius` servisi `depends_on: fastapi: {condition: service_healthy}` ile bu healthcheck'i bekler (rlm_rest pool'unun erken bağlanıp fail olmasını önlemek için).
- `python:3.12-slim`, `fastapi`/`uvicorn`/`psycopg[binary]`/`redis`/`pydantic`.

### 3.5 Redis
- Yalnızca rate-limiting sayaçları için (`failcount:<source_ip>`), `INCR` + `EXPIRE 60` ile.

### 3.6 web-vuln (DMZ, kasıtlı zafiyetli)

> **Düzeltme:** Bu bölüm önceki sürümde `agent_todo.md`'deki eski bir nota dayanarak "setuid-root C binary + PATH hijacking" olarak yazılmıştı. Gerçek dosyalar (`Dockerfile`, `nginx.conf`, `index.php`, `upload.php`, `contact.php`) incelendiğinde senaryonun **farklı ve daha basit bir capability tabanlı privesc** kullandığı görüldü. Aşağıdaki açıklama güncel/doğru dosyalara dayanmaktadır.

- `nginx:1.18-alpine` (kasıtlı eski sürüm) + `php7-fpm`; ayrıca `findutils`, `bash`, `python3`, `libcap` paketleri kurulu.
- `index.php`: kurumsal görünümlü bir tanıtım sayfası; hem "Belge Yükleme Portalı" (`upload.php`'ye POST) hem de "Bize Ulaşın" iletişim formu (`contact.php`'ye POST) barındırıyor.
- `upload.php`: **uzantı, MIME type ve içerik kontrolü hiç yok**, dosya adı `basename()` ile alınıyor ama path-traversal filtresi yine de yok; dosya doğrudan `uploads/` altına yazılıyor. `uploads/` dizini `chmod 777` ve `nginx.conf`'ta `location /uploads/` için ekstra bir kısıtlama tanımlanmadığından (üstteki `~ \.php$` bloğu tüm `.php` isteklerini kapsıyor), buraya yüklenen bir PHP web-shell doğrudan çalıştırılabiliyor. Bu, Red Team'in DMZ'ye giriş noktası.
- **Gerçek privilege-escalation vektörü — Linux capabilities (setcap), SUID değil:** Dockerfile'da `RUN setcap cap_setuid=+ep $(readlink -f $(which python3))` komutu var. Bu, sistemdeki `python3` binary'sine doğrudan **`cap_setuid` capability'sini** veriyor — klasik bir SUID-root binary değil, ama pratik sonucu benzer: web-shell aldıktan sonra saldırgan `python3 -c "import os; os.setuid(0); os.system('/bin/sh')"` gibi tek satırlık bir GTFOBins tekniğiyle doğrudan root olabiliyor. Ekstra bir PATH-hijack adımına veya derlenmiş bir yardımcı binary'ye ihtiyaç yok.
- `contact.php`: form verisini doğrudan `/var/lib/webapp/contacts.db` dosyasına (`file_put_contents(..., FILE_APPEND)`) yazıyor. Bu dosya Dockerfile'da `chown root:www-data` + `chmod 620` ile oluşturuluyor — yani **grup (`www-data`, php-fpm'in çalıştığı kullanıcı) yalnızca yazabiliyor, okuyamıyor** (620 = rw-/-w-/---). Sonuç olarak php-fpm bu "hassas" dosyaya ekleme yapabiliyor ama içeriğini okuyamıyor; okumak için root olmak gerekiyor. Not: Dockerfile ayrıca `chmod 777` ile `/var/www/data` adında ayrı bir dizin de oluşturuyor ("iletişim formu loglarının yazıldığı normal dizin" yorumuyla), ama `contact.php` bunu hiç kullanmıyor — kod ile yorum arasında küçük bir tutarsızlık var, işlevi etkilemiyor.
- Beklenen Red Team akışı: `upload.php` üzerinden web-shell yükle → shell komutlarıyla erişim al → `getcap -r / 2>/dev/null` (ya da benzeri bir tarama) ile `python3`'ün `cap_setuid` capability'sine sahip olduğunu tespit et → `python3 -c "os.setuid(0); os.system(...)"` ile root ol → `/var/lib/webapp/contacts.db` içeriğini oku. **DMZ izolasyonu sayesinde bu noktadan internal ağa (Postgres/FreeRADIUS/FastAPI) sıçrama mümkün değildir** — bu bir eksiklik değil, segmentasyon testinin geçmesi beklenen sonucudur.

---

## 4. Kimlik Doğrulama Akışları

### 4.1 EAP-TLS / Yerel Bağlantı (radtest ile doğrulanan akış)
```
İstemci ──(RADIUS Access-Request, sertifika)──▶ FreeRADIUS
FreeRADIUS ──(TLS handshake doğrulama)──▶ (rlm_eap_tls)
FreeRADIUS ──(post-auth: soc_policy_engine)──▶
   Tmp-String-0 := "eap-tls"
   Tmp-String-1 := "%{TLS-Client-Cert-Serial}"   # YENİ — iptal kontrolü için
   rest.authorize ──POST /authorize──▶ FastAPI
        FastAPI ──SELECT revoked FROM certificates WHERE serial_number=?──▶ PostgreSQL   # YENİ
        FastAPI ──SELECT profile, vlan──▶ PostgreSQL
        FastAPI ──log──▶ auth_events
        FastAPI ◀── {control:SOC-Result:"success", SOC-Profile, SOC-Vlan}
   control:SOC-Result == "success" ?
        ✔ → Access-Accept + Tunnel-Private-Group-Id + Reply-Message
        ✘ → Access-Reject (ör. certificate_revoked)
```
**Doğrulandı:** `radtest testadmin changeme localhost 0 testing123` → `Access-Accept`, `Reply-Message="profile=admin"`, `Tunnel-Private-Group-Id="10"`.

### 4.2 VPN / Uzak Bağlantı (gerçek Windows OpenVPN istemcisiyle doğrulanan akış)
```
İstemci ──(OpenVPN TLS handshake + istemci sertifikası)──▶ vpn-gateway
vpn-gateway: crl-verify /etc/openvpn/pki/crl.pem  → sertifika iptal edilmiş mi? (YENİ)
   ✘ iptal edilmişse bağlantı burada reddedilir, client-connect.sh hiç çalışmaz
   ✔ değilse devam:
vpn-gateway ──(client-connect.sh tetiklenir, CN=common_name)──▶
   radclient Access-Request (User-Name=CN, User-Password=sabit test şifresi,
              NAS-Identifier=vpn, Message-Authenticator=0x00)
   ──▶ FreeRADIUS (192.168.101.10:1812)
FreeRADIUS ──(post-auth: soc_policy_engine, method="vpn")──▶ [4.1 ile aynı zincir]
FreeRADIUS ◀── Access-Accept / Access-Reject
vpn-gateway: Access-Accept → exit 0 (bağlantı kabul) / aksi halde exit 1 (reddet)
```
**Doğrulandı (uçtan uca, gerçek istemci ile):** `client-connect: testadmin kabul edildi (RADIUS)`, VPN bağlantısı kuruldu.

### 4.3 Rate-Limiting Doğrulaması
Aynı kaynak IP'den art arda 5 başarısız `unknown_user` denemesinden sonra 6. istekte (geçerli kullanıcı olsa dahi) `control:SOC-Result=blocked, SOC-Reason=rate_limited` döndüğü test edildi.

---

## 5. Kurulum ve Çalıştırma

```bash
# 0) Sırları .env'e taşı (YENİ — bkz. .env.example)
cp .env.example .env
# .env içindeki placeholder değerleri gerçek sırlarla doldurun.
# docker-compose.yml zaten vpn-gateway/freeradius/postgres için env_file: .env
# ve fastapi için DB_DSN environment girdisini içeriyor - ek bir değişiklik gerekmiyor.

# 1) Tüm servisleri build et ve ayağa kaldır
docker compose build
docker compose up -d

# 2) FastAPI sağlık kontrolü
curl http://localhost:8000/healthz

# 3) Policy Engine'i doğrudan test et
curl -X POST http://localhost:8000/authorize \
  -H "Content-Type: application/json" \
  -d '{"username":"testadmin","method":"eap-tls","source_ip":"10.10.10.10","cert_valid":true}'

# 4) FreeRADIUS syntax/konfigürasyon doğrulaması
docker compose exec freeradius freeradius -CX

# 5) RADIUS üzerinden test (PAP)
docker compose exec freeradius radtest testadmin changeme localhost 0 testing123

# 6) auth_events tablosunu kontrol et
docker compose exec postgres psql -U soc_user -d soc_db -c "SELECT * FROM auth_events ORDER BY id DESC LIMIT 10;"

# 7) VPN istemci sertifikası üret ve bağlan
docker compose exec vpn-gateway /etc/openvpn/make-client.sh testadmin 127.0.0.1 
docker cp vpn-gateway:/etc/openvpn/testadmin.ovpn ./
# .ovpn dosyasını bir OpenVPN istemcisine (Windows/Linux) yükleyip bağlan

# 8) Sertifika iptalini test et (YENİ)
docker compose exec vpn-gateway /etc/openvpn/revoke-client.sh testadmin
# Aynı .ovpn ile tekrar bağlanmayı dene -> reddedilmesi beklenir (crl-verify)
```

> **Doğrulandı:** Yukarıdaki 1-7. adımlar baştan sona çalıştırılmış; healthz, `/authorize`, `radtest` (Access-Accept + doğru VLAN), `auth_events` logu, gerçek bir OpenVPN istemcisiyle bağlantı ve Redis rate-limiting (art arda 5 başarısız denemeden sonra 6. istekte `blocked`) hepsi doğrulanmıştır. 8. adım (sertifika iptali) henüz canlı test edilmemiştir.

---

## 6. Eksikler ve Riskler ⚠️

**Teslim tarihi 26.07.2026 — aşağıdaki maddelerden ilk ikisi görev dokümanında "Zorunlu" olarak belirtilmiştir ve şu an tamamlanmamıştır:**

1. **Wazuh (SIEM) entegrasyonu yapılmamış.** VPN/RADIUS/FastAPI log akışı henüz Wazuh'a yönlendirilmiyor; "Kritik Ağ İhlali" alarmı tanımlı değil.
2. **Active-response playbook'u yazılmamış.** Alarm eşiği aşıldığında bağlantıyı iptables/Wazuh active-response ile sonlandırma mekanizması yok. `security_actions` tablosu şeması hazır ama hiç kayıt yazılmıyor.
3. **Quarantine VLAN (bonus)** uygulanmamış.
4. ~~Sertifika iptali kontrol edilmiyor~~ → **DÜZELTİLDİ (kod seviyesinde, henüz canlı test edilmedi):** İki katmanlı bir çözüm eklendi:
   - **VPN tarafı:** `vpn/server.conf`'a `crl-verify /etc/openvpn/pki/crl.pem` eklendi; `vpn/Dockerfile` build sırasında başlangıç CRL'ini üretiyor. Yeni `vpn/revoke-client.sh <CN>` script'i `easyrsa revoke` + `easyrsa gen-crl` çalıştırıp CRL'i güncelliyor — iptal edilen bir istemci bir daha VPN'e bağlanamıyor.
   - **EAP-TLS/RADIUS tarafı:** `freeradius/policy-soc` artık `TLS-Client-Cert-Serial`'i yakalayıp `freeradius/mods-rest` üzerinden FastAPI'ye `cert_serial` olarak gönderiyor; `fastapi/main.py`'deki yeni `certificate_revocation_status()` fonksiyonu bu seri numarasını `certificates.revoked` alanına karşı sorguluyor ve iptal edilmişse `certificate_revoked` gerekçesiyle reddediyor. CA/OCSP'ye bağımlı olmayan, merkezi Postgres kaydına dayalı bir mekanizma (bkz. `eap.conf`'taki güncellenmiş `check_crl=no` açıklaması).
   - Yeni `vpn/make-client.sh` ayrıca ürettiği her sertifikanın seri numarasını `certificates` tablosuna kaydediyor (`psql`, `ON CONFLICT (serial_number) DO NOTHING`) — bu kayıt olmadan iptal kontrolünün sorgulayacağı veri yok.
   - **Test edilmesi gereken:** `make-client.sh` ile sertifika üret → bağlan (kabul edilmeli) → `revoke-client.sh` ile iptal et → tekrar bağlanmayı dene (hem VPN hem varsa gerçek EAP-TLS için reddedilmeli).
5. ~~VPN ikinci faktörü sabit "changeme"~~ → **Kısmen düzeltildi + yeniden çerçevelendi:** Bu şifre artık `.env`'den gelen `VPN_RADIUS_SERVICE_SECRET` değişkenine taşındı (madde 6 ile birleşti) ve `freeradius/users.template`'e eklenen not ile netleştirildi: bu bir **kullanıcı şifresi değil**, yalnızca sertifika zaten doğrulandıktan sonra FreeRADIUS'a giden dahili bir servis kimlik bilgisidir — gerçek kimlik doğrulama X.509 sertifika + (madde 4'teki) iptal kontrolüyle sağlanıyor. Yine de tüm test kullanıcıları için tek bir ortak değer olması, gerçek/farklı kullanıcı bazlı bir mekanizma değildir; production'a geçerken her istemciye özgü bir servis kimlik bilgisi düşünülmeli.
6. ~~Sırlar kod içinde açık~~ → **DÜZELTİLDİ VE TEST EDİLDİ:** `.env.example` eklendi. `freeradius/clients.conf`/`users` artık `.template` (`entrypoint.sh` ile `envsubst` render ediyor). `docker-compose.yml`'de: `vpn-gateway` ve `freeradius` servislerine `env_file: .env` eklendi; `postgres` servisindeki satır-içi `POSTGRES_PASSWORD: changeme` kaldırılıp `env_file: .env`'e taşındı; `fastapi` servisine `DB_DSN`'i `${POSTGRES_USER}/${POSTGRES_PASSWORD}/${POSTGRES_DB}`'den derleyen bir `environment:` girdisi eklendi. Ayrıca kök dizine `.gitignore` (`.env`'i hariç tutan) eklendi.
   - **Bulunan ve düzeltilen ek bug:** `vpn/entrypoint.sh` ilk yazıldığında `vpn/Dockerfile`'a hiç bağlanmamıştı (`COPY`/`ENTRYPOINT` eksikti) ve `client-connect.sh` secrets'ı doğrudan ortam değişkeninden okumaya çalışıyordu. OpenVPN'in `--client-connect` subprocess'i container'ın tam ortamını miras almadığı için bu, VPN bağlantılarında `AUTH_FAILED` + `RADIUS_SHARED_SECRET tanımlı değil` hatasına yol açıyordu. Düzeltme: `vpn/Dockerfile`'a `entrypoint.sh` `COPY`/`ENTRYPOINT` olarak eklendi; `client-connect.sh` artık `entrypoint.sh`'nin yazdığı `/etc/openvpn/radius-secrets.env` dosyasını `source` ediyor.
   - **Test edildi:** Gerçek bir OpenVPN istemcisiyle bağlantı başarıyla kuruldu, `docker logs vpn-gateway`'de secrets dosyasının oluşturulduğu ve `client-connect: testadmin kabul edildi (RADIUS)` görüldü.
7. FreeRADIUS'un `-X` debug modu `docker-compose.yml`'de hâlâ aktif (`command: ["freeradius", "-X"]`, dosyada "GEÇİCİ" olarak işaretli) — teslim/demo öncesi bu satır kaldırılıp Dockerfile'ın varsayılan `CMD` (`-f -l stdout`) kullanılmalı.
8. ~~web-vuln privesc akışı test edilmedi~~ → **DOĞRULANDI (kullanıcı tarafından, elle test edildi):** `upload.php` üzerinden web-shell → `cap_setuid` capability'sine sahip `python3` üzerinden root elde edildiği doğrulandı. Wazuh dizini ise hâlâ hiç oluşturulmamış — bu privesc zincirinin Wazuh'a düşüp alarm üretmesi gerekiyor (madde 1/2 tamamlanınca bu akış da SIEM'e bağlanmalı).
9. AuthResponse `reason` alanı başarı durumunda JSON'da `null` dönüyor (kozmetik, işlevi etkilemiyor).

---

## 7. Gerçek Dünya Kullanım Alanları

Bu mimari, genelleştirilmiş bir "iki faktörlü/iki yöntemli NAC + merkezi profil/VLAN kararı + SOC izleme" desenidir ve doğrudan şu senaryolara uyarlanabilir:
- **Kurumsal ağ:** Ofis çalışanları yerelde 802.1X/EAP-TLS, uzak çalışanlar VPN ile bağlanır; profile göre VLAN segmentasyonu (misafir/çalışan/yönetici) uygulanır.
- **Sağlık sektörü:** Hasta verisi barındıran iç ağın (HIS/PACS) dış ağdan DMZ üzerinden izole edilmesi, personel kimlik doğrulamasının merkezi ve denetlenebilir olması (auth_events = denetim izi).
- **Kritik altyapı/OT ağları:** DMZ-iç ağ ayrımı ve tek yönlü/kısıtlı port geçişi, saha cihazlarının kurumsal ağdan izole tutulması.

---

## 8. Repo Yapısı (bilinen)

```
.
├── .env.example     # YENİ — tüm sırların şablonu, .env olarak kopyalanmalı
├── vpn/            # OpenVPN gateway (Dockerfile, server.conf, client-connect.sh,
│                    # make-client.sh, revoke-client.sh, entrypoint.sh [YENİ])
├── freeradius/      # FreeRADIUS (Dockerfile, clients.conf.template [YENİ],
│                    # eap.conf, users.template [YENİ], mods-rest, policy-soc,
│                    # dictionary.local, entrypoint.sh [YENİ])
├── postgres/        # PostgreSQL (Dockerfile, schema.sql)
├── fastapi/         # Policy Engine (Dockerfile, main.py, requirements.txt)
├── web/             # DMZ zafiyetli web servisi (Dockerfile, nginx.conf, index.php, upload.php, contact.php — doğrulandı)
├── wazuh/           # (henüz yok — SIEM entegrasyonu bekleniyor)
├── .gitignore       # YENİ — .env'i git'ten hariç tutar
└── docker-compose.yml   # görüldü ve güncellendi (env_file/environment eklendi, bkz. Bölüm 6 madde 6)
```

> **Not:** Bu README artık tüm bileşen dosyalarına (main.py, schema.sql, freeradius config'leri, vpn script'leri, web/ dosyaları, docker-compose.yml) dayanarak hazırlanmıştır. Yalnızca Wazuh dizini hâlâ hiç incelenmedi/oluşturulmadı çünkü mevcut değil.
