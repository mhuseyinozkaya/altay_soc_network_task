#!/bin/sh
# Kullanım: /etc/openvpn/make-client.sh <ortak_ad> <sunucu_host_veya_ip>
# Örnek:    /etc/openvpn/make-client.sh testadmin 192.168.1.50
#
# common_name, freeradius/users'taki test kullanıcı adlarından biriyle
# aynı olmalı (testadmin/testemployee/testguest) - client-connect.sh bu
# CN'i RADIUS username olarak kullanıyor.

CN="$1"
SERVER_HOST="$2"

if [ -z "$CN" ] || [ -z "$SERVER_HOST" ]; then
    echo "Kullanim: $0 <ortak_ad> <sunucu_host_veya_ip>"
    exit 1
fi

cd /etc/openvpn || exit 1
EASYRSA_BATCH=1 /usr/share/easy-rsa/easyrsa build-client-full "$CN" nopass

OUT="/etc/openvpn/${CN}.ovpn"

cat > "$OUT" << EOF
client
dev tun
proto udp
remote ${SERVER_HOST} 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
verb 3

<ca>
$(cat /etc/openvpn/pki/ca.crt)
</ca>
<cert>
$(sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' /etc/openvpn/pki/issued/${CN}.crt)
</cert>
<key>
$(cat /etc/openvpn/pki/private/${CN}.key)
</key>
EOF

echo "Olusturuldu: ${OUT}"
echo "Host'a kopyalamak icin: docker cp vpn-gateway:${OUT} ./"

# --- Sertifikayı Postgres'e kaydet (certificates tablosu) ---
# Bu kayıt olmadan revoke-client.sh / FastAPI'nin iptal kontrolü çalışamaz
# (main.py, serial_number bulunamazsa reddetmeden geçiyor - bkz. README
# "Eksikler ve Riskler"). vpn-gateway internal_net'e de bağlı olduğu için
# (dual-homed) Postgres'e doğrudan erişebiliyor.
if command -v psql >/dev/null 2>&1; then
    SERIAL=$(openssl x509 -in "/etc/openvpn/pki/issued/${CN}.crt" -noout -serial | cut -d= -f2)
    VALID_FROM=$(openssl x509 -in "/etc/openvpn/pki/issued/${CN}.crt" -noout -startdate | cut -d= -f2)
    VALID_TO=$(openssl x509 -in "/etc/openvpn/pki/issued/${CN}.crt" -noout -enddate | cut -d= -f2)

    : "${POSTGRES_USER:=soc_user}"
    : "${POSTGRES_DB:=soc_db}"
    : "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD tanımlı değil, certificates kaydı atlanıyor}"

    PGPASSWORD="$POSTGRES_PASSWORD" psql -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -c \
        "INSERT INTO certificates (user_id, common_name, serial_number, valid_from, valid_to, revoked)
         SELECT id, '${CN}', '${SERIAL}', '${VALID_FROM}'::timestamptz, '${VALID_TO}'::timestamptz, false
         FROM users WHERE username = '${CN}'
         ON CONFLICT (serial_number) DO NOTHING;" \
        && echo "certificates tablosuna kaydedildi (serial=${SERIAL})." \
        || echo "UYARI: certificates tablosuna yazilamadi (Postgres'e erisim/kimlik bilgisi kontrol edilmeli)."
else
    echo "UYARI: psql bulunamadi, certificates tablosuna kayit atlaniyor (iptal kontrolu bu sertifika icin calismayacak)."
fi
