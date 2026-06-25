#!/bin/bash

# Gera a documentação pública dos ambientes sem expor inventário sensível.
# Uso: ./scripts/update_env_docs.sh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_DOCS="${SCRIPT_DIR}/docs/ENVIRONMENTS.md"
ENV_VARS_DIR="${SCRIPT_DIR}/env_vars"
COMMON_VARS="${ENV_VARS_DIR}/common.tfvars"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/opentofu-env-docs.XXXXXX")

# shellcheck source=scripts/tfvars_helpers.sh
source "${SCRIPT_DIR}/scripts/tfvars_helpers.sh"

cleanup_temp_dir() {
    rm -rf "$TEMP_DIR"
}

trap cleanup_temp_dir EXIT

environment_row() {
    local env_file="$1"
    local env_name
    local env_json
    local zone_count
    local network_count
    local vm_count

    env_name=$(basename "$env_file" .tfvars)
    if [ "$env_name" = "common" ]; then
        return 0
    fi

    if ! env_json=$(tfvars_environment_summary_json "$SCRIPT_DIR" "$env_file" "$COMMON_VARS"); then
        printf "[ERRO] Falha ao extrair informacoes do ambiente %s.\n" "$env_name" >&2
        return 1
    fi

    zone_count=$(printf "%s" "$env_json" | jq -r '(.zones // {}) | length')
    network_count=$(printf "%s" "$env_json" | jq -r '[ (.zones // {})[]?.networks | length ] | add // 0')
    vm_count=$(printf "%s" "$env_json" | jq -r '(.vm // {}) | length')

    printf "| %s | %s | %s | %s |\n" \
        "$env_name" "$zone_count" "$network_count" "$vm_count"
}

update_env_docs() {
    local temp_file="${TEMP_DIR}/ENVIRONMENTS.md"
    local env_file

    mkdir -p "$(dirname "$ENV_DOCS")"

    cat > "$temp_file" << EOL
# Ambientes Gerenciados

Este documento e gerado automaticamente a partir de \`env_vars/*.tfvars\`.

Detalhes de inventario como vCenter, datacenter, cluster, datastore, portgroups, enderecos IP, DNS, nomes de VM e hostnames nao sao publicados aqui. Consulte os arquivos de variaveis e o state remoto apenas nos fluxos operacionais autorizados.

## Lista de Ambientes

| Ambiente | Zonas declaradas | Redes declaradas | VMs declaradas |
| --- | ---: | ---: | ---: |
EOL

    for env_file in "$ENV_VARS_DIR"/*.tfvars; do
        environment_row "$env_file" >> "$temp_file"
    done

    cat >> "$temp_file" << EOL

## Politica de Exposicao

- Os Markdown gerados publicam somente metadados agregados.
- Inventario sensivel deve permanecer nos \`tfvars\`, no vCenter, no gerenciador de senhas ou no state remoto, conforme o fluxo operacional autorizado.
- Regere este arquivo com \`./scripts/update_env_docs.sh\` apos alteracoes em \`env_vars/*.tfvars\`.
EOL

    mv "$temp_file" "$ENV_DOCS"
    echo "Documentacao de ambientes atualizada em $ENV_DOCS"
}

update_env_docs
