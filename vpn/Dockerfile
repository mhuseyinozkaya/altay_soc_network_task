FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    openvpn \
    easy-rsa \
    freeradius-utils \
    postgresql-client \
    curl \
    jq \
    gnupg \
    ca-certificates \
    iptables \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# --- Wazuh agent kurulumu (SIEM + active-response) ---
RUN curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring \
        --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import \
    && chmod 644 /usr/share/keyrings/wazuh.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
        > /etc/apt/sources.list.d/wazuh.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends wazuh-agent=4.9.2-1 \
    && rm -rf /var/lib/apt/lists/*

COPY ossec-agent.conf /var/ossec/etc/ossec.conf
COPY active-response/soc-block-vpn.sh /var/ossec/active-response/bin/soc-block-vpn.sh
RUN chmod 750 /var/ossec/active-response/bin/soc-block-vpn.sh

ENV EASYRSA_PKI=/etc/openvpn/pki

# Test/lab amaçlı PKI (CA + server sertifikası). Gerçek ortamda
# harici bir CA'dan alınan sertifikalarla değiştirilecek.
# gen-crl: sertifika iptali (revocation) için başlangıç CRL'i üretir -
# server.conf'taki crl-verify bu dosyayı okur (bkz. revoke-client.sh).
RUN mkdir -p /var/log/openvpn \
    && ln -s /usr/share/easy-rsa/* /etc/openvpn/ 2>/dev/null || true \
    && cd /etc/openvpn \
    && /usr/share/easy-rsa/easyrsa init-pki \
    && EASYRSA_BATCH=1 /usr/share/easy-rsa/easyrsa build-ca nopass \
    && EASYRSA_BATCH=1 /usr/share/easy-rsa/easyrsa gen-dh \
    && EASYRSA_BATCH=1 /usr/share/easy-rsa/easyrsa build-server-full server nopass \
    && EASYRSA_BATCH=1 /usr/share/easy-rsa/easyrsa gen-crl

COPY server.conf /etc/openvpn/server.conf
COPY client-connect.sh /etc/openvpn/client-connect.sh
COPY make-client.sh /etc/openvpn/make-client.sh
COPY revoke-client.sh /etc/openvpn/revoke-client.sh
RUN chmod +x /etc/openvpn/client-connect.sh /etc/openvpn/make-client.sh /etc/openvpn/revoke-client.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 1194/udp

# NOT: entrypoint.sh Wazuh agent kaydı + internal_net egress kısıtlaması
# (iptables) + OpenVPN'i log-append ile başlatıp tail -F ile stdout'a
# basma işini yapıyor - CAP_ADD NET_ADMIN gerektirir (docker-compose.yml'de
# zaten mevcut).
ENTRYPOINT ["/entrypoint.sh"]
