#!/bin/bash

# Forca o uso do bash
if [ -z "$BASH" ]; then
    exec bash "$0" "$@"
fi

set -o pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd "$SCRIPT_DIR" || exit 1

# shellcheck source=scripts/rgw_credentials.sh
source "${SCRIPT_DIR}/scripts/rgw_credentials.sh"
# shellcheck source=scripts/rgw_guardrails.sh
source "${SCRIPT_DIR}/scripts/rgw_guardrails.sh"
# shellcheck source=scripts/tfvars_helpers.sh
source "${SCRIPT_DIR}/scripts/tfvars_helpers.sh"

if ! command -v tofu &> /dev/null; then
    echo "[ERRO] OpenTofu nao esta instalado ou nao esta no PATH."
    echo "Instale o OpenTofu antes de continuar."
    exit 1
fi

declare -A ENV_MAP
ENV_MAP["dev"]="DEVELOP"
ENV_MAP["homolog"]="HOMOLOG"
ENV_MAP["prod"]="PRODUCTION"

if [ -z "$1" ]; then
    echo "Uso: $0 <ambiente> (dev|homolog|prod)"
    exit 1
fi

ENV=$(echo "$1" | tr '[:upper:]' '[:lower:]')
case "$ENV" in
    dev|homolog|prod) ;;
    *)
        echo "[ERRO] Ambiente invalido: $1"
        echo "Uso: $0 <ambiente> (dev|homolog|prod)"
        exit 1
        ;;
esac

ENVIRONMENT=$ENV
NORMALIZED_ENV=${ENV_MAP[$ENVIRONMENT]}
VARS_FILE="${SCRIPT_DIR}/env_vars/${ENVIRONMENT}.tfvars"
COMMON_VARS="${SCRIPT_DIR}/env_vars/common.tfvars"
CREDENTIALS_FILE="${SCRIPT_DIR}/terraform.tfvars"
BACKEND_CONFIG="${SCRIPT_DIR}/backend/${ENVIRONMENT}.s3.tfbackend"
PLAN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/opentofu-plan.${ENVIRONMENT}.XXXXXX") || exit 1
PLAN_FILE="${PLAN_DIR}/tfplan"

cleanup_plan() {
    rm -rf "$PLAN_DIR"
}

trap cleanup_plan EXIT

require_file() {
    if [ ! -f "$1" ]; then
        echo "[ERRO] Arquivo obrigatorio nao encontrado: $1"
        exit 1
    fi
}

require_backend_credentials() {
    if ! load_rgw_backend_credentials "$ENVIRONMENT"; then
        exit 1
    fi
}

run_backend_guardrail() {
    if ! rgw_apply_guardrail "$ENVIRONMENT" "$VARS_FILE" "$BACKEND_CONFIG"; then
        exit 1
    fi
}

init_backend() {
    echo "[INFO] Inicializando backend remoto do ambiente $ENVIRONMENT..."
    if ! tofu init -reconfigure -backend-config="$BACKEND_CONFIG"; then
        echo "[ERRO] Falha ao inicializar o backend remoto."
        exit 1
    fi
}

select_or_create_workspace() {
    if tofu workspace select "$NORMALIZED_ENV" >/dev/null 2>&1; then
        echo "[INFO] Workspace $NORMALIZED_ENV selecionado."
        return 0
    fi

    echo "[INFO] Workspace $NORMALIZED_ENV nao existe no backend remoto. Criando..."
    if ! tofu workspace new "$NORMALIZED_ENV"; then
        echo "[ERRO] Falha ao criar workspace $NORMALIZED_ENV."
        exit 1
    fi
}

confirm_production() {
    if [ "$ENVIRONMENT" = "prod" ]; then
        echo "[ATENCAO] Voce esta prestes a fazer alteracoes no ambiente de PRODUCAO"
        printf "Tem certeza que deseja continuar? (yes/NO) "
        read -r REPLY
        echo
        if [ "$REPLY" != "yes" ]; then
            echo "[INFO] Operacao cancelada"
            exit 1
        fi
    fi
}

