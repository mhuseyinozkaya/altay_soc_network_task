#!/bin/bash
set -e

mkdir -p /var/log/openvpn /var/log/soc

# --- internal_net egress kısıtlaması ---
# Görev gereksinimi: "DMZ'den bu servislere yalnızca belirli portlar
# üzerinden erişim verilecek". Docker'ın kendi network izolasyonuna ek bir
# savunma katmanı olarak, vpn-gateway'in internal_net (192.168.101.0/24)
# çıkışını yalnızca FreeRADIUS'un 1812/1813 (RADIUS) portlarına izin verip
# gerisini DROP ediyoruz.
if command -v iptables >/dev/null 2>&1; then
    iptables -I OUTPUT -d 192.168.101.0/24 -p udp --dport 1812 -j ACCEPT
    iptables -I OUTPUT -d 192.168.101.0/24 -p udp --dport 1813 -j ACCEPT
    iptables -A OUTPUT -d 192.168.101.0/24 -j DROP
    echo "[entrypoint] internal_net cikisi RADIUS (1812/1813) ile sinirlandirildi"
else
    echo "[entrypoint] UYARI: iptables bulunamadi, internal_net kisitlamasi uygulanamadi"
fi

# --- Wazuh agent kaydı ---
# DİKKAT: WAZUH_MANAGER burada docker-compose.yml'de bilinçli olarak
# wazuh-manager'ın DMZ bacağının sabit IP'si (192.168.100.12) olarak
# veriliyor, hostname değil - yukarıdaki iptables kuralı hostname'in
# internal_net IP'sine (192.168.101.15) çözülmesi ihtimaline karşı bu
# trafiği keserdi.
# NOT: fastapi/entrypoint.sh'deki ayni gerekce - agent-auth 30sn'ye kadar
# surebiliyor, OpenVPN'in kendisini bu kadar geciktirmemesi icin arka
# plana (&) alindi.
if [ -n "${WAZUH_MANAGER:-}" ]; then
    (
        sed -i "s/MANAGER_IP/${WAZUH_MANAGER}/" /var/ossec/etc/ossec.conf || true

        if [ ! -s /var/ossec/etc/client.keys ]; then
            echo "[entrypoint] Wazuh agent kaydediliyor (${WAZUH_AGENT_NAME:-vpn-gateway}) -> ${WAZUH_MANAGER}"
            for i in $(seq 1 10); do
                /var/ossec/bin/agent-auth -m "${WAZUH_MANAGER}" \
                    -A "${WAZUH_AGENT_NAME:-vpn-gateway}" \
                    -P "${WAZUH_REGISTRATION_PASSWORD:-}" && break
                echo "[entrypoint] agent-auth basarisiz, 3sn sonra tekrar denenecek (${i}/10)"
                sleep 3
            done
        fi

        /var/ossec/bin/wazuh-control start || echo "[entrypoint] UYARI: wazuh-agent baslatilamadi, openvpn yine de devam edecek"
    ) &
fi

# OpenVPN'i başlat - server.conf'taki `log-append /var/log/openvpn/openvpn.log`
# dosyaya yazıyor (Wazuh bunu tail ediyor), biz de aynı dosyayı `tail -F`
# ile stdout'a basıyoruz ki `docker logs vpn-gateway` çalışmaya devam etsin
# (bkz. README/WAZUH_DEGISIKLIK_RAPORU.md - önceki turda bu satır docker
# logs'u kestiği için kaldırılmıştı).
touch /var/log/openvpn/openvpn.log
tail -F /var/log/openvpn/openvpn.log &

exec openvpn --config /etc/openvpn/server.conf
