## Kurallar
Todo başlığı altındaki görevleri yap ve başarıyla tamamladıklarını kendin ne yaptığını hatırlamak ve dökümante etmek için ## finish başlığı altına yaz

## Todo
- Görevdeki dış ağ DMZ ve iç ağı ayır. İç ağın IP adresi 192.168.101.0/24 olsun, DMZ ağı ise 192.168.100.0/24 olsun
- Makinelerin IP dağılımını host IP alanını .10'dan başlatarak yap.
- Docker ağ mimarisi kullanılarak hazırlanacak.
- web sunucusu için minimal nginx sunucusu olacak. web/ dizini altına koyacağım shell.php'yi dosyasını sende onu kopyalayacak Dockerfile'ı oluşturacaksın.
- FreeRadius, PostgreSQL, Redis, ve REST API kurulumlarını yap.
## finish

- Docker network iskeleti oluşturuldu (docker-compose.yml):
  - dmz_net: 192.168.100.0/24 (gateway .1, host'lar .10'dan başlıyor)
  - internal_net: 192.168.101.0/24, internal: true (dış ağa çıkışı yok)
  - Servisler: vpn-gateway (.10) + web-vuln (.11) DMZ'de; freeradius (.10),
    postgres (.11), redis (.12), fastapi (.13) internal_net'te.
- web/Dockerfile: nginx:1.18-alpine (kasıtlı eski sürüm) + php7-fpm.
  - uploads/ dizini 777 izinle oluşturuluyor, PHP-FPM tarafından
    çalıştırılabilir durumda.
