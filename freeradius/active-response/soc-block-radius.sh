#!/bin/bash
# Wazuh active-response script - freeradius agent uzerinde LOKAL calisir.
# AMAC: alarm esigi asildiginda ilgili baglantiyi iptables ile dogrudan
# sonlandirmak (EAP-TLS ve RADIUS uzerinden gelen brute-force/sertifika sahteciligi).

set -u
LOG_FILE="/var/log/soc/active-response.log"
mkdir -p /var/log/soc

log() {
    echo "$(date -u +%FT%TZ) $*" >> "$LOG_FILE"
}

INPUT_JSON=$(cat)
log "raw input: ${INPUT_JSON}"

COMMAND=$(echo "$INPUT_JSON" | jq -r '.command // empty')
SRC_IP=$(echo "$INPUT_JSON" | jq -r '.parameters.alert.data.source_ip // empty')
USERNAME=$(echo "$INPUT_JSON" | jq -r '.parameters.alert.data.username // empty')
REASON=$(echo "$INPUT_JSON" | jq -r '.parameters.alert.rule.description // "unknown"')

if [ -z "$COMMAND" ] || [ -z "$SRC_IP" ]; then
    log "ERROR: command veya srcip bos, cikiliyor. input=${INPUT_JSON}"
    exit 1
fi

FASTAPI_URL="http://fastapi:8000/internal/security-action"
INTERNAL_TOKEN="${FASTAPI_INTERNAL_TOKEN:-}"

report_action() {
    curl -s -m 5 -o /dev/null -w "%{http_code}" \
        -X POST "$FASTAPI_URL" \
        -H "Content-Type: application/json" \
        -H "X-Internal-Token: ${INTERNAL_TOKEN}" \
        -d "{\"source_ip\":\"${SRC_IP}\",\"username\":$( [ -n "$USERNAME" ] && echo "\"${USERNAME}\"" || echo null ),\"action_type\":\"block_ip\",\"detail\":\"freeradius active-response: ${REASON}\"}" \
        >> "$LOG_FILE" 2>&1
    echo >> "$LOG_FILE"
}

case "$COMMAND" in
    add)
        if ! iptables -C INPUT -s "$SRC_IP" -p udp -m multiport --dports 1812,1813 -j DROP 2>/dev/null; then
            iptables -I INPUT -s "$SRC_IP" -p udp -m multiport --dports 1812,1813 -j DROP
            log "BLOCKED ${SRC_IP} (reason: ${REASON})"
            report_action
        else
            log "already blocked ${SRC_IP}, skipping duplicate rule"
        fi
        ;;
    delete)
        iptables -D INPUT -s "$SRC_IP" -p udp -m multiport --dports 1812,1813 -j DROP 2>/dev/null
        log "UNBLOCKED ${SRC_IP} (active-response timeout)"
        ;;
    *)
        log "ERROR: bilinmeyen komut: ${COMMAND}"
        exit 1
        ;;
esac

exit 0
