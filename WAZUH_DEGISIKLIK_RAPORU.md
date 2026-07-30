# Wazuh Entegrasyonu — Değişiklik Raporu ve Kurulum Talimatı

Bu doküman, Faz1 (altyapı) + Faz2 (red team) tamamlanmış olan projeye Wazuh
(SIEM) ve active-response katmanının nasıl eklendiğini, hangi dosyaların
neden değiştiğini ve projeyi ayağa kaldıracak kişinin adım adım ne yapması
gerektiğini anlatır.

**Önemli:** Test edilmiş VPN/RADIUS/FastAPI akışının mantığına (Access-Accept
/ Access-Reject kararı) dokunulmadı. Sadece paralel bir gözlem+müdahale
katmanı (Wazuh) eklendi. Yine de değişen dosyalar aşağıda tek tek listelendi
— "neden bu satır değişti" sorusunun cevabını burada bulabilirsiniz.

---

## 1. Ne eklendi (yeni bileşenler)

| Bileşen | Nerede | Ne işe yarıyor |
|---|---|---|
| Wazuh Manager | `wazuh/manager/` (yeni container: `wazuh-manager`) | Tüm logları toplar, alarm üretir, active-response'u tetikler. Dashboard/indexer **yok** — sadece manager, kontrol log dosyalarından ve `docker exec` ile yapılır. |
| Wazuh Agent | `freeradius`, `vpn-gateway`, `fastapi` container'larının içine kuruldu | Kendi container'ındaki logu manager'a gönderir, manager'dan gelen active-response komutlarını yerelde çalıştırır. |
| JSON audit log | `fastapi/main.py` → `/var/log/soc/auth_events.log` | Her `/authorize` kararı Postgres'e ek olarak buraya da JSON satırı olarak yazılıyor. Wazuh'un asıl okuduğu kaynak burası (Postgres'i değil, bu dosyayı tail ediyor). |
| Active-response scriptleri | `freeradius/active-response/`, `vpn/active-response/`, `wazuh/manager/active-response/` | Alarm eşiği aşıldığında bağlantıyı fiilen kesen (iptables/kill) veya karantinaya alan scriptler. |
| `/internal/security-action` | `fastapi/main.py` (yeni endpoint) | Wazuh'un tetiklediği aksiyonu `security_actions` tablosuna yazmak için. Basit bir token ile korunuyor. |
| Quarantine (bonus) | Redis + `access_profile` enum'ında `quarantine` değeri | Bağlantıyı tamamen kesmek yerine VLAN 99'a hapsetme modu. `QUARANTINE_MODE` env değişkeniyle açılıp kapanıyor. |

---

## 2. Mevcut (zaten var olan, test edilmiş) dosyalarda ne değişti ve neden

### `docker-compose.yml`
- **`wazuh-manager` servisi eklendi.** Hem `dmz_net` (192.168.100.12) hem
  `internal_net`'te (192.168.101.15) — çünkü hem DMZ'deki VPN'i hem
  internal_net'teki FreeRADIUS/FastAPI'yi izlemesi gerekiyor.
- **`freeradius` servisine `cap_add: NET_ADMIN` eklendi.** Active-response
  scripti iptables kuralı ekleyebilsin diye (önceden bu capability yoktu).
- **`command: ["freeradius", "-X"]` (debug modu) satırı kaldırıldı.**
  `agent_todo.md`'de zaten "test bitince kaldırılmalı" notu vardı, bu adımı
  ben tamamladım. Artık freeradius normal modda (`entrypoint.sh` üzerinden)
  çalışıyor.
- **`vpn-gateway`'e `WAZUH_MANAGER: 192.168.100.12` (sabit IP, hostname
  değil) verildi.** Sebebi aşağıda "Dikkat Edilmesi Gereken Nokta" bölümünde.
- Tüm servislere Wazuh agent kaydı için `WAZUH_AGENT_NAME`,
  `WAZUH_REGISTRATION_PASSWORD` ortam değişkenleri eklendi.
- `fastapi`'ye `INTERNAL_TOKEN`, `QUARANTINE_MODE`, `QUARANTINE_TTL_SECONDS`
  eklendi.

### `fastapi/main.py`
- **Postgres'e yazan kod satırı değişmedi**, sadece `log_event()`
  fonksiyonu genişletildi: aynı fonksiyon artık Postgres insert'inden sonra
  aynı bilgiyi `/var/log/soc/auth_events.log`'a JSON olarak da yazıyor.
- `authorize()` fonksiyonunun en başına (adım 0) quarantine kontrolü
  eklendi — mevcut rate-limit/sertifika/kullanıcı kontrol sırası
  değişmedi, öncesine bir kontrol eklendi.
- Yeni endpoint: `POST /internal/security-action` (Wazuh buraya yazıyor).

