FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# --- Wazuh agent kurulumu ---
# NOT: Bu adım build sırasında paket sunucusuna (packages.wazuh.com) internet
# erişimi gerektirir. Önceki turda (arkadaşınızın ortamında) bu erişim yoktu,
# bu yüzden hiç eklenmemişti - build gerçekten bu ağdan yapılabiliyor mu
# doğrulanmalı (bkz. README, Wazuh bölümü).
RUN curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring \
        --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import \
    && chmod 644 /usr/share/keyrings/wazuh.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
        > /etc/apt/sources.list.d/wazuh.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends wazuh-agent=4.9.2-1 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# --- Wazuh agent config + entrypoint ---
COPY ossec-agent.conf /var/ossec/etc/ossec.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && mkdir -p /var/log/soc

EXPOSE 8000

HEALTHCHECK --interval=5s --timeout=3s --retries=5 --start-period=15s \
    CMD curl -f http://localhost:8000/healthz || exit 1

ENTRYPOINT ["/entrypoint.sh"]
