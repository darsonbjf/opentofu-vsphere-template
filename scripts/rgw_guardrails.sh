#!/bin/bash

RGW_GUARDRAIL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

rgw_expected_bucket() {
    case "$1" in
        dev) echo "opentofu-vsphere-template-dev" ;;
        homolog) echo "opentofu-vsphere-template-homolog" ;;
        prod) echo "opentofu-vsphere-template-prod" ;;
        *) return 1 ;;
    esac
}

rgw_hcl_value() {
    local key="$1"
    local file="$2"

    awk -v key="$key" '
        $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            value = $0
            sub(/^[^=]*=[[:space:]]*/, "", value)
            sub(/[[:space:]]*#.*/, "", value)
            gsub(/"/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            print value
            exit
        }
    ' "$file"
}

rgw_backend_endpoint() {
    local file="$1"

    awk '
        /^[[:space:]]*endpoints[[:space:]]*=/ { in_endpoints = 1; next }
        in_endpoints && /^[[:space:]]*}/ { in_endpoints = 0 }
        in_endpoints && /^[[:space:]]*s3[[:space:]]*=/ {
            value = $0
            sub(/^[^=]*=[[:space:]]*/, "", value)
            sub(/[[:space:]]*#.*/, "", value)
            gsub(/"/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            print value
            exit
        }
    ' "$file"
}

rgw_tfvars_environment() {
    local file="$1"
    rgw_hcl_value "environment" "$file"
}

rgw_critical_abort() {
    local environment="$1"
    local expected_bucket="$2"
    local configured_bucket="$3"
    local endpoint="$4"
    local reason="$5"
    local red_bold=""
    local reset=""

    if [ -z "${NO_COLOR:-}" ] && [ -t 2 ]; then
        red_bold=$'\033[1;31m'
        reset=$'\033[0m'
    fi

    {
        printf "%s\n" "${red_bold}"
        printf "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"
        printf "!! ERRO CRITICO: GUARDRAIL DO BACKEND CEPH RGW BLOQUEOU A EXECUCAO          !!\n"
        printf "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"
        printf "Ambiente solicitado : %s\n" "${environment:-<desconhecido>}"
        printf "Bucket esperado     : %s\n" "${expected_bucket:-<desconhecido>}"
        printf "Bucket configurado  : %s\n" "${configured_bucket:-<nao encontrado>}"
        printf "Endpoint configurado: %s\n" "${endpoint:-<nao encontrado>}"
        printf "Motivo              : %s\n" "$reason"
        printf "\n"
        printf "Nenhum comando OpenTofu sera executado.\n"
        printf "Confira o backend do ambiente e as credenciais RGW no gerenciador de senhas antes de tentar novamente.\n"
        printf "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"
        printf "%s" "$reset"
    } >&2
}

rgw_backend_guardrail() {
    local environment="$1"
    local vars_file="$2"
    local backend_config="$3"
    local expected_bucket
    local configured_bucket
    local configured_endpoint
    local configured_environment
    local insecure
    local check_output
    local python_args

    expected_bucket=$(rgw_expected_bucket "$environment") || {
        rgw_critical_abort "$environment" "" "" "" "ambiente sem bucket RGW esperado"
        return 1
    }

    configured_environment=$(rgw_tfvars_environment "$vars_file")
    configured_bucket=$(rgw_hcl_value "bucket" "$backend_config")
    configured_endpoint=$(rgw_backend_endpoint "$backend_config")
    insecure=$(rgw_hcl_value "insecure" "$backend_config")

    if [ "$configured_environment" != "$environment" ]; then
        rgw_critical_abort "$environment" "$expected_bucket" "$configured_bucket" "$configured_endpoint" "env_vars informa environment='$configured_environment'"
        return 1
    fi

    if [ "$configured_bucket" != "$expected_bucket" ]; then
        rgw_critical_abort "$environment" "$expected_bucket" "$configured_bucket" "$configured_endpoint" "backend aponta para bucket diferente do ambiente solicitado"
        return 1
    fi

    if [ -z "$configured_endpoint" ]; then
        rgw_critical_abort "$environment" "$expected_bucket" "$configured_bucket" "$configured_endpoint" "endpoint s3 nao encontrado no backend"
        return 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        rgw_critical_abort "$environment" "$expected_bucket" "$configured_bucket" "$configured_endpoint" "python3 nao encontrado para validar acesso ao bucket"
        return 1
    fi

    python_args=(
        "${RGW_GUARDRAIL_DIR}/rgw_check_bucket_access.py"
        "--endpoint" "$configured_endpoint"
        "--bucket" "$expected_bucket"
        "--region" "$CEPH_RGW_BACKEND_REGION"
    )

    if [ "$insecure" = "true" ]; then
        python_args+=("--insecure")
    fi

    if ! check_output=$(python3 "${python_args[@]}" 2>&1); then
        rgw_critical_abort "$environment" "$expected_bucket" "$configured_bucket" "$configured_endpoint" "$check_output"
        return 1
    fi

    echo "[INFO] Guardrail RGW validado: ambiente $environment usa bucket $expected_bucket em $configured_endpoint."
}

rgw_apply_guardrail() {
    rgw_backend_guardrail "$@"
}
