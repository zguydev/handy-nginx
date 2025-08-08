#!/bin/sh
# vim:sw=4:ts=4:sts=4:et
#------------------------------------------------------------------------------
# This entrypoint script runs envsubst on templates just like the original
# NGINX script, but better.
# It is recommended to remove the original 20-envsubst-on-templates.sh script
# from the entrypoint directory.
#------------------------------------------------------------------------------

set -eu

LC_ALL=C
ME=$(basename "$0")

. /docker-entrypoint.d/18-better-envsubst-on-templates.libsh

better_auto_envsubst() {
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

    if [ ! -f "$watch_env_file" ]; then
        entrypoint_log "$ME: WARN: Watch env file $watch_env_file does not exist"
        return 0
    fi

    (
        load_watch_env_file
        if [ -f "$main_template_file" ]; then
            if [ ! -w "$main_output_file" ]; then
                entrypoint_log "$ME: ERROR: $main_template_file exists, but $main_output_file is not writable"
            else
                if [ -z "${NGINX_ENVSUBST_IGNORE_NGINX_CONF_TEMPLATE_AT_START:-}" ]; then
                    entrypoint_log "$ME: Running envsubst on $main_template_file to $main_output_file"
                    better_envsubst_file "$main_template_file" "$main_output_file"
                else
                    entrypoint_log "$ME: INFO: envsubst on $main_template_file was ignored at start"
                fi
            fi
        fi

        if test -n "$(find "$conf_template_dir" -follow -type f -name "$template_filename_pattern" -print -quit)"; then
            better_envsubst_dir "$conf_template_dir" "$conf_output_dir"
        fi

        if test -n "$(find "$stream_template_dir" -follow -type f -name "$template_filename_pattern" -print -quit)"; then
            better_envsubst_dir "$stream_template_dir" "$stream_output_dir"
            add_stream_block
        fi

        if test -n "$(find "$sites_available_template_dir" -follow -type f -name "$template_filename_pattern" -print -quit)"; then
            better_envsubst_dir "$sites_available_template_dir" "$sites_available_output_dir"
            update_sites_enabled_symlinks

            if [ -w "$main_output_file" ]; then
                add_include_sites_available_block
            fi
        fi

        if test -n "$(find "$common_template_dir" -follow -type f -name "$template_filename_pattern" -print -quit)"; then
            better_envsubst_dir "$common_template_dir" "$common_output_dir"
        fi
    )
}

better_auto_envsubst
