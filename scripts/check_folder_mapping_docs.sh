#!/bin/bash

# Confere se as tabelas documentadas de CIDR -> folder seguem variables.tf.
# Uso: ./scripts/check_folder_mapping_docs.sh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/opentofu-folder-docs.XXXXXX")
DOC_PATHS=(README.md docs/INFRASTRUCTURE_ZONES.md)
# shellcheck disable=SC2016
ROW_PATTERN='^\| `([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]+` \| `(DEVELOPMENT|STAGING|PRODUCTION)` \|$'

cleanup_temp_dir() {
    rm -rf "$TEMP_DIR"
}

trap cleanup_temp_dir EXIT

for command_name in tofu jq git; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf "[ERRO] %s nao esta instalado ou nao esta no PATH.\n" "$command_name" >&2
        exit 1
    fi
done

mkdir -p "${TEMP_DIR}/config"
cp "${REPO_DIR}/variables.tf" "${TEMP_DIR}/config/variables.tf"

console_output=$(printf 'jsonencode(local.vm_folder_by_cidr)\n' | TF_DATA_DIR="${TEMP_DIR}/.tofu-data" tofu -chdir="${TEMP_DIR}/config" console -no-color)
printf "%s\n" "$console_output" \
    | jq -er 'fromjson | to_entries | sort_by(.key)[] | "| `\(.key)` | `\(.value)` |"' \
    > "${TEMP_DIR}/expected.rows"

for doc_path in "${DOC_PATHS[@]}"; do
    actual_rows="${TEMP_DIR}/$(basename "$doc_path").rows"

    if ! grep -E "$ROW_PATTERN" "${REPO_DIR}/${doc_path}" | sort > "$actual_rows"; then
        : > "$actual_rows"
    fi

    if ! cmp -s "${TEMP_DIR}/expected.rows" "$actual_rows"; then
        printf "[ERRO] Tabela CIDR -> folder desatualizada em %s.\n" "$doc_path" >&2
        git --no-pager diff --no-index -- "${TEMP_DIR}/expected.rows" "$actual_rows" || true
        printf "Atualize a tabela para refletir local.vm_folder_by_cidr em variables.tf.\n" >&2
        exit 1
    fi
done

printf "[OK] Tabelas CIDR -> folder estao alinhadas com variables.tf.\n"
