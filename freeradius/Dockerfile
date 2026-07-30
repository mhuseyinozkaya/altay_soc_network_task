FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    freeradius \
    freeradius-utils \
    freeradius-rest \
    openssl \
    curl \
    jq \
    gnupg \
    ca-certificates \
    iptables \
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
COPY active-response/soc-block-radius.sh /var/ossec/active-response/bin/soc-block-radius.sh
RUN chmod 750 /var/ossec/active-response/bin/soc-block-radius.sh

# Kendi imzalı CA + server sertifikası (test/lab amaçlı).
# freeradius'un kendi CA scriptleri /etc/freeradius/3.0/certs altında hazır gelir.
WORKDIR /etc/freeradius/3.0/certs
RUN make all 2>/dev/null || true

# NOT: clients.conf ve users bilinçli olarak hardcoded (bkz. README Bölüm 6,
# madde 5/6) - OpenVPN'in --client-connect script'ine ana process'in .env
# değişkenlerini güvenilir şekilde aktarmadığı görüldüğü için VPN tarafı
# (vpn/client-connect.sh) da hardcoded'a alındı; RADIUS shared secret'ın
# iki tarafta da eşleşmesi gerektiği için burası da hardcoded'a döndürüldü.
COPY clients.conf /etc/freeradius/3.0/clients.conf
COPY users /etc/freeradius/3.0/users
COPY eap.conf /etc/freeradius/3.0/mods-available/eap

# --- rlm_rest: FastAPI Policy Engine entegrasyonu ---
COPY mods-rest /etc/freeradius/3.0/mods-available/rest
COPY policy-soc /etc/freeradius/3.0/policy.d/soc
COPY dictionary.local /etc/freeradius/3.0/dictionary.local
RUN echo '$INCLUDE dictionary.local' >> /etc/freeradius/3.0/dictionary

RUN ln -sf ../mods-available/rest /etc/freeradius/3.0/mods-enabled/rest

# post-auth { } bloğunun içine policy çağrısını enjekte et.
# NOT: default site dosyasının tam içeriği bu ortamda görüntülenemediği için
# bu sed komutu ilk "post-auth {" satırından hemen sonrasına ekleme yapar.
# Build sonrası `freeradius -CX` ile syntax doğrulaması yapılmalı.
RUN sed -i '0,/post-auth {/s//post-auth {\n\tsoc_policy_engine/' \
    /etc/freeradius/3.0/sites-available/default

RUN chown -R freerad:freerad /etc/freeradius/3.0

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 1812/udp 1813/udp

# NOT: entrypoint.sh artık freeradius'u -X yerine -f -l <dosya> ile
# başlatıp aynı dosyayı tail -F ile stdout'a basıyor (Wazuh dosyayı, docker
# logs stdout'u okuyor) - debug modu (-X) burada tamamen kaldırıldı.
ENTRYPOINT ["/entrypoint.sh"]
