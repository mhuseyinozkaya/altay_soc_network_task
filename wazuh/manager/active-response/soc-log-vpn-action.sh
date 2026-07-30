#!/bin/bash
# Wazuh active-response script - wazuh-manager uzerinde "server" konumunda
# calisir. AMAC: vpn-gateway'in fastapi'ye (internal_net) erisimi kasitli
# olarak sadece RADIUS portlariyla sinirli (bkz. vpn/entrypoint.sh), bu
# yuzden security_actions kaydini burada, manager uzerinden yapiyoruz.
# wazuh-manager hem dmz_net hem internal_net'te oldugu icin fastapi:8000'e
# dogrudan ulasabiliyor.

set -u
LOG_FILE="/var/log/soc/active-response.log"
mkdir -p /var/log/soc

log() {
    echo "$(date -u +%FT%TZ) $*" >> "$LOG_FILE"
}

INPUT_JSON=$(cat)
COMMAND=$(echo "$INPUT_JSON" | jq -r '.command // empty')

if [ "$COMMAND" != "add" ]; then
    exit 0
fi

SRC_IP=$(echo "$INPUT_JSON" | jq -r '.parameters.alert.data.source_ip // empty')
USERNAME=$(echo "$INPUT_JSON" | jq -r '.parameters.alert.data.username // empty')
REASON=$(echo "$INPUT_JSON" | jq -r '.parameters.alert.rule.description // "unknown"')

if [ -z "$SRC_IP" ]; then
    log "ERROR: source_ip bos, cikiliyor. input=${INPUT_JSON}"
    exit 1
fi

curl -s -m 5 -o /dev/null -w "%{http_code}" \
    -X POST "http://fastapi:8000/internal/security-action" \
    -H "Content-Type: application/json" \
    -H "X-Internal-Token: ${FASTAPI_INTERNAL_TOKEN:-}" \
    -d "{\"source_ip\":\"${SRC_IP}\",\"username\":$( [ -n "$USERNAME" ] && echo "\"${USERNAME}\"" || echo null ),\"action_type\":\"block_ip\",\"detail\":\"vpn-gateway active-response (kill+iptables): ${REASON}\"}" \
    >> "$LOG_FILE" 2>&1
echo >> "$LOG_FILE"

log "reported VPN block for ${SRC_IP} to FastAPI"
exit 0
