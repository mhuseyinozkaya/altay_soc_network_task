#!/bin/bash
set -e

mkdir -p /var/log/freeradius /var/log/soc

# NOT: fastapi/entrypoint.sh'deki ayni gerekce - agent-auth 30sn'ye kadar
# surebiliyor, freeradius'un kendisini bu kadar geciktirmemesi icin arka
# plana (&) alindi.
if [ -n "${WAZUH_MANAGER:-}" ]; then
    (
        sed -i "s/MANAGER_IP/${WAZUH_MANAGER}/" /var/ossec/etc/ossec.conf || true

        if [ ! -s /var/ossec/etc/client.keys ]; then
            echo "[entrypoint] Wazuh agent kaydediliyor (${WAZUH_AGENT_NAME:-freeradius}) -> ${WAZUH_MANAGER}"
            for i in $(seq 1 10); do
                /var/ossec/bin/agent-auth -m "${WAZUH_MANAGER}" \
                    -A "${WAZUH_AGENT_NAME:-freeradius}" \
                    -P "${WAZUH_REGISTRATION_PASSWORD:-}" && break
                echo "[entrypoint] agent-auth basarisiz, 3sn sonra tekrar denenecek (${i}/10)"
                sleep 3
            done
        fi

        /var/ossec/bin/wazuh-control start || echo "[entrypoint] UYARI: wazuh-agent baslatilamadi, freeradius yine de devam edecek"
    ) &
fi

# freeradius'u dosyaya yazacak şekilde başlat (Wazuh agent bu dosyayı tail
# ediyor, bkz. ossec-agent.conf: /var/log/freeradius/radius.log), aynı
# zamanda `tail -F` ile stdout'a da bas ki `docker logs freeradius` eskisi
# gibi çalışmaya devam etsin.
freeradius -f -l /var/log/freeradius/radius.log &
FR_PID=$!

tail -F /var/log/freeradius/radius.log &
TAIL_PID=$!

trap "kill $FR_PID $TAIL_PID 2>/dev/null" TERM INT
wait $FR_PID
