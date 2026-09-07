#!/usr/bin/env bash

CONFIG_PATH=/data/options.json

INTERFACE="$(jq -r '.interface' "${CONFIG_PATH}")"
CONNECTION="$(jq -r '.connection' "${CONFIG_PATH}")"
GATEWAY="$(jq -r '.gateway' "${CONFIG_PATH}")"
CHECK_INTERVAL="$(jq -r '.check_interval' "${CONFIG_PATH}")"
MAX_RECOVERY_ATTEMPTS="$(jq -r '.max_recovery_attempts' "${CONFIG_PATH}")"

SUPERVISOR_TOKEN="${SUPERVISOR_TOKEN}"

RECOVERY_ATTEMPTS=0

log() {
    echo "[INFO] $1"
}

debug() {
    echo "[DEBUG] $1"
}

ha_service() {
    local domain="$1"
    local service="$2"
    local data="$3"

    curl -sS \
        --max-time 10 \
        -X POST \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${data}" \
        "http://supervisor/core/api/services/${domain}/${service}" \
        >/dev/null
}

increment_recovery_counter() {
    ha_service \
        counter \
        increment \
        '{"entity_id":"counter.wifi_recovery_attempts"}'
}

set_last_recovery_time() {
    local timestamp="$1"

    ha_service \
        input_datetime \
        set_datetime \
        "{\"entity_id\":\"input_datetime.wifi_last_recovery\",\"datetime\":\"${timestamp}\"}"
}

wifi_connected() {
    local state
    local nmcli_out

    #state="$(nmcli -t -f DEVICE,STATE device status 2>/dev/null |
        #awk -F: -v dev="${INTERFACE}" '$1 == dev {print $2}')"
    nmcli_out="$(nmcli -t -f DEVICE,STATE device status)"
    debug "nmcli_out = $nmcli_out"

    state = `echo $nmcli_out | awk -F: -v dev="${INTERFACE}" '$1 == dev {print $2}'`

    debug "Wi-Fi interface ${INTERFACE} state: ${state}"

    [ "${state}" = "connected" ]
}

gateway_reachable() {
    ping -c 1 -W 2 "${GATEWAY}" >/dev/null 2>&1
}

network_ok() {
    wifi_connected && gateway_reachable
}

restart_wifi() {
    log "Attempting Wi-Fi recovery on ${INTERFACE}"

    nmcli connection down "${CONNECTION}" >/dev/null 2>&1 || true
    sleep 2

    nmcli connection up "${CONNECTION}" >/dev/null 2>&1
}

log "---------------------------------------------------"
log "Wi-Fi Watchdog started"
log "Interface: ${INTERFACE}"
log "Connection: ${CONNECTION}"
log "Gateway: ${GATEWAY}"
log "Check interval: ${CHECK_INTERVAL}s"
log "Maximum recovery attempts: ${MAX_RECOVERY_ATTEMPTS}"
log "---------------------------------------------------"

while true; do

    TIMESTAMP="$(date -Iseconds)"
    MAX_REPORTED='N'

    if network_ok; then

        debug "${TIMESTAMP}: Wi-Fi OK"
        RECOVERY_ATTEMPTS=0
        MAX_REPORTED='N'

    else

        RECOVERY_ATTEMPTS=$((RECOVERY_ATTEMPTS + 1))

        if [ "${RECOVERY_ATTEMPTS}" -le "${MAX_RECOVERY_ATTEMPTS}" ]; then
            log "${TIMESTAMP}: Wi-Fi connectivity lost"
            log "${TIMESTAMP}: Recovery attempt ${RECOVERY_ATTEMPTS}/${MAX_RECOVERY_ATTEMPTS}"

            increment_recovery_counter

            set_last_recovery_time "${TIMESTAMP}"

            restart_wifi
        else
            if [[ "$MAX_REPORTED" = "N" ]]
            then
                log "${TIMESTAMP}: Maximum recovery attempts reached"
                MAX_REPORTED='Y'
            fi
        fi

    fi

    sleep "${CHECK_INTERVAL}"

done