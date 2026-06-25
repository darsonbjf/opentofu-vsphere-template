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

if ! command -v git >/dev/null 2>&1; then
    printf "[ERRO] git nao esta instalado ou nao esta no PATH.\n" >&2
    exit 1
fi

awk '
    /^[[:space:]]*vm_folder_by_cidr[[:space:]]*=/ {
        in_map = 1
        next
    }
    in_map && /^[[:space:]]*}/ {
        exit
    }
    in_map && /^[[:space:]]*"[^"]+"[[:space:]]*=/ {
        line = $0
        sub(/^[[:space:]]*"/, "", line)
        cidr = line
        sub(/".*/, "", cidr)
        sub(/^[^=]*=[[:space:]]*"/, "", line)
        folder = line
        sub(/".*/, "", folder)
        printf "| `%s` | `%s` |\n", cidr, folder
    }
' "${REPO_DIR}/variables.tf" \
    | sort \
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