validate_dev_plan_scope() {
    if [ "$ENVIRONMENT" != "dev" ]; then
        return 0
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "[ERRO] jq nao esta instalado. Ele e obrigatorio para validar o escopo do plano dev."
        exit 1
    fi

    local allowed_vms_json
    local allowed_count
    local plan_json
    local unsafe_addresses
    local invalid_names

    if ! allowed_vms_json=$(tfvars_dev_allowed_vms_json "$SCRIPT_DIR" "$VARS_FILE" "$COMMON_VARS" "$NORMALIZED_ENV"); then
        echo "[ERRO] Falha ao derivar escopo permitido de $VARS_FILE."
        exit 1
    fi

    if [ "$(printf "%s" "$allowed_vms_json" | jq -r '.environment')" != "dev" ]; then
        echo "[ERRO] O guardrail dev recebeu tfvars que nao declaram environment = \"dev\"."
        exit 1
    fi

    allowed_count=$(printf "%s" "$allowed_vms_json" | jq -r '.allowed_vms | length')

    if ! plan_json=$(tofu show -json "$PLAN_FILE"); then
        echo "[ERRO] Falha ao ler plano gerado em formato JSON."
        exit 1
    fi

    unsafe_addresses=$(printf "%s" "$plan_json" | jq -r --argjson allowed "$allowed_vms_json" '
      (.resource_changes // [])
      | map(
          select(.mode == "managed")
          | select((.change.actions // []) != ["no-op"])
          | select(
              if (.address | test("^vsphere_virtual_machine\\.vm_nonprod\\[")) and (.change.actions // []) == ["delete"] then
                false
              elif ($allowed.allowed_vms[.address]? != null) then
                false
              else
                true
              end
            )
          | "\(.address) (\((.change.actions // []) | join(",")))"
        )
      | .[]
    ')

    if [ -n "$unsafe_addresses" ]; then
        echo "[ERRO] O plano dev contem mudancas fora do escopo permitido por $VARS_FILE:"
        echo "$unsafe_addresses"
        echo "[INFO] Nenhuma aplicacao sera executada."
        exit 1
    fi

    invalid_names=$(printf "%s" "$plan_json" | jq -r --argjson allowed "$allowed_vms_json" '
      (.resource_changes // [])
      | map(
          select(.mode == "managed")
          | select((.change.actions // []) != ["no-op"])
          | select((.change.actions // []) != ["delete"])
          | select($allowed.allowed_vms[.address]? != null)
          | ($allowed.allowed_vms[.address].name) as $expected
          | select((.change.after.name? // "") != $expected)
          | "\(.address): esperado \($expected), plano \(.change.after.name? // "<unknown>")"
        )
      | .[]
    ')

    if [ -n "$invalid_names" ]; then
        echo "[ERRO] O plano dev contem nomes de VM divergentes do escopo derivado de $VARS_FILE:"
        echo "$invalid_names"
        echo "[INFO] Nenhuma aplicacao sera executada."
        exit 1
    fi

    echo "[INFO] Plano dev validado: $allowed_count VM(s) derivada(s) de $VARS_FILE; deletes nonprod sao permitidos."
}

require_file "$VARS_FILE"
require_file "$CREDENTIALS_FILE"
require_file "$BACKEND_CONFIG"
"${SCRIPT_DIR}/scripts/check_sensitive_files.sh" --preflight
require_backend_credentials
run_backend_guardrail

init_backend
select_or_create_workspace
confirm_production

echo "[INFO] Gerando plano para ambiente $ENVIRONMENT no workspace $NORMALIZED_ENV"

PLAN_ARGS=()
if [ -f "$COMMON_VARS" ]; then
    PLAN_ARGS+=("-var-file=$COMMON_VARS")
else
    echo "[AVISO] Arquivo de variaveis comuns $COMMON_VARS nao encontrado"
fi
PLAN_ARGS+=("-var-file=$VARS_FILE" "-var-file=$CREDENTIALS_FILE" "-out=$PLAN_FILE")

if tofu plan "${PLAN_ARGS[@]}"; then
    validate_dev_plan_scope
else
    echo "[ERRO] Falha ao gerar plano"
    exit 1
fi

update_environments_md() {
    echo "[INFO] Atualizando ENVIRONMENTS.md..."
    "${SCRIPT_DIR}/scripts/update_environments_md.sh" "$ENVIRONMENT" "apply"
    echo "[INFO] ENVIRONMENTS.md atualizado com sucesso"
}

update_markdown() {
    echo "[INFO] Atualizando documentacao..."
    "${SCRIPT_DIR}/scripts/update_vm_state.sh" "$ENVIRONMENT"
    "${SCRIPT_DIR}/scripts/update_changelog.sh"
    "${SCRIPT_DIR}/scripts/update_env_docs.sh"
    update_environments_md
    echo "[INFO] Toda a documentacao foi atualizada com sucesso"
}

echo "[INFO] Revise o plano acima"
printf "Deseja aplicar estas mudancas? (y/N) "
read -r REPLY
echo
case "$REPLY" in
    [Yy]*)
        echo "[INFO] Aplicando plano no workspace $NORMALIZED_ENV"
        if tofu apply "$PLAN_FILE"; then
            update_markdown
            echo "[INFO] Aplicacao concluida com sucesso"
        else
            exit 1
        fi
        ;;
    *)
        echo "[INFO] Operacao cancelada"
        ;;
esac
