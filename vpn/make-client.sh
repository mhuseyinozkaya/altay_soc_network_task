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
