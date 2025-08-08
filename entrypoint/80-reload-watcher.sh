#!/bin/sh
# vim:sw=4:ts=4:sts=4:et
#------------------------------------------------------------------------------
# This entrypoint script runs an autoreload watcher in background that watches
# for templates to have changes in runtime.
# If any template has a modification, all templates will be updated.
# If env watch file exists, environment variables will be dynamically
# loaded and unloaded on every change.
#------------------------------------------------------------------------------

set -eu

LC_ALL=C
ME=$(basename "$0")

case "${NGINX_ENTRYPOINT_RELOAD_WATCHER:-}" in
  "" | "0" | "false" | "False" | "FALSE" \
  | "n" | "N" | "no" | "No" | "NO" \
  | "off" | "Off" | "OFF") exit 0 ;;
esac

. /docker-entrypoint.d/18-better-envsubst-on-templates.libsh

entrypoint_log() {
    if [ -z "${NGINX_ENTRYPOINT_QUIET_LOGS:-}" ]; then
        echo "$@"
    fi
}

wait_for_nginx_start() {
    entrypoint_log "$ME: INFO: Waiting for NGINX to start..."
    while [ ! -f /var/run/nginx.pid ]; do
        sleep 0.1
    done
    entrypoint_log "$ME: INFO: Detected NGINX start, watcher started"
}

auto_remove_unsynced_files() {
    local target_template_dir="$1"
    local output_dir="$2"

    local file full_path
    find "$output_dir" -follow -type f -name "$template_filename_pattern" -print | sort -V | while read -r file; do
        full_path="$target_template_dir/$(basename "$file")"
        if [ ! -f "$full_path" ]; then
            entrypoint_log "$ME: INFO: Removing $file as it no longer exists in $target_template_dir"
            rm -f "$file"
        fi
    done
}

auto_sync_files_in_dir() {
    local target_template_dir="$1"
    local output_dir="$2"

    if [ -d "$target_template_dir" ] && [ -w "$output_dir" ]; then
        better_envsubst_dir "$target_template_dir" "$output_dir"
        auto_remove_unsynced_files "$target_template_dir" "$output_dir"
    fi
}

sync_templates() {
    entrypoint_log "$ME: INFO: Syncing NGINX templates..."

    (
        load_watch_env_file
        auto_sync_files_in_dir "$conf_template_dir" "$conf_output_dir"
        auto_sync_files_in_dir "$stream_template_dir" "$stream_output_dir"
        auto_sync_files_in_dir "$sites_available_template_dir" "$sites_available_output_dir"
        auto_sync_files_in_dir "$common_template_dir" "$common_output_dir"

        if [ -f "$main_template_file" ] && [ -w "$main_output_file" ]; then
            better_envsubst_file "$main_template_file" "$main_output_file"
        fi
    )
}

update_symlinks() {
    entrypoint_log "$ME: INFO: Cleaning up old symbolic links..."

    local link full_path
    find "$sites_enabled_output_dir" -type l -name "$template_filename_pattern" | while read -r link; do
        full_path=$(readlink "$link")
        if [ ! -e "$full_path" ]; then
            entrypoint_log "$ME: INFO: Removing stale symlink $link (linked file $full_path does not exist)"
            rm -f "$link"
        fi
    done

    entrypoint_log "$ME: INFO: Creating symbolic links in $sites_enabled_output_dir..."
    find "$sites_available_output_dir" -name "$template_filename_pattern" -exec ln -sf {} "$sites_enabled_output_dir" \;
}

