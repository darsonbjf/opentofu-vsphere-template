#!/bin/bash

CEPH_RGW_BACKEND_REGION="default"
CEPH_RGW_CACHE_DISABLED="${CEPH_RGW_DISABLE_CACHE:-0}"
CEPH_RGW_CACHE_REFRESH="${CEPH_RGW_REFRESH_CACHE:-0}"
CEPH_RGW_PROD_CACHE_TTL_SECONDS=1800

rgw_cache_enabled() {
    [ "$CEPH_RGW_CACHE_DISABLED" != "1" ]
}

rgw_cache_load_enabled() {
    rgw_cache_enabled && [ "$CEPH_RGW_CACHE_REFRESH" != "1" ]
}

rgw_cache_base_dir() {
    if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
        printf "%s/opentofu-vsphere-template/rgw-credentials" "$XDG_RUNTIME_DIR"
    else
        printf "%s/.cache/opentofu-vsphere-template/rgw-credentials" "$HOME"
    fi
}

rgw_cache_file() {
    local environment="$1"
    printf "%s/%s.env" "$(rgw_cache_base_dir)" "$environment"
}

rgw_today() {
    date +%F
}

rgw_now_epoch() {
    date +%s
}

clear_rgw_credentials_cache_values() {
    CEPH_RGW_CACHE_DATE=""
    CEPH_RGW_CACHE_SAVED_AT=""
    CEPH_RGW_ACCESS_KEY_ID=""
    CEPH_RGW_SECRET_ACCESS_KEY=""
}

rgw_prod_cache_valid() {
    local now
    local cache_age

    case "${CEPH_RGW_CACHE_SAVED_AT:-}" in
        "" | *[!0-9]*)
            return 1
            ;;
    esac

    now=$(rgw_now_epoch)
    if [ "$CEPH_RGW_CACHE_SAVED_AT" -gt "$now" ]; then
        return 1
    fi

    cache_age=$((now - CEPH_RGW_CACHE_SAVED_AT))
    [ "$cache_age" -le "$CEPH_RGW_PROD_CACHE_TTL_SECONDS" ]
}

rgw_cache_valid_for_environment() {
    local environment="$1"
    local cache_date

    if [ -z "${CEPH_RGW_ACCESS_KEY_ID:-}" ] ||
       [ -z "${CEPH_RGW_SECRET_ACCESS_KEY:-}" ]; then
        return 1
    fi

    case "$environment" in
        prod)
            rgw_prod_cache_valid
            ;;
        *)
            cache_date=$(rgw_today)
            [ "${CEPH_RGW_CACHE_DATE:-}" = "$cache_date" ]
            ;;
    esac
}

rgw_cache_expiry_message() {
    local environment="$1"

    case "$environment" in
        prod)
            printf "por ate 30 minutos"
            ;;
        *)
            printf "ate 00:00"
            ;;
    esac
}

load_rgw_credentials_cache() {
    local environment="$1"
    local cache_file

    if ! rgw_cache_load_enabled; then
        return 1
    fi

    cache_file=$(rgw_cache_file "$environment")
    if [ ! -f "$cache_file" ]; then
        return 1
    fi

    chmod 600 "$cache_file" 2>/dev/null || true

    clear_rgw_credentials_cache_values

    # shellcheck disable=SC1090
    source "$cache_file"

    if ! rgw_cache_valid_for_environment "$environment"; then
        rm -f "$cache_file"
        clear_rgw_credentials_cache_values
        return 1
    fi

    export CEPH_RGW_ACCESS_KEY_ID
    export CEPH_RGW_SECRET_ACCESS_KEY
    echo "[INFO] Credenciais RGW do ambiente $environment carregadas do cache local $(rgw_cache_expiry_message "$environment")."
}

save_rgw_credentials_cache() {
    local environment="$1"
    local cache_dir
    local cache_file

    if ! rgw_cache_enabled; then
        return 0
    fi

    cache_dir=$(rgw_cache_base_dir)
    cache_file=$(rgw_cache_file "$environment")

    mkdir -p "$cache_dir" || return 1
    chmod 700 "$cache_dir" 2>/dev/null || true

    {
        printf "CEPH_RGW_CACHE_DATE=%q\n" "$(rgw_today)"
        printf "CEPH_RGW_CACHE_SAVED_AT=%q\n" "$(rgw_now_epoch)"
        printf "CEPH_RGW_ACCESS_KEY_ID=%q\n" "$CEPH_RGW_ACCESS_KEY_ID"
        printf "CEPH_RGW_SECRET_ACCESS_KEY=%q\n" "$CEPH_RGW_SECRET_ACCESS_KEY"
    } > "$cache_file" || return 1

    chmod 600 "$cache_file" 2>/dev/null || true
    echo "[INFO] Credenciais RGW do ambiente $environment mantidas em cache local $(rgw_cache_expiry_message "$environment")."
}

