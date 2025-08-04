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
    local nginx_conf_template="${template_dir}/nginx.conf"
    local conf_output_dir="${NGINX_ENVSUBST_OUTPUT_DIR:-/etc/nginx/conf.d}"
    local stream_output_dir="${NGINX_ENVSUBST_STREAM_OUTPUT_DIR:-/etc/nginx/stream-conf.d}"
    local sites_available_output_dir="${NGINX_ENVSUBST_SITES_AVAILABLE_OUTPUT_DIR:-/etc/nginx/sites-available}"
    local sites_enabled_output_dir="${NGINX_ENVSUBST_SITES_ENABLED_OUTPUT_DIR:-/etc/nginx/sites-enabled}"
    local nginx_conf_output="/etc/nginx/nginx.conf"
    local template_filename_pattern='*.conf'

    if [ ! -d "$template_dir" ]; then
        entrypoint_log "$ME: ERROR: $template_dir does not exist"
        return 0
    fi

    if [ -f "$nginx_conf_template" ]; then
        if [ ! -w "$nginx_conf_output" ]; then
            entrypoint_log "$ME: ERROR: $nginx_conf_template exists, but $nginx_conf_output is not writable"
        else
            if [ ! -z "${NGINX_ENVSUBST_IGNORE_NGINX_CONF_TEMPLATE_AT_START:-}" ]; then
                entrypoint_log "$ME: Running envsubst on $nginx_conf_template to $nginx_conf_output"
                better_envsubst_file "$nginx_conf_template" "$nginx_conf_output"
            else
                entrypoint_log "$ME: INFO: envsubst on $nginx_conf_template was ignored at start"
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

        if [ -w "$nginx_conf_output" ]; then
            add_include_sites_available_block
        fi
    fi
}

better_auto_envsubst
