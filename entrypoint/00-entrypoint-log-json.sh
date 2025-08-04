#!/bin/sh
# vim:sw=4:ts=4:sts=4:et
#------------------------------------------------------------------------------
# This entrypoint script changes entrypoint_log function inside other
# entrypoint scripts to JSON logging format.
#------------------------------------------------------------------------------

set -eu

LC_ALL=C
ME=$(basename "$0")

case "${NGINX_ENTRYPOINT_JSON_LOGGING:-}" in
  "" | "0" | "false" | "False" | "FALSE" \
  | "n" | "N" | "no" | "No" | "NO" \
  | "off" | "Off" | "OFF") exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || {
    entrypoint_log "$ME: ERROR: jq not found, JSON logging is skipped"
    exit 0
}

entrypoint_log_json_function="$(cat <<'EOF'
entrypoint_log() {
    default_level="INFO"
    raw="$1"
    script_name=""
    level=""
    body=""

    # Parse into 3 parts
    num_colons=$(printf "%s" "$raw" | awk -F: '{print NF-1}')
    if [ "$num_colons" -ge 2 ]; then
        script_name=$(printf "%s" "$raw" | cut -d: -f1)
        level=$(printf "%s" "$raw" | cut -d: -f2 | sed 's/^[[:space:]]*//')
        body=$(printf "%s" "$raw" | cut -d: -f3- | sed 's/^[[:space:]]*//')
    elif [ "$num_colons" -eq 1 ]; then
        script_name=$(printf "%s" "$raw" | cut -d: -f1)
        body=$(printf "%s" "$raw" | cut -d: -f2- | sed 's/^[[:space:]]*//')
        level=$(printf "%s" "$body" | cut -d' ' -f1)
        case "$(printf "%s" "$level" | tr '[:lower:]' '[:upper:]')" in
            ERROR|WARN|WARNING|INFO|DEBUG) ;;
            *) level="$default_level" ;;
        esac
    else
        body="$raw"
        level="$default_level"
    fi

    # Normalize level
    level_uc=$(printf "%s" "$level" | tr '[:lower:]' '[:upper:]')
    case "$level_uc" in
        WARN|WARNING) level="WARN" ;;
        ERROR)        level="ERROR" ;;
        INFO)         level="INFO" ;;
        DEBUG)        level="DEBUG" ;;
        *)            level="$default_level" ;;
    esac

    # ISO 8601 timestamp in local time (using TZ if defined)
    timestamp=$(date +"%Y-%m-%dT%H:%M:%S%z")

    # Convert +hhmm to +hh:mm (ISO 8601 compliance)
    timestamp="${timestamp%??}:${timestamp: -2}"

    if [ -n "$script_name" ]; then
        jq -c -M -n \
            --arg level "$level" \
            --arg body "$body" \
            --arg script_name "$script_name" \
            --arg timestamp "$timestamp" \
            '{timestamp: $timestamp, level: $level, body: $body, script_name: $script_name}'
    else
        jq -c -M -n \
            --arg level "$level" \
            --arg body "$body" \
            --arg timestamp "$timestamp" \
            '{timestamp: $timestamp, level: $level, body: $body}'
    fi
}
EOF
)"
eval "$entrypoint_log_json_function"

marker="# changed by $ME"

replace_entrypoint_log_function() {
    local file="$1"

    if [ ! -w "$file" ]; then
      entrypoint_log "$ME: ERROR: $file is not writable"
      return 0
    fi

    {
        echo "$marker on $(date)"
        echo "$entrypoint_log_json_function"
    } > /tmp/entrypoint_log_json.tmp

    sed -i -e '/^entrypoint_log()[[:space:]]*{/,/^}/{
        /^entrypoint_log()[[:space:]]*{/r /tmp/entrypoint_log_json.tmp
        d
    }' "$file"

    rm -f "/tmp/entrypoint_log_json.tmp"
}

patch_entrypoint_scripts_logging() {
    local entrypoint_dir="/docker-entrypoint.d"
    if [ ! -w "$entrypoint_dir" ]; then
        entrypoint_log "$ME: ERROR: No write permission on $entrypoint_dir"
        return 0
    fi

    local self="$(realpath "$0")"
    for file in $entrypoint_dir/*sh; do
        [ -f "$file" ] || continue

        if [ "$(realpath "$file")" = "$self" ]; then
            continue
        fi

        if grep -qF "$marker" "$file"; then
            entrypoint_log "$ME: INFO: $file already patched"
            continue
        fi

        if grep -qE '^\s*entrypoint_log\(\)\s*\{' "$file"; then
            entrypoint_log "$ME: INFO: replacing existing entrypoint_log() function in $file"

            replace_entrypoint_log_function "$file"
        else
            entrypoint_log "$ME: INFO: no entrypoint_log() found in $file to replace"
        fi
    done
}

patch_entrypoint_scripts_logging
