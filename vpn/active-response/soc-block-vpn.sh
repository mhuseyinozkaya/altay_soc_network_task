#!/bin/bash
# Wazuh active-response script - vpn-gateway agent uzerinde LOKAL calisir.

set -u
LOG_FILE="/var/log/soc/active-response.log"
mkdir -p /var/log/soc

log() {
    echo "$(date -u +%FT%TZ) $*" >> "$LOG_FILE"
}

INPUT_JSON=$(cat)
log "raw input: ${INPUT_JSON}"

COMMAND=$(echo "$INPUT_JSON" | jq -r '.command // empty')
TUNNEL_IP=$(echo "$INPUT_JSON" | jq -r '.parameters.alert.data.source_ip // empty')
REASON=$(echo "$INPUT_JSON" | jq -r '.parameters.alert.rule.description // "unknown"')

if [ -z "$COMMAND" ] || [ -z "$TUNNEL_IP" ]; then
    log "ERROR: command veya tunnel ip bos, cikiliyor. input=${INPUT_JSON}"
    exit 1
fi

management_cmd() {
    printf '%s\n' "$1" | timeout 5 nc 127.0.0.1 7505 2>/dev/null
}

case "$COMMAND" in
    add)
        CN=$(management_cmd "status 2" | awk -F',' -v ip="$TUNNEL_IP" \
            '$0 ~ /^CLIENT_LIST/ && $4 == ip {print $2}')

        if [ -n "$CN" ]; then
            management_cmd "kill ${CN}" >/dev/null
            log "KILLED vpn session cn=${CN} tunnel_ip=${TUNNEL_IP} (reason: ${REASON})"
        else
            log "WARN: ${TUNNEL_IP} icin aktif CN bulunamadi (belki zaten kapandi)"
        fi

        if ! iptables -C FORWARD -s "$TUNNEL_IP" -j DROP 2>/dev/null; then
            iptables -I FORWARD -s "$TUNNEL_IP" -j DROP
            log "BLOCKED forward traffic from ${TUNNEL_IP}"
        fi
        ;;
    delete)
        iptables -D FORWARD -s "$TUNNEL_IP" -j DROP 2>/dev/null
        log "UNBLOCKED forward traffic from ${TUNNEL_IP} (active-response timeout)"
        ;;
    *)
        log "ERROR: bilinmeyen komut: ${COMMAND}"
        exit 1
        ;;
esac

exit 0
