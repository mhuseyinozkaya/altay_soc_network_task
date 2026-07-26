#!/bin/sh
# VPN gateway entrypoint: secrets'ları dosyaya yazar, sonra OpenVPN'i başlatır.
# client-connect.sh OpenVPN tarafından subprocess olarak çalıştırıldığında
# container'ın ortam değişkenlerini (env_file: .env ile gelenler) MİRAS
# ALMIYOR - OpenVPN güvenlik nedeniyle client-connect script'ine sınırlı
# bir ortam geçiriyor. Bu yüzden secrets'ı client-connect.sh'nin okuyabileceği
# bir dosyaya yazıyoruz.

set -e

SECRETS_FILE="/etc/openvpn/radius-secrets.env"

: "${RADIUS_SHARED_SECRET:?RADIUS_SHARED_SECRET tanımlı değil (.env dosyasını kontrol edin)}"
: "${VPN_RADIUS_SERVICE_SECRET:?VPN_RADIUS_SERVICE_SECRET tanımlı değil (.env dosyasını kontrol edin)}"

cat > "$SECRETS_FILE" <<EOF
RADIUS_SHARED_SECRET=${RADIUS_SHARED_SECRET}
VPN_RADIUS_SERVICE_SECRET=${VPN_RADIUS_SERVICE_SECRET}
EOF

chmod 600 "$SECRETS_FILE"
echo "VPN entrypoint: secrets dosyasi olusturuldu -> $SECRETS_FILE"

exec "$@"
