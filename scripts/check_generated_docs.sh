#!/bin/bash

# Regenera a documentacao derivada e falha se houver diferencas pendentes.
# Uso: ./scripts/check_generated_docs.sh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
ENV_VARS_DIR="${REPO_DIR}/env_vars"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/opentofu-docs-check.XXXXXX")
DOC_PATHS=(README.md docs/ENVIRONMENTS.md docs/ENVIRONMENTS_*.md docs/VM_DETAILS.md)

cleanup_temp_dir() {
    rm -rf "$TEMP_DIR"
}

trap cleanup_temp_dir EXIT

cd "$REPO_DIR" || exit 1

if ! command -v git >/dev/null 2>&1; then
    printf "[ERRO] git nao esta instalado ou nao esta no PATH.\n" >&2
    exit 1
fi

git diff --binary -- "${DOC_PATHS[@]}" > "${TEMP_DIR}/before.diff"

"${SCRIPT_DIR}/update_readme_tfdocs.sh"

for env_file in "$ENV_VARS_DIR"/*.tfvars; do
    env_name=$(basename "$env_file" .tfvars)
    if [ "$env_name" = "common" ]; then
        continue
    fi

    "${SCRIPT_DIR}/update_environments_md.sh" "$env_name" apply
done

"${SCRIPT_DIR}/update_vm_state.sh" dev

git diff --binary -- "${DOC_PATHS[@]}" > "${TEMP_DIR}/after.diff"

if ! cmp -s "${TEMP_DIR}/before.diff" "${TEMP_DIR}/after.diff"; then
    git diff --exit-code -- "${DOC_PATHS[@]}" || true
    printf "\n[ERRO] Documentacao gerada esta desatualizada.\n" >&2
    printf "Execute ./scripts/check_generated_docs.sh e versiona as alteracoes resultantes.\n" >&2
    exit 1
fi

printf "[OK] Documentacao gerada esta atualizada.\n"
"${SCRIPT_DIR}/check_folder_mapping_docs.sh"
