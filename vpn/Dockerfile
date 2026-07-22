FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    openvpn \
    easy-rsa \
    freeradius-utils \
    && rm -rf /var/lib/apt/lists/*

ENV EASYRSA_PKI=/etc/openvpn/pki

# Test/lab amaçlı PKI (CA + server sertifikası). Gerçek ortamda
# harici bir CA'dan alınan sertifikalarla değiştirilecek.
RUN mkdir -p /var/log/openvpn \
    && ln -s /usr/share/easy-rsa/* /etc/openvpn/ 2>/dev/null || true \
    && cd /etc/openvpn \
    && /usr/share/easy-rsa/easyrsa init-pki \
    && EASYRSA_BATCH=1 /usr/share/easy-rsa/easyrsa build-ca nopass \
    && EASYRSA_BATCH=1 /usr/share/easy-rsa/easyrsa gen-dh \
    && EASYRSA_BATCH=1 /usr/share/easy-rsa/easyrsa build-server-full server nopass

COPY server.conf /etc/openvpn/server.conf
COPY client-connect.sh /etc/openvpn/client-connect.sh
COPY make-client.sh /etc/openvpn/make-client.sh
RUN chmod +x /etc/openvpn/client-connect.sh /etc/openvpn/make-client.sh

EXPOSE 1194/udp

CMD ["openvpn", "--config", "/etc/openvpn/server.conf"]