### `fastapi/Dockerfile`
- Wazuh agent kurulumu + `ossec-agent.conf` kopyalanması eklendi.
- `CMD` yerine `ENTRYPOINT ["/entrypoint.sh"]` kullanılıyor artık (yeni
  `entrypoint.sh` önce Wazuh agent'ı kaydedip başlatıyor, sonra `exec
  uvicorn ...` ile eskisiyle aynı komutu çalıştırıyor). Healthcheck
  değişmedi.

### `freeradius/Dockerfile` + yeni `freeradius/entrypoint.sh`
- Wazuh agent + `iptables` + `jq` + `curl` kuruldu.
- **CMD davranışı değişti:** eskiden `freeradius -f -l stdout` idi. Artık
  `entrypoint.sh` hem dosyaya (`/var/log/freeradius/radius.log`) yazıp hem
  `tail -F` ile aynı içeriği stdout'a basıyor — yani `docker logs
  freeradius` eskisi gibi çalışmaya devam ediyor, ek olarak Wazuh'un
  okuyabileceği bir dosya da oluşuyor.
- Geri kalan tüm dosyalar (`clients.conf`, `eap.conf`, `users`, `mods-rest`
  içindeki `data` satırı hariç, `policy-soc`) **aynı**.

### `freeradius/policy-soc` ve `freeradius/mods-rest` — DİKKAT
- Access-Accept/Access-Reject kararını veren mantık (rest.authorize çağrısı,
  `SOC-Result` kontrolü, `ok || updated` fix'i) **hiç değişmedi**.
- Sadece şu eklendi: VPN akışında artık `Calling-Station-Id` varsa onu,
  yoksa eskisi gibi `Packet-Src-IP-Address`'i kullanan bir `Tmp-String-1`
  değişkeni oluşturuluyor ve `mods-rest`'teki `source_ip` alanı buna
  bağlandı. Sebebi bir sonraki maddede.

### `vpn/client-connect.sh` — DİKKAT
- RADIUS'a giden istek artık bir alan daha içeriyor:
  `Calling-Station-Id=<istemcinin gerçek tünel IP'si>`
  (`ifconfig_pool_remote_ip` ortam değişkeninden alınıyor, OpenVPN bunu
  otomatik set ediyor).
- **Neden gerekli:** `radclient` çağrısını fiziksel olarak `vpn-gateway`
  container'ı yapıyor, yani FreeRADIUS'un gördüğü kaynak IP her zaman
  `vpn-gateway`'in kendi IP'si oluyordu — hangi gerçek VPN kullanıcısının
  bağlandığını ayırt etmek mümkün değildi. Wazuh'un "sadece o kullanıcıyı
  blokla/karantinaya al" diyebilmesi için gerçek istemci IP'sinin
  bilinmesi şart. **Access-Accept/Reject kararını etkilemiyor**, sadece
  loglanan/raporlanan IP bilgisini daha doğru hale getiriyor.
- `radclient` çağrısına gönderilen diğer alanlar (`User-Name`,
  `User-Password`, `NAS-Identifier`, `Message-Authenticator`) **değişmedi**.

### `vpn/server.conf` + yeni `vpn/entrypoint.sh` — DİKKAT
- `log-append /var/log/openvpn/openvpn.log` **geri eklendi**. Biliyoruz ki
  bu satır daha önce `docker logs vpn-gateway`'i kestiği için
  kaldırılmıştı (agent_todo.md'de bu bugfix var). Bu sefer aynı soruna
  düşülmemesi için `entrypoint.sh` içinde bu dosya `tail -F` ile ayrıca
  stdout'a da basılıyor. Yani **hem `docker logs vpn-gateway` çalışmalı
  hem de Wazuh dosyayı okuyabilmeli.** Bu noktayı mutlaka test edin.
- `management 127.0.0.1 7505` eklendi — Wazuh'un belirli bir VPN
  istemcisini anında sonlandırabilmesi (`kill <cn>`) için. Sadece
  container içinden erişilebilir, dışa açılmıyor.
- `client-connect` satırı, sertifika/kimlik doğrulama akışı **değişmedi**.

### `postgres/schema.sql`
- Tek satır: `access_profile` enum'ına `'quarantine'` değeri eklendi.
  Mevcut `admin/employee/guest` değerleri ve tüm tablolar aynı.

---

## 3. Dikkat Edilmesi Gereken Nokta: vpn-gateway'in ağ kısıtlaması

`vpn/entrypoint.sh` artık container başlarken kendi üzerine şu iptables
kuralını ekliyor:

- `internal_net`'e (192.168.101.0/24) çıkış **sadece** FreeRADIUS'un
  1812/1813 portlarına izinli, geri kalan her şey DROP.

Bu, görev metnindeki "DMZ'den bu servislere yalnızca belirli portlar
üzerinden erişim verilecek" isterini fiilen uygulayan bir kural (Docker'ın
kendi network izolasyonuna ek bir savunma katmanı).

**Sonucu:** `vpn-gateway`'in Wazuh manager'a bağlanırken `wazuh-manager`
hostname'ini DEĞİL, doğrudan `192.168.100.12` (manager'ın DMZ bacağı) IP'sini
kullanması gerekiyordu — çünkü hostname internal_net IP'sine (192.168.101.15)
çözülseydi, yukarıdaki kural bu trafiği de keserdi. `docker-compose.yml`'de
bu şekilde ayarlandı.

---

## 4. Kurulum / Ayağa Kaldırma Adımları

```bash
# 1) Projeyi aç
cd altay_soc_gorev

# 2) Build (Wazuh + wazuh-agent paketleri indirilecek)
docker compose build

# 3) Ayağa kaldır
docker compose up -d

# 4) Her şey ayakta mı kontrol et
docker compose ps
```

---

## 5. Test Sırası

1. **FastAPI ayakta mı:** `curl localhost:8000/healthz`
2. **Wazuh agent'lar bağlandı mı:** `docker exec wazuh-manager /var/ossec/bin/agent_control -l`
3. **RADIUS akışı hâlâ çalışıyor mu:** `docker exec freeradius radtest testadmin changeme localhost 0 testing123`
4. **VPN loglama çalışıyor mu:** `docker logs vpn-gateway`
5. **Audit log dosyası oluşuyor mu:** `docker exec fastapi tail -f /var/log/soc/auth_events.log`
6. **Alarm + active-response uçtan uca:** 5+ başarısız `radtest` sonrası `alerts.json` ve `iptables -L` kontrolü.
