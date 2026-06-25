#!/bin/bash

# Forca o uso do bash
if [ -z "$BASH" ]; then
    exec bash "$0" "$@"
fi

set -e
set -o pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
REPO_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
cd "$REPO_DIR" || exit 1

# shellcheck source=scripts/rgw_credentials.sh
source "${REPO_DIR}/scripts/rgw_credentials.sh"
# shellcheck source=scripts/rgw_guardrails.sh
source "${REPO_DIR}/scripts/rgw_guardrails.sh"

usage() {
    echo "Uso: $0 <ambiente> (dev|homolog)"
}

error() {
    echo "[ERRO] $1" >&2
}

info() {
    echo "[INFO] $1"
}

require_file() {
    if [ ! -f "$1" ]; then
        error "Arquivo obrigatorio nao encontrado: $1"
        exit 1
    fi
}

workspace_for_environment() {
    case "$1" in
        dev) echo "DEVELOP" ;;
        homolog) echo "HOMOLOG" ;;
        *) return 1 ;;
    esac
}

if ! command -v tofu >/dev/null 2>&1; then
    error "OpenTofu nao esta instalado ou nao esta no PATH."
    exit 1
fi

if [ "$#" -ne 1 ]; then
    usage
    exit 1
fi

ENVIRONMENT=$(echo "$1" | tr '[:upper:]' '[:lower:]')

case "$ENVIRONMENT" in
    dev|homolog) ;;
    prod)
        error "Migracao de state de producao recusada. O endereco vsphere_virtual_machine.vm deve permanecer protegido em prod."
        exit 1
        ;;
    *)
        error "Ambiente invalido: $1"
        usage
        exit 1
        ;;
esac

WORKSPACE=$(workspace_for_environment "$ENVIRONMENT")
VARS_FILE="${REPO_DIR}/env_vars/${ENVIRONMENT}.tfvars"
BACKEND_CONFIG="${REPO_DIR}/backend/${ENVIRONMENT}.s3.tfbackend"

require_file "$VARS_FILE"
require_file "$BACKEND_CONFIG"

if ! load_rgw_backend_credentials "$ENVIRONMENT"; then
    exit 1
fi

if ! rgw_backend_guardrail "$ENVIRONMENT" "$VARS_FILE" "$BACKEND_CONFIG"; then
    exit 1
fi

info "Inicializando backend remoto do ambiente $ENVIRONMENT."
tofu init -reconfigure -backend-config="$BACKEND_CONFIG"

info "Selecionando workspace $WORKSPACE."
tofu workspace select "$WORKSPACE"

SELECTED_WORKSPACE=$(tofu workspace show)
if [ "$SELECTED_WORKSPACE" != "$WORKSPACE" ]; then
    error "Workspace selecionado nao confere. Esperado '$WORKSPACE', atual '$SELECTED_WORKSPACE'."
    exit 1
fi

STATE_LIST=$(tofu state list)
OLD_KEYS=$(printf "%s\n" "$STATE_LIST" | sed -n 's/^vsphere_virtual_machine\.vm\[\(.*\)\]$/\1/p')

if [ -z "$OLD_KEYS" ]; then
    info "Nenhum endereco antigo vsphere_virtual_machine.vm[...] encontrado. Nada a migrar."
    exit 0
fi

while IFS= read -r KEY; do
    if [ -z "$KEY" ]; then
        continue
    fi

    OLD_ADDRESS="vsphere_virtual_machine.vm[$KEY]"
    NEW_ADDRESS="vsphere_virtual_machine.vm_nonprod[$KEY]"

    if printf "%s\n" "$STATE_LIST" | grep -Fxq "$NEW_ADDRESS"; then
        error "Destino ja existe no state: $NEW_ADDRESS. Resolva manualmente antes de continuar."
        exit 1
    fi

    info "Migrando state: $OLD_ADDRESS -> $NEW_ADDRESS"
    tofu state mv "$OLD_ADDRESS" "$NEW_ADDRESS"
done <<EOF
$OLD_KEYS
EOF

info "Migracao de state non-prod concluida para $ENVIRONMENT."
