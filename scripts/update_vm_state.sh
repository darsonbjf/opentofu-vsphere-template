#!/bin/bash

# Gera um resumo redigido das VMs declaradas nos ambientes.
# Uso: ./scripts/update_vm_state.sh <ambiente>

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VM_DETAILS="${SCRIPT_DIR}/docs/VM_DETAILS.md"
ENVIRONMENT=${1:-}
ENV_VARS_DIR="${SCRIPT_DIR}/env_vars"
COMMON_VARS="${ENV_VARS_DIR}/common.tfvars"
TEMP_DIR=""

# shellcheck source=scripts/tfvars_helpers.sh
source "${SCRIPT_DIR}/scripts/tfvars_helpers.sh"

cleanup_temp_dir() {
    if [ -n "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup_temp_dir EXIT

usage() {
    echo "Uso: $0 <ambiente>"
}

if [ -z "$ENVIRONMENT" ] || [ "$#" -ne 1 ]; then
    usage
    exit 1
fi

case "$ENVIRONMENT" in
    dev|homolog|prod) ;;
    *)
        echo "Ambiente desconhecido: $ENVIRONMENT" >&2
        usage
        exit 1
        ;;
esac

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/opentofu-vm-state.XXXXXX")

environment_vm_row() {
    local env_file="$1"
    local env_name
    local env_json
    local vm_count
    local total_cpu
    local total_memory
    local total_disk
    local total_data_disk

    env_name=$(basename "$env_file" .tfvars)
    if [ "$env_name" = "common" ]; then
        return 0
    fi

    if ! env_json=$(tfvars_environment_summary_json "$SCRIPT_DIR" "$env_file" "$COMMON_VARS"); then
        printf "[ERRO] Falha ao ler %s.\n" "$env_file" >&2
        return 1
    fi

    vm_count=$(printf "%s" "$env_json" | jq -r '(.vm // {}) | length')
    total_cpu=$(printf "%s" "$env_json" | jq -r '[ (.vm // {})[]?.cpus ] | add // 0')
    total_memory=$(printf "%s" "$env_json" | jq -r '[ (.vm // {})[]?.memory ] | add // 0')
    total_disk=$(printf "%s" "$env_json" | jq -r '[ (.vm // {})[]?.disk_size ] | add // 0')
    total_data_disk=$(printf "%s" "$env_json" | jq -r '[ (.vm // {})[]?.disk_size_data // 0 ] | add // 0')

    printf "| %s | %s | %s | %s MiB | %s GiB | %s GiB |\n" \
        "$env_name" "$vm_count" "$total_cpu" "$total_memory" "$total_disk" "$total_data_disk"
}

write_vm_details() {
    local temp_file="${TEMP_DIR}/VM_DETAILS.md"
    local env_file

    mkdir -p "$(dirname "$VM_DETAILS")"

    cat > "$temp_file" << EOL
# Relatorio Redigido de Infraestrutura Virtual

Este documento e gerado automaticamente a partir de \`env_vars/*.tfvars\`.

Nomes de VM, hostnames, enderecos IP, nomes de redes, gateways, DNS, IDs de portgroup e dados do state nao sao publicados neste arquivo.

## Resumo por Ambiente

| Ambiente | VMs declaradas | vCPUs totais | Memoria total | Disco de SO total | Disco de dados total |
| --- | ---: | ---: | ---: | ---: | ---: |
EOL

    for env_file in "$ENV_VARS_DIR"/*.tfvars; do
        environment_vm_row "$env_file" >> "$temp_file"
    done

    mv "$temp_file" "$VM_DETAILS"
    echo "Resumo redigido de VMs atualizado em $VM_DETAILS"
}

write_vm_details