read_visible_value() {
    local prompt="$1"
    local value

    if { : < /dev/tty; } 2>/dev/null && { : > /dev/tty; } 2>/dev/null; then
        printf "%s" "$prompt" > /dev/tty
        IFS= read -r value < /dev/tty || return 1
    else
        printf "%s" "$prompt" >&2
        IFS= read -r value || return 1
    fi

    printf "%s" "$value"
}

read_silent_value() {
    local prompt="$1"
    local value

    if { : < /dev/tty; } 2>/dev/null && { : > /dev/tty; } 2>/dev/null; then
        printf "%s" "$prompt" > /dev/tty
        IFS= read -r -s value < /dev/tty || return 1
        printf "\n" > /dev/tty
    else
        printf "%s" "$prompt" >&2
        IFS= read -r -s value || return 1
        printf "\n" >&2
    fi

    printf "%s" "$value"
}

read_secret_value() {
    local prompt="$1"

    if [ "${CEPH_RGW_VISIBLE_SECRET:-0}" = "1" ]; then
        read_visible_value "$prompt"
    else
        read_silent_value "$prompt"
    fi
}

export_opentofu_s3_backend_credentials() {
    export AWS_ACCESS_KEY_ID="$CEPH_RGW_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$CEPH_RGW_SECRET_ACCESS_KEY"
    export AWS_DEFAULT_REGION="$CEPH_RGW_BACKEND_REGION"
}

validate_rgw_backend_credentials() {
    local missing=0

    if [ -z "${CEPH_RGW_ACCESS_KEY_ID:-}" ]; then
        echo "[ERRO] CEPH_RGW_ACCESS_KEY_ID nao definido. Obtenha a credencial RGW no gerenciador de senhas."
        missing=1
    fi

    if [ -z "${CEPH_RGW_SECRET_ACCESS_KEY:-}" ]; then
        echo "[ERRO] CEPH_RGW_SECRET_ACCESS_KEY nao definido. Obtenha a credencial RGW no gerenciador de senhas."
        missing=1
    fi

    if [ "$missing" -ne 0 ]; then
        return 1
    fi

    export_opentofu_s3_backend_credentials
}

load_rgw_backend_credentials() {
    local environment="$1"

    if [ -n "${CEPH_RGW_ACCESS_KEY_ID:-}" ] &&
       [ -n "${CEPH_RGW_SECRET_ACCESS_KEY:-}" ]; then
        save_rgw_credentials_cache "$environment" || {
            echo "[ERRO] Falha ao salvar cache local de credenciais RGW."
            return 1
        }
        export_opentofu_s3_backend_credentials
        return 0
    fi

    if [ -z "${CEPH_RGW_ACCESS_KEY_ID:-}" ] &&
       [ -z "${CEPH_RGW_SECRET_ACCESS_KEY:-}" ] &&
       load_rgw_credentials_cache "$environment"; then
        validate_rgw_backend_credentials
        return $?
    fi

    if [ -n "${CEPH_RGW_ACCESS_KEY_ID:-}" ] ||
       [ -n "${CEPH_RGW_SECRET_ACCESS_KEY:-}" ]; then
        echo "[INFO] Credenciais RGW do ambiente $environment incompletas no ambiente."
    else
        echo "[INFO] Credenciais RGW do ambiente $environment nao encontradas no ambiente nem no cache local valido."
    fi

    if [ "${CEPH_RGW_VISIBLE_SECRET:-0}" = "1" ]; then
        echo "[INFO] Cole os valores do gerenciador de senhas abaixo. Access key e secret ficarao visiveis porque CEPH_RGW_VISIBLE_SECRET=1."
    else
        echo "[INFO] Cole os valores do gerenciador de senhas abaixo. CEPH_RGW_ACCESS_KEY_ID ficara visivel; CEPH_RGW_SECRET_ACCESS_KEY ficara oculto."
    fi

    if [ -z "${CEPH_RGW_ACCESS_KEY_ID:-}" ]; then
        CEPH_RGW_ACCESS_KEY_ID=$(read_visible_value "CEPH_RGW_ACCESS_KEY_ID: ") || return 1
        export CEPH_RGW_ACCESS_KEY_ID
    fi

    if [ -z "${CEPH_RGW_SECRET_ACCESS_KEY:-}" ]; then
        CEPH_RGW_SECRET_ACCESS_KEY=$(read_secret_value "CEPH_RGW_SECRET_ACCESS_KEY: ") || return 1
        export CEPH_RGW_SECRET_ACCESS_KEY
    fi

    validate_rgw_backend_credentials || return 1
    save_rgw_credentials_cache "$environment" || {
        echo "[ERRO] Falha ao salvar cache local de credenciais RGW."
        return 1
    }
}
