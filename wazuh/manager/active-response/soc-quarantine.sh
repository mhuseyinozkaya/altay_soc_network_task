#!/bin/bash
# Wazuh active-response script - wazuh-manager uzerinde "server" konumunda
# calisir. BONUS: baglantiyi tamamen kesmek yerine ilgili kullanici/IP'yi
# quarantine VLAN'a (99) yonlendirir. Sadece QUARANTINE_MODE=quarantine
# oldugunda aktif (bkz. wazuh/manager/config/soc-extra.conf.template).

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
    -d "{\"source_ip\":\"${SRC_IP}\",\"username\":$( [ -n "$USERNAME" ] && echo "\"${USERNAME}\"" || echo null ),\"action_type\":\"quarantine_vlan\",\"detail\":\"wazuh quarantine mode: ${REASON}\"}" \
    >> "$LOG_FILE" 2>&1
echo >> "$LOG_FILE"

log "quarantined ${USERNAME:-$SRC_IP} (reason: ${REASON})"
exit 0
