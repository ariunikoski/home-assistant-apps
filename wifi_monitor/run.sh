#!/usr/bin/with-contenv bash

CONFIG_PATH=/data/options.json

INTERFACE="$(jq -r '.interface' "${CONFIG_PATH}")"
CONNECTION="$(jq -r '.connection' "${CONFIG_PATH}")"
GATEWAY="$(jq -r '.gateway' "${CONFIG_PATH}")"
CHECK_INTERVAL="$(jq -r '.check_interval' "${CONFIG_PATH}")"
MAX_RECOVERY_ATTEMPTS="$(jq -r '.max_recovery_attempts' "${CONFIG_PATH}")"
DEBUG="$(jq -r '.debug' "${CONFIG_PATH}")"

SUPERVISOR_TOKEN="${SUPERVISOR_TOKEN}"
RECOVERY_ATTEMPTS=0
MAX_REPORTED='N'

log() {
    echo "[INFO] $1"
}

debug() {
    if [[ "$DEBUG" = 'true' ]]
    then
        echo "[DEBUG] $1"
    fi
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
        '{"entity_id":"counter.wifi_recovery_attemp"}'
}

set_last_recovery_time() {
    local timestamp="$1"

    ha_service \
        input_datetime \
        set_datetime \
        "{\"entity_id\":\"input_datetime.wifi_last_recovery\",\"datetime\":\"${timestamp}\"}"
}

wifi_connected() {
    local response
    local connected

    response="$(curl -sS \
        --max-time 10 \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        "http://supervisor/network/interface/${INTERFACE}/info")"

    debug "${INTERFACE} response: ${response}"

    connected="$(printf '%s' "${response}" |
        jq -r '.data.connected // false')"

    debug "${INTERFACE} connected: ${connected}"

    [ "${connected}" = "true" ]
}

gateway_reachable() {
    ping -c 1 -W 2 "${GATEWAY}" >/dev/null 2>&1
}

network_ok() {
    wifi_connected && gateway_reachable
}
restart_wifi() {
    log "Requesting Supervisor network reload"

    local response

    response="$(curl -sS \
        --max-time 15 \
        -X POST \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        -H "Content-Type: application/json" \
        "http://supervisor/network/reload")"

    log "Network reload response: ${response}"

    sleep 10
}

supervisor_test() {
    local response

    response="$(curl -sS \
        --max-time 10 \
        -w '\nHTTP_STATUS:%{http_code}' \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        -H "Content-Type: application/json" \
        "http://supervisor/supervisor/info")"

    log "Supervisor test:"
    log "${response}"
}

log "---------------------------------------------------"
log "Wi-Fi Watchdog started"
log "Interface: ${INTERFACE}"
log "Connection: ${CONNECTION}"
log "Gateway: ${GATEWAY}"
log "Check interval: ${CHECK_INTERVAL}s"
log "Maximum recovery attempts: ${MAX_RECOVERY_ATTEMPTS}"
log "Debug: ${DEBUG}"
if [[ "$DEBUG"] = 'true' ]]
then
  supervisor_test
fi
debug "SUPERVISOR_TOKEN length: ${#SUPERVISOR_TOKEN}"
debug "[DEBUG] with-contenv: $(command -v with-contenv)"
debug "[DEBUG] bash: $(command -v bash)"
debug "[DEBUG] bashio: $(command -v bashio)"
log "---------------------------------------------------"

while true; do

    TIMESTAMP="$(date -Iseconds)"

    if network_ok; then
        debug "${TIMESTAMP}: Wi-Fi OK"
        RECOVERY_ATTEMPTS=0
        MAX_REPORTED='N'

    else
        if [ "${RECOVERY_ATTEMPTS}" -le "${MAX_RECOVERY_ATTEMPTS}" ]; then
            log "${TIMESTAMP}: Wi-Fi connectivity lost"
            log "${TIMESTAMP}: Recovery attempt ${RECOVERY_ATTEMPTS}/${MAX_RECOVERY_ATTEMPTS}"

            RECOVERY_ATTEMPTS=$((RECOVERY_ATTEMPTS + 1))

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