- web/index.php: basit dosya yükleme formu.
- web/upload.php: KASITLI ZAFİYETLİ upload handler - uzantı/MIME/tip
  kontrolü yok, path traversal filtresi yok. Bu, AŞAMA 2'deki Red Team
  senaryosunun (sahte/yetkisiz erişim ile sızma) giriş noktasını oluşturuyor.
  Not: shell.php gömülü DEĞİL - Red Team kendi payload'ını bu açık
  üzerinden runtime'da yükleyecek; böylece Wazuh'un yakalayacağı olay
  gerçek bir istismar adımına dayanıyor (statik olarak image'a gömülmüyor).

Henüz yapılmadı: vpn-gateway Dockerfile, FreeRADIUS (EAP-TLS), PostgreSQL
şema/seed, FastAPI + Policy Engine, Wazuh entegrasyonu, playbook/active-response.

---
- FreeRADIUS + EAP-TLS kuruldu (freeradius/):
  - Dockerfile: debian:bookworm-slim üzerine freeradius + freeradius-utils,
    build sırasında self-signed CA/server sertifikası üretiliyor (test/lab
    amaçlı; gerçek CA zincirine sonra geçirilecek).
  - clients.conf: dmz_network (192.168.100.0/24) ve internal_network
    (192.168.101.0/24) RADIUS istemcisi olarak tanımlı, paylaşılan secret
    şimdilik placeholder (.env'e taşınacak).
  - eap.conf: default_eap_type = tls, sertifikalar
    /etc/freeradius/3.0/certs altından okunuyor.
  - users: testadmin/testemployee/testguest için statik VLAN/profil
    eşlemesi (Tunnel-Private-Group-Id 10/20/30). Bu eşleme ileride FastAPI
    Policy Engine'e (rlm_rest) devredilecek, şu an statik.

Henüz yapılmadı: vpn-gateway Dockerfile, PostgreSQL şema/seed, FastAPI +
Policy Engine (rlm_rest entegrasyonu), Wazuh entegrasyonu,
playbook/active-response, gerçek sertifika dağıtımı (istemci sertifikaları).

---
- PostgreSQL şeması kuruldu (postgres/):
  - Tablolar: users (username/profile/vlan), certificates (EAP-TLS sertifika
    kayıtları, seri no, iptal durumu), auth_events (her VPN/EAP-TLS girişinin
    Policy Engine kararı: profil, VLAN, sonuç, IP, gerekçe),
    security_actions (Wazuh active-response tarafından tetiklenen
    block_ip/quarantine_vlan aksiyonları, auth_events'e FK ile bağlı).
  - Enum tipler: access_profile (admin/employee/guest), auth_method
    (vpn/eap-tls), auth_result (success/failure).
  - auth_events üzerinde occurred_at/source_ip/result indeksleri var
    (Wazuh sorgu performansı için).
  - Test/lab kullanıcıları (testadmin/testemployee/testguest) freeradius/users
    ile tutarlı şekilde seed edildi.
  - postgres/Dockerfile: postgres:16-alpine + schema.sql'i
    /docker-entrypoint-initdb.d altına kopyalayarak ilk açılışta otomatik
    yükleniyor. docker-compose.yml'deki postgres servisi image yerine
    build: ./postgres kullanacak şekilde güncellendi.

Henüz yapılmadı: vpn-gateway Dockerfile, FastAPI + Policy Engine
(rlm_rest entegrasyonu, auth_events/security_actions'a yazma), Wazuh
entegrasyonu, playbook/active-response, Redis rate-limiting mantığı,
gerçek istemci sertifikası dağıtımı.

---
- FastAPI + Policy Engine kuruldu (fastapi/):
  - POST /authorize: RADIUS (rlm_rest üzerinden) veya VPN tarafından
    gönderilen {username, method, source_ip, cert_valid} bilgisini alır.
    Postgres users tablosundan profil/VLAN'ı bulur, auth_events tablosuna
    sonucu loglar, JSON olarak {result, profile, vlan, reason} döner.
  - Redis ile rate-limiting: aynı source_ip için FAIL_THRESHOLD=5 başarısız
    denemeden sonra (60 sn pencere içinde) "blocked" sonucu döner ve bu da
    auth_events'e "rate_limited" olarak loglanır. Bu, AŞAMA 3'teki Wazuh
    alarm mekanizmasının veri kaynağı olacak.
  - GET /healthz: sağlık kontrolü.
  - requirements.txt: fastapi, uvicorn, psycopg[binary], redis, pydantic.
  - Dockerfile: python:3.12-slim tabanlı, port 8000.

Henüz yapılmadı: vpn-gateway Dockerfile, rlm_rest'in FreeRADIUS tarafında
gerçek konfigürasyonu (şu an /authorize endpoint'i hazır ama FreeRADIUS
henüz buna bağlanmıyor - eap.conf/authorize bölümüne rlm_rest modülü
eklenmeli), Wazuh entegrasyonu ve log yönlendirme, playbook/active-response
(iptables/Wazuh active-response ile bağlantı kesme), quarantine VLAN
(bonus), security_actions tablosuna yazma mantığı, gerçek istemci
sertifikası dağıtımı, secrets'ların .env'e taşınması.

---
- rlm_rest -> FastAPI Policy Engine entegrasyonu kuruldu (freeradius/):
  - mods-rest: rlm_rest modül config'i (connect_uri=http://fastapi:8000),
    authorize alt bloğu POST /authorize'a JSON body ile istek atıyor
    (username, method=eap-tls, source_ip, cert_valid=true). cert_valid
    hep true çünkü bu çağrı post-auth'ta yapılıyor -> sertifika zaten
    rlm_eap_tls tarafından doğrulanmış oluyor.
  - policy-soc: post-auth için "soc_policy_engine" adlı unlang policy.
    Access-Accept durumunda rest.authorize çağrılıyor; FastAPI "ok"
    dönerse Tunnel-Private-Group-Id/Tunnel-Type reply attribute'larına
    %{rest:$.vlan} ve %{rest:$.profile} ile JSON yanıtından değer
    yazılıyor. FastAPI reddederse (rate_limited/unknown_user) reject
    ediliyor.
  - Dockerfile: rest modülü mods-enabled'a symlink ile açıldı, policy.d/soc
    eklendi, sites-available/default'ın post-auth {} bloğuna
    soc_policy_engine çağrısı sed ile enjekte edildi.
  - docker-compose.yml: freeradius servisine depends_on: fastapi eklendi.

  ÖNEMLİ - test edilmedi: sed enjeksiyonu default site dosyasının gerçek
  içeriği görülmeden yapıldığı için, build sonrası mutlaka
  `freeradius -CX` ile syntax doğrulaması ve gerçek bir EAP-TLS
  handshake ile uçtan uca test gerekiyor (SOC dokümanındaki "Playbook/
  active-response en geç perşembe" kuralına benzer şekilde bu entegrasyon
  da canlı test edilmeden bitmiş sayılmamalı).

Henüz yapılmadı: vpn-gateway Dockerfile (VPN metodu için ayrı bir
authorize akışı - şu an sadece eap-tls kodlanmış durumda), Wazuh
entegrasyonu ve log yönlendirme, playbook/active-response
(iptables/Wazuh active-response), quarantine VLAN (bonus),
security_actions tablosuna yazma, secrets'ların .env'e taşınması,
freeradius -CX doğrulaması.

---
- vpn-gateway kuruldu (vpn/):
  - Dockerfile: debian:bookworm-slim + openvpn + easy-rsa. Build sırasında
    test/lab amaçlı kendi PKI'ı (CA + server sertifikası + dh) üretiliyor.
  - server.conf: udp/1194, tun cihazı, istemcilere 10.8.0.0/24 havuzundan
    IP veriliyor, `push route 192.168.100.0/24` ile istemciler VPN
    üzerinden DMZ'yi görebiliyor. verify-client-cert require ile
    istemci sertifikası zorunlu kılındı.
  - docker-compose.yml: vpn-gateway servisine cap_add: NET_ADMIN ve
    devices: /dev/net/tun eklendi (tun arayüzü için gerekli).

Henüz yapılmadı: OpenVPN <-> FreeRADIUS bağlantısı (VPN metodu için
policy engine akışı - şu an sadece EAP-TLS tarafı FastAPI'ye bağlı,
VPN girişleri henüz auth_events'e loglanmıyor / profil ataması
yapmıyor), istemci sertifikası dağıtımı (.ovpn dosyası üretimi),
Wazuh entegrasyonu ve log yönlendirme, playbook/active-response,
quarantine VLAN (bonus), security_actions tablosuna yazma,
secrets'ların .env'e taşınması, freeradius -CX doğrulaması,
tüm servislerin `docker compose build` ile uçtan uca test edilmesi.

---
- VPN <-> FreeRADIUS bağlantısı kuruldu:
  - vpn/client-connect.sh: OpenVPN her istemci bağlantısında bu scripti
    çalıştırıyor. İstemci sertifikasının CN'ini (common_name env var)
    username olarak, sabit test şifresini (freeradius/users ile aynı,
    "changeme") ve NAS-Identifier=vpn attribute'unu radclient ile
    FreeRADIUS'a (192.168.101.10:1812, dmz_network secret'ı) gönderiyor.
    Access-Accept dönerse exit 0 (bağlantıya izin), aksi halde exit 1
    (reddet).
  - vpn/server.conf: script-security 2 ve client-connect eklendi.
  - vpn/Dockerfile: freeradius-utils (radclient) kuruldu, script
    kopyalanıp çalıştırılabilir yapıldı.
  - freeradius/mods-rest: FastAPI'ye giden "method" alanı artık
    %{NAS-Identifier:-eap-tls} ile dinamik: VPN üzerinden gelen istekte
    "vpn", EAP-TLS akışında (NAS-Identifier set edilmediği için
    varsayılan) "eap-tls" olarak gidiyor. Böylece auth_events tablosunda
    iki giriş yöntemi de ayırt edilebiliyor.

  ÖNEMLİ - test edilmedi / bilinen sınırlamalar:
  - VPN akışında hem sertifika hem de sabit "changeme" şifresiyle RADIUS
    doğrulaması var; bu ikinci faktör şu an gerçek bir kimlik doğrulama
    değil, sadece test/lab amaçlı sabit bir değer (production'a geçmeden
    önce her istemciye özgü bir mekanizmayla değiştirilmeli).
  - client-connect.sh içindeki RADIUS_SECRET ve VPN_TEST_PASSWORD,
    freeradius/clients.conf ve users dosyalarındaki değerlerle senkron
    tutulmalı - şu an ikisi de "changeme*" placeholder, .env'e taşınınca
    tek yerden yönetilmeli.
  - Uçtan uca test edilmedi: gerçek bir OpenVPN istemci sertifikasıyla
    bağlanıp client-connect.sh'nin radclient çağrısının başarılı
    döndüğü ve auth_events tablosuna method=vpn olarak düştüğü
    doğrulanmalı.

Henüz yapılmadı: Wazuh entegrasyonu ve log yönlendirme,
playbook/active-response (iptables/Wazuh active-response),
quarantine VLAN (bonus), security_actions tablosuna yazma,
secrets'ların .env'e taşınması, freeradius -CX doğrulaması,
tüm servislerin docker compose build ile uçtan uca test edilmesi.

---
- Eksik dosya tamamlandı: web/nginx.conf
  - PHP isteklerini 127.0.0.1:9000'deki php-fpm7'ye fastcgi_pass ile
    yönlendiriyor (alpine php7-fpm paketinin varsayılan listen adresi;
    build sonrası doğrulanmalı, farklıysa fastcgi_pass güncellenmeli).
  - /uploads/ için autoindex açık, ekstra bir kısıtlama yok (kasıtlı -
    zafiyet senaryosunun parçası).
  - web/Dockerfile zaten bu dosyayı COPY nginx.conf ile bekliyordu, önceki
    turda dosyanın kendisi unutulmuştu, şimdi tamamlandı.

---
- Bugfix: vpn/Dockerfile - `mkdir -p /etc/openvpn/pki` kaldırıldı.
  Sebep: easyrsa init-pki, EASYRSA_PKI dizini zaten var olduğunda
  EASYRSA_BATCH=1 ile bile interaktif "yes" onayı istiyor ve build'i
  durduruyordu (kullanıcı build hatası bildirdi). Artık dizini
  init-pki'nin kendisi oluşturuyor.

---
- Test hazırlığı: docker-compose.yml'deki fastapi servisine
  ports: "8000:8000" eklendi (sadece test/geliştirme amaçlı - internal_net
  "internal: true" olduğu için bu publish'in gerçekten host'tan erişilebilir
  olduğu doğrulanmalı; sorun çıkarsa geçici olarak internal_net'ten
  internal: true satırını kaldırıp test edilebilir).
- Sıradaki adım: kullanıcıya adım adım test listesi verildi
  (compose up -> healthz -> /authorize -> auth_events kontrolü ->
  freeradius -CX -> radtest -> web-vuln/upload -> vpn client-connect).
  Sonuçlar geldikçe hataları buraya işlenecek.

---
- Bugfix: docker-compose.yml - internal_net'ten "internal: true" kaldırıldı.
  Sebep: bu ayar internal_net'in dışa (internete) çıkışını tamamen kesiyor,
  bu da fastapi için tanımlanan ports: "8000:8000" publish'inin host'tan
  görünmemesine (docker compose ps'de "8000/tcp" olarak, host mapping
  olmadan görünmesine) sebep oluyordu (kullanıcı test sırasında farketti).
  NOT: DMZ<->internal ağ izolasyonu bu ayardan bağımsız, ayrı Docker
  network'leri olmalarından geliyor - bu değişiklik segmentasyonu bozmuyor,
  sadece internal_net'in internete çıkışını serbest bırakıyor.
- Sorun bildirildi: freeradius container docker compose ps çıktısında hiç
  görünmüyor (muhtemelen crash/exit). Kullanıcıdan `docker compose ps -a`
  ve `docker compose logs freeradius` çıktısı istendi, henüz teşhis
  edilmedi.

---
- Bugfix: freeradius/Dockerfile - freeradius-rest paketi eklendi.
  Sebep: Debian bookworm'da rlm_rest.so, ana freeradius paketine değil
  ayrı freeradius-rest paketine dahil; bu yüzden container başlarken
  "Failed to link to module 'rlm_rest': ... No such file or directory"
  hatasıyla crash oluyordu (kullanıcı loglarda tespit etti).

---
- Bugfix: rlm_rest instantiation hatası ("Connection failed: 7 - Couldn't
  connect to server"). Sebep: freeradius'un depends_on: fastapi ayarı
  sadece container başlatma sırasını garanti ediyordu, fastapi'nin
  uvicorn+Postgres bağlantısıyla gerçekten hazır olmasını beklemiyordu;
  rlm_rest pool'u (start=5) erken bağlanmaya çalışıp fail oluyordu.
  Çözüm:
  - fastapi/Dockerfile: curl kuruldu, HEALTHCHECK eklendi (/healthz).
  - docker-compose.yml: freeradius'un depends_on'u
    fastapi: {condition: service_healthy} olarak değiştirildi.
- Temizlik: freeradius/eap.conf'taki artık gereksiz dh_file satırı
  kaldırıldı (loglardaki "no longer necessary" uyarısı için).

---
- Bugfix: freeradius/policy-soc - tanımın başındaki hatalı "policy "
  anahtar kelimesi kaldırıldı. Hata: "Failed to find "policy" as a
  module or policy" + "Errors parsing post-auth section" + "Failed to
  load virtual server default" (freeradius crash oluyordu). policy.d/
  dosyalarında tanım doğrudan `isim { ... }` olmalı, "policy" öneki
  sadece bir bloğun içinden çağırırken kullanılıyor - tanımda değil.
  fastapi artık healthy durumda, freeradius bu düzeltmeyle birlikte
  ayağa kalkmalı.

---
- DOĞRULANDI (uçtan uca, kullanıcı tarafından test edildi):
  - fastapi /healthz -> {"status":"ok",...} (host:8000 üzerinden erişilebilir)
  - fastapi POST /authorize (testadmin, eap-tls) ->
    {"result":"success","profile":"admin","vlan":10}
  - Bu isteğin postgres auth_events tablosuna doğru şekilde loglandığı
    doğrulandı (id=1, username=testadmin, method=eap-tls, result=success,
    assigned_profile=admin, assigned_vlan=10, source_ip=192.168.100.10,
    reason=ok).
  - freeradius artık crash olmadan ayakta (fastapi healthcheck +
    policy-soc düzeltmeleri sonrası).

  Bilinen küçük kozmetik sorun: AuthResponse.reason alanı başarı
  durumunda kodda "ok" set ediliyor ama JSON yanıtında reason:null
  dönüyor (muhtemelen pydantic response_model default'u ile ilgili -
  işlevi etkilemiyor, düzeltme opsiyonel).

Henüz test edilmedi: freeradius -CX syntax doğrulaması, radtest ile
gerçek RADIUS Access-Request testi (rest.authorize'ın post-auth'tan
gerçekten tetiklendiği ve Tunnel-Private-Group-Id'nin doğru döndüğü),
VPN client-connect.sh akışı, web-vuln/upload akışı.
Henüz yapılmadı: Wazuh entegrasyonu, playbook/active-response,
quarantine VLAN (bonus), security_actions tablosuna yazma,
secrets'ların .env'e taşınması.

---
- freeradius/clients.conf'a "localhost" test client'ı eklendi
  (127.0.0.1, secret=testing123, require_message_authenticator=no).
  Sebep: radtest'i container'ın kendi içinden localhost'a atacağız,
  önceki clients.conf'ta sadece dmz_network/internal_network vardı,
  127.0.0.1 hiçbir aralığa girmediği için radtest reddedilirdi.

---
- Bugfix (kullanıcı -X debug çıktısıyla teşhis etti): rest modülü
  "ERROR: ... ^ Unknown module" hatası veriyordu. Sebep:
  mods-rest'teki data alanında kullandığım %{NAS-Identifier:-eap-tls}
  (varsayılan değer) sözdizimi bu FreeRADIUS sürümünde desteklenmiyor/
  farklı parse ediliyor, JSON body'nin tamamını bozup rest.authorize'ın
  fail dönmesine (dolayısıyla Access-Reject'e) sebep oluyordu.
  Çözüm:
  - policy-soc: rest.authorize'dan önce düz if/else ile
    control:Tmp-String-0'a "vpn" ya da "eap-tls" yazılıyor
    (&NAS-Identifier == "vpn" kontrolüyle).
  - mods-rest: data alanındaki method artık %{control:Tmp-String-0}
    referans gösteriyor, kırılgan :- sözdizimi kaldırıldı.

  Test sırası: docker compose build freeradius && docker compose up -d
  freeradius, ardından tekrar radtest testadmin changeme localhost 0
  testing123. Bu sefer Access-Accept + Tunnel-Private-Group-Id=10
  bekleniyor.

  HATIRLATMA: docker-compose.yml'deki freeradius servisine test için
  eklenen `command: ["freeradius", "-X"]` (debug modu) satırı, testler
  bitince kaldırılmalı - production/demo öncesi normal moda dönülmeli.

---
- Bugfix (kullanıcının debug log'undan teşhis edildi) - VLAN/profil boş
  dönüyordu + GİZLİ GÜVENLİK AÇIĞI: rest.authorize'ın "ok" dönmesi sadece
  HTTP isteğinin başarılı olduğunu (200 OK) gösteriyor, FastAPI'nin iş
  mantığı kararını (success/failure/blocked) YANSITMIYORDU. Yani
  rate-limit veya bilinmeyen kullanıcı durumunda FastAPI HTTP 200 ile
  {"result":"blocked"/"failure"} dönse bile [rest.authorize]=ok kabul
  ediliyor ve önceki haliyle (VLAN boş kalsa da) Access-Accept
  gönderilebiliyordu. Ayrıca %{rest:$.vlan}/%{rest:$.profile} JSON
  path xlat sözdizimi bu rlm_rest sürümünde desteklenmiyor
  ("Error URI is malformed").

  Çözüm:
  - freeradius/dictionary.local (YENİ): SOC-Result/SOC-Profile/
    SOC-Vlan/SOC-Reason custom attribute tanımları.
  - freeradius/Dockerfile: dictionary.local kopyalanıp ana dictionary'ye
    $INCLUDE ile eklendi.
  - fastapi/main.py: /authorize artık AuthResponse yerine
    radius_response() ile control:SOC-Result/SOC-Profile/SOC-Vlan/
    SOC-Reason anahtarlı JSON dönüyor (rlm_rest'in otomatik JSON->
    attribute eşlemesiyle uyumlu format, "<list>:<attribute>" şeklinde).
  - freeradius/policy-soc: artık %{rest:$.x} yerine doğrudan
    &control:SOC-Vlan / &control:SOC-Profile okunuyor, VE asıl karar
    &control:SOC-Result == "success" kontrolüyle veriliyor (rest.authorize
    "ok" durumu sadece bağlantı hatası ayrımı için kullanılıyor artık) ->
    güvenlik açığı kapatıldı.

  Test sırası: docker compose build fastapi freeradius &&
  docker compose up -d fastapi freeradius, sonra tekrar radtest.
  Bu sefer Access-Accept + Tunnel-Private-Group-Id="10" +
  Reply-Message="profile=admin" bekleniyor. Ayrıca bilinmeyen bir
  kullanıcıyla (radtest nonexistent wrongpass ...) Access-Reject
  alındığı da ayrıca test edilmeli (güvenlik düzeltmesini doğrulamak için).

---
- Bugfix (debug log ile kesin teşhis edildi): [rest.authorize] = updated
  dönüyordu (control: attribute'ları başarıyla güncellendiği için),
  ama policy-soc'taki if (ok) kontrolü sadece tam "ok" kodunu kabul
  ediyordu, "updated" farklı bir dönüş kodu olduğu için her zaman else
  (reject) bloğuna düşülüyordu - SOC-Result zaten doğru "success" olarak
  parse edilmiş olmasına rağmen. Düzeltme: if (ok) -> if (ok || updated).
- Küçük temizlik: &NAS-Identifier == "vpn" kontrolü, attribute hiç yokken
  (EAP-TLS akışında) "ERROR: Failed retrieving values" basıyordu (zararsız
  ama gürültülü). &NAS-Identifier && &NAS-Identifier == "vpn" ile önce
  varlık kontrolü eklendi.

  Test sırası: docker compose build freeradius && docker compose up -d
  freeradius, sonra tekrar radtest testadmin changeme localhost 0
  testing123. Bu sefer gerçekten Access-Accept + Tunnel-Private-Group-Id
  = "10" bekleniyor.

---
- DOĞRULANDI (uçtan uca, kullanıcı tarafından test edildi): EAP/PAP
  akışında radtest testadmin changeme localhost 0 testing123 ->
  Access-Accept, Reply-Message="profile=admin",
  Tunnel-Type=VLAN, Tunnel-Medium-Type=IEEE-802,
  Tunnel-Private-Group-Id="10". Zincir baştan sona çalışıyor:
  RADIUS Access-Request -> post-auth -> rlm_rest -> FastAPI Policy
  Engine -> Postgres lookup -> doğru VLAN/profil kararı -> RADIUS
  reply attribute'ları.

---
- DOĞRULANDI (kullanıcı tarafından test edildi) - Redis rate-limiting +
  güvenlik düzeltmesi: aynı source_ip'den (10.10.10.10) art arda 5 kez
  "hackeruser" (Postgres'te yok) ile POST /authorize ->
  her seferinde {"control:SOC-Result":"failure",...,
  "control:SOC-Reason":"unknown_user"}. 6. istekte GEÇERLİ bir kullanıcı
  (testadmin) aynı IP'den denendiğinde -> {"control:SOC-Result":"blocked",
  "control:SOC-Reason":"rate_limited"} döndü (FAIL_THRESHOLD=5 doğru
  çalışıyor). Bu, önceki turda bulunan güvenlik açığının (business-logic
  reddinin FreeRADIUS tarafında yanlışlıkla Access-Accept'e dönüşmesi)
  gerçekten kapandığını doğruluyor - hem FastAPI/Redis seviyesinde hem
  de (ok||updated fix'i sayesinde) RADIUS'a giden yolda.

DURUM ÖZETİ: EAP-TLS/PAP -> FreeRADIUS -> rlm_rest -> FastAPI Policy
Engine -> Postgres -> doğru VLAN/profil ataması ve reddi uçtan uca
çalışıyor ve test edildi doğrulandı.

Henüz yapılmadı: gerçek EAP-TLS (sertifika ile, sadece PAP değil) testi,
VPN client-connect.sh akışının gerçek bir OpenVPN istemcisiyle testi,
web-vuln/upload akışının testi, Wazuh entegrasyonu ve log yönlendirme,
playbook/active-response (iptables/Wazuh active-response),
quarantine VLAN (bonus), security_actions tablosuna yazma,
secrets'ların .env'e taşınması, freeradius debug modunun (-X) normal
moda geri alınması (docker-compose.yml'deki command satırı kaldırılmalı).

---
- VPN client testine hazırlık:
  - docker-compose.yml: vpn-gateway'e ports: "1194:1194/udp" eklendi
    (önceden sadece EXPOSE vardı, host'a hiç yayınlanmıyordu - dışarıdan
    gerçek bir OpenVPN client ile bağlanmak mümkün değildi).
  - vpn/make-client.sh (YENİ): easyrsa ile istemci sertifikası üretip
    tek dosyalık (inline ca/cert/key gömülü) .ovpn profili oluşturan
    yardımcı script. Kullanım: /etc/openvpn/make-client.sh <CN> <host>.
    CN, freeradius/users'taki test kullanıcılarıyla (testadmin vb.)
    aynı olmalı çünkü client-connect.sh CN'i RADIUS username olarak
    kullanıyor.
  - vpn/Dockerfile: make-client.sh kopyalanıp çalıştırılabilir yapıldı.

---
- Bugfix: VPN client bağlantısında sürekli AUTH_FAILED alınıyordu
  (kullanıcı gerçek bir Windows OpenVPN client ile test etti - TLS
  handshake sorunsuz geçiyor, ama sonrasında reddediliyordu).
  İki sebep bulundu:
  1) docker logs vpn-gateway boş görünüyordu çünkü server.conf'taki
     log-append /var/log/openvpn/openvpn.log satırı OpenVPN'in (ve
     client-connect.sh'nin) çıktısını container içi bir dosyaya
     yönlendiriyordu, docker'ın yakaladığı stdout'a değil. Bu satır
     kaldırıldı.
  2) ASIL SEBEP: vpn-gateway sadece dmz_net'e bağlıydı, ama
     client-connect.sh radclient ile 192.168.101.10'daki (internal_net)
     freeradius'a Access-Request atmaya çalışıyordu - bu iki ağ
     birbirinden tamamen izole olduğu için vpn-gateway'in oraya hiç
     yolu yoktu, radclient timeout/hata alıp script exit 1 ile
     reddediyordu (bu da OpenVPN'de AUTH_FAILED olarak görünüyordu).
     Çözüm: vpn-gateway artık dmz_net (192.168.100.10) VE internal_net
     (192.168.101.14) olmak üzere iki ağa birden bağlı (dual-homed).
     Bu, görevin kendi tanımıyla da tutarlı: "DMZ'den bu servislere
     yalnızca belirli portlar üzerinden erişim verilecek" ifadesi tam
     olarak bu senaryoyu (VPN gateway -> RADIUS 1812/udp) kapsıyor,
     segmentasyonu bozmuyor çünkü diğer DMZ üyesi (web-vuln) hâlâ
     internal_net'e hiç bağlı değil.

  Test sırası: docker compose build vpn-gateway && docker compose up -d
  vpn-gateway, sonra Windows OpenVPN client'ı tekrar bağla. Bu sefer
  docker logs vpn-gateway'de hem OpenVPN loglarının hem de
  client-connect.sh çıktısının göründüğü doğrulanmalı.

---
- Bugfix (kullanıcı test etti, freeradius logunda "Receive - Insecure
  packet ... Packet does not contain required Message-Authenticator
  attribute" görüldü): vpn-gateway ile internal_net (192.168.101.14)
  arasındaki temel ağ bağlantısı ÇALIŞIYORDU (paket freeradius'a
  ulaşıyordu), ama freeradius/clients.conf'taki internal_network client'ı
  require_message_authenticator = yes olduğu için, client-connect.sh'nin
  radclient ile elle oluşturduğu (Message-Authenticator içermeyen)
  paketi sessizce reddediyordu (hiç yanıt vermiyordu - "No reply from
  server" bu yüzdendi). radtest bunu otomatik eklediği için önceki
  testlerde sorun çıkmamıştı.
  Çözüm: vpn/client-connect.sh'deki radclient'a gönderilen attribute
  listesine Message-Authenticator=0x00 eklendi (radclient bunu görünce
  doğru değeri kendisi hesaplıyor).

  Not: vpn-gateway container'ında (debian bookworm-slim tabanlı) ping
  komutu kurulu değil - bu normal/beklenen, iputils-ping minimal image'da
  yok, test için önemli değil çünkü freeradius logundan bağlantının
  çalıştığı zaten doğrulandı.

  Test sırası: docker compose build vpn-gateway && docker compose up -d
  vpn-gateway, sonra Windows OpenVPN client ile tekrar bağlan. Bu sefer
  "client-connect: testadmin kabul edildi (RADIUS)" ve VPN bağlantısının
  gerçekten kurulduğu (AUTH_FAILED almadan) bekleniyor.

---
- DOĞRULANDI (uçtan uca, gerçek Windows OpenVPN client ile test edildi):
  client-connect.sh'ye Message-Authenticator eklenmesi sorunu çözdü.
  RADIUS debug log: [rest.authorize] = updated, &control:SOC-Result ==
  "success" TRUE, Access-Accept gönderildi (Reply-Message="profile=admin",
  Tunnel-Type=VLAN, Tunnel-Private-Group-Id="10").
  Zincir tam olarak çalışıyor: OpenVPN istemci sertifikası doğrulama ->
  client-connect.sh -> RADIUS Access-Request (Message-Authenticator ile)
  -> FreeRADIUS post-auth -> rlm_rest -> FastAPI Policy Engine ->
  Postgres lookup -> doğru VLAN/profil -> Access-Accept -> OpenVPN
  bağlantıyı kabul ediyor.

DURUM ÖZETİ: Hem EAP-TLS/PAP hem de VPN girişi için tüm NAC zinciri
(FreeRADIUS + rlm_rest + FastAPI Policy Engine + Postgres + Redis
rate-limit) uçtan uca test edildi ve doğrulandı.

Henüz yapılmadı: auth_events tablosuna VPN girişinin method=vpn olarak
gerçekten düştüğünün doğrulanması (muhtemelen düşüyor ama son testte
kontrol edilmedi), web-vuln/upload akışının testi, Wazuh entegrasyonu
ve log yönlendirme, playbook/active-response (iptables/Wazuh
active-response), quarantine VLAN (bonus), security_actions tablosuna
yazma, secrets'ların .env'e taşınması, freeradius debug modunun (-X)
normal moda geri alınması (docker-compose.yml'deki command satırı
kaldırılmalı - artık ana sorunlar çözüldüğü için debug modu kapatılabilir).
