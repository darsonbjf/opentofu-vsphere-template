#!/bin/bash

# Remove artefatos locais sensiveis gerados por OpenTofu/Terraform.
# Uso:
#   ./scripts/clean_local_artifacts.sh --dry-run
#   ./scripts/clean_local_artifacts.sh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
DRY_RUN=0

usage() {
    printf "Uso: %s [--dry-run]\n" "$0" >&2
}

case "${1:-}" in
    "")
        ;;
    --dry-run)
        DRY_RUN=1
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        usage
        exit 1
        ;;
esac

if [ "$#" -gt 1 ]; then
    usage
    exit 1
fi

declare -a TARGETS=()

add_if_exists() {
    local path="$1"

    if [ -e "$path" ]; then
        TARGETS+=("$path")
    fi
}

relative_path() {
    local path="$1"

    printf "%s" "${path#"$REPO_DIR"/}"
}

collect_root_plans() {
    local path

    while IFS= read -r -d '' path; do
        TARGETS+=("$path")
    done < <(
        find "$REPO_DIR" -maxdepth 1 -type f \
            \( -name 'tfplan' -o -name 'tfplan.*' -o -name '*.tfplan' -o -name '*.plan' -o -name 'out.plan' \) \
            -print0 | sort -z
    )
}

collect_root_plans
add_if_exists "${REPO_DIR}/.terraform/terraform.tfstate"
add_if_exists "${REPO_DIR}/terraform.tfstate.d"
add_if_exists "${REPO_DIR}/.terraform.d"

if [ "${#TARGETS[@]}" -eq 0 ]; then
    printf "[OK] Nenhum artefato local sensivel para remover.\n"
    exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
    printf "[DRY-RUN] Artefatos locais sensiveis que seriam removidos:\n"
    for target in "${TARGETS[@]}"; do
        printf " - %s\n" "$(relative_path "$target")"
    done
    exit 0
fi

printf "[INFO] Removendo artefatos locais sensiveis:\n"
for target in "${TARGETS[@]}"; do
    printf " - %s\n" "$(relative_path "$target")"
    rm -rf -- "$target"
done

printf "[OK] Limpeza de artefatos locais concluida.\n"
