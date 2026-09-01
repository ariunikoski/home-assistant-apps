
```bash
#!/usr/bin/with-contenv bashio

REPORT_URL="https://unikoski.org/home_assistant_status"
INTERFACE="wlp2s0"
INTERVAL=300

API_KEY="$(bashio::config 'api_key')"

log() {
    bashio::log.info "$1"
}

log "=========================================="
log "HA Status Monitor starting"
log "Interface: ${INTERFACE}"
log "Report URL: ${REPORT_URL}"
log "Report interval: ${INTERVAL} seconds"
log "=========================================="

if [ -z "${API_KEY}" ]; then
    bashio::log.error "No API key has been configured."
    exit 1
fi

get_entity_state() {
    local entity_id="$1"

    curl -fsS \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        -H "Content-Type: application/json" \
        --max-time 10 \
        "http://supervisor/core/api/states/${entity_id}"
}

send_status() {
    local status="$1"
    local status_message="$2"
    local smart_home_status="$3"
    local connected_message="$4"
    local disconnected_message="$5"

    curl -fsS \
        --max-time 15 \
        -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${API_KEY}" \
        --data-urlencode "status=${status}" \
        --data-urlencode "status_message=${status_message}" \
        --data-urlencode "smart_home_status=${smart_home_status}" \
        --data-urlencode "connected_message=${connected_message}" \
        --data-urlencode "disconnected_message=${disconnected_message}" \
        "${REPORT_URL}" \
        >/dev/null
}

while true; do

    TIMESTAMP="$(date -Iseconds)"

    HOME_ASSISTANT_HEALTH="$(get_entity_state sensor.home_assistant_health || true)"
    SMART_HOME_HEALTH="$(get_entity_state sensor.smart_home_device_health || true)"

    HEALTH_STATE="$(printf '%s' "${HOME_ASSISTANT_HEALTH}" |
        jq -r '.state // "unknown"')"

    STATUS_MESSAGE="${HEALTH_STATE}"

    if [ "${HEALTH_STATE}" = "Healthy" ]; then
        STATUS="ok"
    else
        STATUS="ko"
    fi

    SMART_HOME_STATUS="$(printf '%s' "${SMART_HOME_HEALTH}" |
        jq -r '.state // "unknown" | ascii_downcase')"

    CONNECTED_DEVICES="$(printf '%s' "${SMART_HOME_HEALTH}" |
        jq -r '.attributes.connected_devices // "0"')"

    TOTAL_DEVICES="$(printf '%s' "${SMART_HOME_HEALTH}" |
        jq -r '.attributes.total_devices // "0"')"

    CONNECTED_MESSAGE="${CONNECTED_DEVICES}/${TOTAL_DEVICES}"

    DISCONNECTED_MESSAGE="$(printf '%s' "${SMART_HOME_HEALTH}" |
        jq -r '.attributes.disconnected_names // ""')"

    log "${TIMESTAMP}: status=${STATUS}, status_message=${STATUS_MESSAGE}, smart_home_status=${SMART_HOME_STATUS}, connected=${CONNECTED_MESSAGE}, disconnected=${DISCONNECTED_MESSAGE}"

    if send_status \
        "${STATUS}" \
        "${STATUS_MESSAGE}" \
        "${SMART_HOME_STATUS}" \
        "${CONNECTED_MESSAGE}" \
        "${DISCONNECTED_MESSAGE}"; then

        log "${TIMESTAMP}: status report sent successfully"

    else

        bashio::log.warning \
            "${TIMESTAMP}: failed to send status report"

    fi

    sleep "${INTERVAL}"

done
```
