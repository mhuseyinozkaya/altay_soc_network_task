#!/bin/sh
# OpenVPN her istemci bağlantısında bu scripti çalıştırır.
# common_name, OpenVPN tarafından ortam değişkeni olarak set edilir
# (istemci sertifikasının CN alanı).
#
# Amaç: sertifika zaten OpenVPN tarafından doğrulandı; burada aynı
# kullanıcıyı FreeRADIUS'a sorup post-auth -> FastAPI Policy Engine
# akışından geçirerek profil/VLAN kararını aynı yerden (auth_events)
# loglamak.

RADIUS_HOST="192.168.101.10"

# NOT: Bu iki değer bilinçli olarak hardcoded - OpenVPN'in --client-connect
# script'ini çağırırken ana process'in (PID 1) tüm ortam değişkenlerini
# aktarmadığı görüldü (script-security ile çalıştırılan harici programlara
# yalnızca OpenVPN'in kendi ürettiği değişkenler garanti ediliyor, .env'den
# gelen RADIUS_SHARED_SECRET/VPN_RADIUS_SERVICE_SECRET script'e ulaşmadı).
# Bu değer freeradius/clients.conf'taki "secret" ile BİREBİR AYNI OLMALI
# (RADIUS shared secret, iki taraf da eşleşmezse Access-Reject alınır).
RADIUS_SECRET="changeme_shared_secret"   # freeradius/clients.conf ile aynı
VPN_TEST_PASSWORD="changeme"             # freeradius/users ile aynı (lab/test)

if [ -z "$common_name" ]; then
    echo "client-connect: common_name bulunamadi, reddediliyor"
    exit 1
fi

# YENİ: radclient çağrısını fiziksel olarak vpn-gateway container'ı yaptığı
# için FreeRADIUS'un gördüğü kaynak IP her zaman vpn-gateway'in kendi IP'si
# oluyordu - Wazuh'un "sadece bu VPN kullanıcısını blokla/karantinaya al"
# diyebilmesi için gerçek istemci (tünel) IP'si gerekiyor.
# ifconfig_pool_remote_ip, OpenVPN tarafından --client-connect script'ine
# otomatik set edilen kendi değişkenlerinden biri (genel .env değişkenleri
# gibi parent-process ortamından gelmiyor, bu yüzden RADIUS_SHARED_SECRET'te
# yaşadığımız aktarım sorunundan etkilenmiyor).
# Bu alan yalnızca loglanan/raporlanan IP'yi doğru hale getiriyor -
# Access-Accept/Reject kararını ETKİLEMİYOR.
CALLING_STATION_ID="${ifconfig_pool_remote_ip:-$common_name}"

RESPONSE=$(printf "User-Name=%s,User-Password=%s,NAS-Identifier=vpn,Calling-Station-Id=%s,Message-Authenticator=0x00" \
    "$common_name" "$VPN_TEST_PASSWORD" "$CALLING_STATION_ID" \
    | radclient -x "${RADIUS_HOST}:1812" auth "${RADIUS_SECRET}" 2>&1)

echo "$RESPONSE" | grep -q "Access-Accept"
if [ $? -eq 0 ]; then
    echo "client-connect: ${common_name} kabul edildi (RADIUS)"
    exit 0
else
    echo "client-connect: ${common_name} reddedildi (RADIUS): $RESPONSE"
    exit 1
fi
