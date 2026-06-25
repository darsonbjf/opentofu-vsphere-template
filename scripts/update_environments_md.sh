#!/bin/bash

# Atualiza o documento por ambiente sem gravar inventario sensivel.
# Uso: ./scripts/update_environments_md.sh <ambiente> <apply|destroy> [usuario]

set -euo pipefail

ENVIRONMENT=${1:-}
ACTION=${2:-}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
ENV_VARS_DIR="${REPO_DIR}/env_vars"
COMMON_VARS="${ENV_VARS_DIR}/common.tfvars"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/opentofu-environment.XXXXXX")

# shellcheck source=scripts/tfvars_helpers.sh
source "${SCRIPT_DIR}/tfvars_helpers.sh"

cleanup_temp_dir() {
    rm -rf "$TEMP_DIR"
}

trap cleanup_temp_dir EXIT

usage() {
    echo "Uso: $0 <ambiente> <apply|destroy>"
}

if [ -z "$ENVIRONMENT" ] || [ -z "$ACTION" ]; then
    usage
    exit 1
fi

case "$ACTION" in
    apply|destroy) ;;
    *)
        echo "Acao desconhecida: $ACTION" >&2
        usage
        exit 1
        ;;
esac

ENV_FILE="${ENV_VARS_DIR}/${ENVIRONMENT}.tfvars"
ENV_DOC="${REPO_DIR}/docs/ENVIRONMENTS_${ENVIRONMENT}.md"

if [ ! -f "$ENV_FILE" ]; then
    echo "Arquivo de ambiente nao encontrado: $ENV_FILE" >&2
    exit 1
fi

env_summary_json() {
    tfvars_environment_summary_json "$REPO_DIR" "$ENV_FILE" "$COMMON_VARS"
}

mb_to_gib_label() {
    local mb="$1"

    if [[ "$mb" =~ ^[0-9]+$ ]] && [ "$mb" -ge 1024 ]; then
        awk "BEGIN { printf \"%.1f\", $mb / 1024 }" | sed 's/\./,/'
        printf " GiB"
    else
        printf "%s MiB" "$mb"
    fi
}

write_vm_profile_rows() {
    local env_json="$1"
    local row_count=0

    while IFS=$'\t' read -r index cpus memory disk_size disk_size_data timeout; do
        [ -n "$index" ] || continue
        row_count=$((row_count + 1))
        printf "| VM %s | %s | %s | %s GiB | %s | %s s |\n" \
            "$index" \
            "$cpus" \
            "$(mb_to_gib_label "$memory")" \
            "$disk_size" \
            "$(if [ "$disk_size_data" = "nao declarado" ]; then printf "nao declarado"; else printf "%s GiB" "$disk_size_data"; fi)" \
            "$timeout"
    done < <(
        printf "%s" "$env_json" | jq -r '
          (.vm // {})
          | to_entries
          | sort_by(.key)
          | to_entries[]
          | [
              ((.key + 1) | tostring),
              (.value.value.cpus | tostring),
              (.value.value.memory | tostring),
              (.value.value.disk_size | tostring),
              ((.value.value.disk_size_data // "nao declarado") | tostring),
              ((.value.value.wait_for_guest_net_timeout // 5) | tostring)
            ]
          | @tsv
        '
    )

    if [ "$row_count" -eq 0 ]; then
        printf "| Nenhuma VM declarada | - | - | - | - | - |\n"
    fi
}

write_environment_doc() {
    local env_json="$1"
    local temp_file
    local zone_count
    local network_count
    local vm_count

    temp_file="${TEMP_DIR}/$(basename "$ENV_DOC")"
    zone_count=$(printf "%s" "$env_json" | jq -r '(.zones // {}) | length')
    network_count=$(printf "%s" "$env_json" | jq -r '[ (.zones // {})[]?.networks | length ] | add // 0')
    vm_count=$(printf "%s" "$env_json" | jq -r '(.vm // {}) | length')

    mkdir -p "$(dirname "$ENV_DOC")"

    {
        printf "## Informacoes Redigidas do Ambiente %s\n\n" "$ENVIRONMENT"
        printf "Este documento e gerado automaticamente por \`scripts/update_environments_md.sh\`.\n\n"
        printf "Valores de inventario como vCenter, datacenter, cluster, datastore, portgroups, enderecos IP, DNS, nomes de VM e hostnames foram omitidos de proposito.\n\n"
        printf "### Resumo\n\n"
        printf "| Campo | Valor |\n"
        printf "| --- | --- |\n"
        printf "| Ambiente | %s |\n" "$ENVIRONMENT"
        printf "| Zonas declaradas | %s |\n" "$zone_count"
        printf "| Redes declaradas | %s |\n" "$network_count"
        printf "| VMs declaradas | %s |\n\n" "$vm_count"
        printf "### Perfis de VM\n\n"
        printf "| Item | vCPUs | Memoria | Disco de SO | Disco de dados | Timeout de rede |\n"
        printf "| --- | ---: | ---: | ---: | ---: | ---: |\n"
        write_vm_profile_rows "$env_json"
        printf "\n### Acesso ao Guest\n\n"
        printf "O template OpenTofu nao gerencia acesso nem configuracao interna do guest. Use o procedimento operacional do template base da VM ou da equipe responsavel pelo sistema operacional.\n"
    } > "$temp_file"

    mv "$temp_file" "$ENV_DOC"
    echo "Documento redigido do ambiente $ENVIRONMENT atualizado em $ENV_DOC"
}

ENV_JSON=$(env_summary_json)
write_environment_doc "$ENV_JSON"
"${SCRIPT_DIR}/update_env_docs.sh"
