#!/bin/sh
# vim:sw=4:ts=4:sts=4:et
#------------------------------------------------------------------------------
# This entrypoint script removes specified scripts from the NGINX entrypoint
# directory.
# NGINX_ENTRYPOINT_REMOVE_SCRIPTS is used to define space-separated script
# names to remove.
#------------------------------------------------------------------------------

set -eu

LC_ALL=C
ME=$(basename "$0")

[ -z "${NGINX_ENTRYPOINT_REMOVE_SCRIPTS:-}" ] && exit 0

entrypoint_log() {
    if [ -z "${NGINX_ENTRYPOINT_QUIET_LOGS:-}" ]; then
        echo "$@"
    fi
}

remove_entrypoint_scripts() {
    entrypoint_dir="/docker-entrypoint.d"

    if [ ! -w "$entrypoint_dir" ]; then
        entrypoint_log "$ME: ERROR: No write permission on $entrypoint_dir"
        return 0
    fi

    for script in $NGINX_ENTRYPOINT_REMOVE_SCRIPTS; do
        full_path="$entrypoint_dir/$script"

        if [ -f "$full_path" ]; then
            entrypoint_log "$ME: INFO: Removing $full_path"
            if ! rm -f "$full_path"; then
                entrypoint_log "$ME: ERROR: Failed to remove $full_path"
            fi
        else
            entrypoint_log "$ME: WARN: $full_path not found, skipping"
        fi
    done
}

remove_entrypoint_scripts
