#!/bin/sh
# Kullanım: /etc/openvpn/revoke-client.sh <ortak_ad>
# Örnek:    /etc/openvpn/revoke-client.sh testadmin
#
# Bir istemci sertifikasını iki katmanda birden iptal eder:
#   1) easyrsa revoke + gen-crl -> OpenVPN'in crl-verify ile okuduğu CRL
#      güncellenir (VPN bağlantısı bir daha kabul edilmez).
#   2) Postgres certificates.revoked = true -> EAP-TLS/Policy Engine
#      tarafındaki iptal kontrolü de aynı sertifikayı reddeder.
# Bu, Red Team'in "iptal edilmiş sertifika ile bağlantı" testinin
# gerçekten reddedildiğini doğrulamak için kullanılır.

CN="$1"

if [ -z "$CN" ]; then
    echo "Kullanim: $0 <ortak_ad>"
    exit 1
fi

cd /etc/openvpn || exit 1

EASYRSA_BATCH=1 /usr/share/easy-rsa/easyrsa revoke "$CN"
EASYRSA_BATCH=1 /usr/share/easy-rsa/easyrsa gen-crl
cp pki/crl.pem /etc/openvpn/pki/crl.pem
echo "OpenVPN CRL guncellendi: ${CN} artik VPN uzerinden baglanamaz."

if command -v psql >/dev/null 2>&1; then
    : "${POSTGRES_USER:=soc_user}"
    : "${POSTGRES_DB:=soc_db}"
    : "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD tanımlı değil, Postgres güncellenemiyor}"

    PGPASSWORD="$POSTGRES_PASSWORD" psql -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -c \
        "UPDATE certificates SET revoked = true WHERE common_name = '${CN}';" \
        && echo "Postgres certificates.revoked = true olarak guncellendi (${CN})." \
        || echo "UYARI: Postgres guncellenemedi (kayit make-client.sh ile olusturulmus mu kontrol edin)."
else
    echo "UYARI: psql bulunamadi, Postgres tarafi guncellenemedi (yalnizca OpenVPN CRL'i etkin oldu)."
fi

echo "Not: crl-verify her bağlantıda dosyayı yeniden okur, vpn-gateway'i yeniden başlatmaya gerek yok."
