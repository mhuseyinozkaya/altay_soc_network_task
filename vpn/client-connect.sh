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

# Secrets container'ın ortam değişkenlerinden DEĞİL, entrypoint.sh'nin
# yazdığı dosyadan okunuyor - OpenVPN'in client-connect subprocess'i
# container'ın tam ortamını miras almıyor (bkz. entrypoint.sh).
SECRETS_FILE="/etc/openvpn/radius-secrets.env"
if [ -f "$SECRETS_FILE" ]; then
    . "$SECRETS_FILE"
fi

: "${RADIUS_SHARED_SECRET:?RADIUS_SHARED_SECRET tanimli degil (secrets dosyasi bulunamadi - entrypoint.sh calismamis olabilir)}"
: "${VPN_RADIUS_SERVICE_SECRET:?VPN_RADIUS_SERVICE_SECRET tanimli degil}"
RADIUS_SECRET="$RADIUS_SHARED_SECRET"
VPN_TEST_PASSWORD="$VPN_RADIUS_SERVICE_SECRET"

if [ -z "$common_name" ]; then
    echo "client-connect: common_name bulunamadi, reddediliyor"
    exit 1
fi

RESPONSE=$(printf "User-Name=%s,User-Password=%s,NAS-Identifier=vpn,Message-Authenticator=0x00" \
    "$common_name" "$VPN_TEST_PASSWORD" \
    | radclient -x "${RADIUS_HOST}:1812" auth "${RADIUS_SECRET}" 2>&1)

echo "$RESPONSE" | grep -q "Access-Accept"
if [ $? -eq 0 ]; then
    echo "client-connect: ${common_name} kabul edildi (RADIUS)"
    exit 0
else
    echo "client-connect: ${common_name} reddedildi (RADIUS): $RESPONSE"
    exit 1
fi
