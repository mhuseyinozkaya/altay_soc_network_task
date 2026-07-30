#!/bin/bash
set -e

mkdir -p /var/log/soc

# NOT: Wazuh agent kaydi (agent-auth) baslarisiz olursa 10x3sn=30sn'ye kadar
# bekleyebiliyor. Bu blok daha once uvicorn'dan ONCE, sirayla calisiyordu -
# yani fastapi'nin /healthz'i bu 30sn boyunca hic ayakta olmuyordu ve
# docker'in HEALTHCHECK'i (start-period=5s) bu sureyi asinca container'i
# "unhealthy" isaretleyip freeradius'un (depends_on: service_healthy)
# hic baslamamasina yol aciyordu. Cozum: agent kaydini arka plana (&) alip
# uvicorn'un hemen baslamasini sagliyoruz - fastapi artik wazuh kaydini
# beklemeden ayakta olacak.
if [ -n "${WAZUH_MANAGER:-}" ]; then
    (
        sed -i "s/MANAGER_IP/${WAZUH_MANAGER}/" /var/ossec/etc/ossec.conf || true

        if [ ! -s /var/ossec/etc/client.keys ]; then
            echo "[entrypoint] Wazuh agent kaydediliyor (${WAZUH_AGENT_NAME:-fastapi}) -> ${WAZUH_MANAGER}"
            for i in $(seq 1 10); do
                /var/ossec/bin/agent-auth -m "${WAZUH_MANAGER}" \
                    -A "${WAZUH_AGENT_NAME:-fastapi}" \
                    -P "${WAZUH_REGISTRATION_PASSWORD:-}" && break
                echo "[entrypoint] agent-auth basarisiz, 3sn sonra tekrar denenecek (${i}/10)"
                sleep 3
            done
        fi

        /var/ossec/bin/wazuh-control start || echo "[entrypoint] UYARI: wazuh-agent baslatilamadi, fastapi yine de devam edecek"
    ) &
fi

exec uvicorn main:app --host 0.0.0.0 --port 8000