try_reload_nginx() {
    entrypoint_log "$ME: INFO: Validating NGINX configuration..."

    local nginx_test_output=$(nginx -t 2>&1)
    local nginx_test_status=$?

    if [ "$nginx_test_status" -ne 0 ]; then
        entrypoint_log "$ME: WARN: nginx -t: $nginx_test_output"
        entrypoint_log "$ME: WARN: [!!!] Configuration test failed, NGINX restart was skipped!"
        return 0
    fi

    entrypoint_log "$ME: INFO: nginx -t: $nginx_test_output"
    entrypoint_log "$ME: INFO: [v] Configuration is valid, restarting NGINX..."

    local nginx_reload_output=$(nginx -s reload 2>&1)
    local nginx_reload_status=$?

    if [ "$nginx_reload_status" -eq 0 ]; then
        entrypoint_log "$ME: INFO: nginx -s reload: $nginx_reload_output"
        entrypoint_log "$ME: INFO: NGINX reload complete"
    else
        entrypoint_log "$ME: ERROR: nginx -s reload: $nginx_reload_output"
        entrypoint_log "$ME: ERROR: NGINX reload failed"
    fi
}

run_update() {
    sync_templates
    update_symlinks
    try_reload_nginx
}

autoreload_watcher() {
    local template_dir="${NGINX_ENVSUBST_TEMPLATE_DIR:-/etc/nginx/templates}"
    local conf_template_dir="${template_dir}/conf.d"
    local stream_template_dir="${template_dir}/stream-conf.d"
    local sites_available_template_dir="${template_dir}/sites-available"
    local common_template_dir="${template_dir}/common"
    local main_template_file="${template_dir}/main/nginx.conf"
    local conf_output_dir="${NGINX_ENVSUBST_OUTPUT_DIR:-/etc/nginx/conf.d}"
    local stream_output_dir="${NGINX_ENVSUBST_STREAM_OUTPUT_DIR:-/etc/nginx/stream-conf.d}"
    local sites_available_output_dir="${NGINX_ENVSUBST_SITES_AVAILABLE_OUTPUT_DIR:-/etc/nginx/sites-available}"
    local sites_enabled_output_dir="${NGINX_ENVSUBST_SITES_ENABLED_OUTPUT_DIR:-/etc/nginx/sites-enabled}"
    local common_output_dir="${NGINX_ENVSUBST_COMMON_OUTPUT_DIR:-/etc/nginx/common}"
    local main_output_file="/etc/nginx/nginx.conf"
    local template_filename_pattern='*.conf'
    local watch_env_file="${NGINX_ENVSUBST_WATCH_ENV_FILE:-/mount/nginx.env}"

    if [ ! -d "$template_dir" ]; then
        entrypoint_log "$ME: ERROR: Template directory $template_dir does not exist"
        return 0
    fi

    command -v inotifywait >/dev/null 2>&1 || {
        entrypoint_log "$ME: ERROR: inotifywait not found, cannot start watcher"
        return 0
    }

    if [ ! -f "$watch_env_file" ]; then
        entrypoint_log "$ME: WARN: Watch env file $watch_env_file does not exist"
        return 0
    fi

    set --
    [ -d "$conf_template_dir" ] && set -- "$@" "$conf_template_dir"
    [ -d "$stream_template_dir" ] && set -- "$@" "$stream_template_dir"
    [ -d "$sites_available_template_dir" ] && set -- "$@" "$sites_available_template_dir"
    [ -d "$common_template_dir" ] && set -- "$@" "$common_template_dir"
    [ -f "$main_template_file" ] && set -- "$@" "$(dirname "$main_template_file")"

    if [ "$#" -eq 0 ]; then
        entrypoint_log "$ME: WARN: No paths to watch, watcher shut down"
        return 0
    fi
    entrypoint_log "$ME: INFO: Watching paths: $*"

    wait_for_nginx_start

    local DIR FILE EVENT full_path
    inotifywait -m -e modify,create,delete,move --format '%w %f %e' "$@" |
    while IFS=' ' read -r DIR FILE EVENT; do
        full_path="${DIR%/}/$FILE"

        case "$FILE" in
            *.conf | *.conf~ | *.conf_ | *.conf.*) ;;
            *) continue ;;
        esac

        entrypoint_log "$ME: INFO: Detected event $EVENT on $full_path"

        run_update
    done
}

autoreload_watcher &
