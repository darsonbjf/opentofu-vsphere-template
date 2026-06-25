#!/bin/bash

# Forca o uso do bash
if [ -z "$BASH" ]; then
    exec bash "$0" "$@"
fi

set -o pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd "$SCRIPT_DIR" || exit 1

if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
    GREEN_BOLD=$'\033[1;32m'
    YELLOW_BOLD=$'\033[1;33m'
    CYAN_BOLD=$'\033[1;36m'
else
    BOLD=""
    RESET=""
    GREEN_BOLD=""
    YELLOW_BOLD=""
    CYAN_BOLD=""
fi

if [ -z "${NO_COLOR:-}" ] && [ -t 2 ]; then
    ERR_RED_BOLD=$'\033[1;31m'
    ERR_RESET=$'\033[0m'
else
    ERR_RED_BOLD=""
    ERR_RESET=""
fi

section() {
    printf "\n%s== %s ==%s\n" "$CYAN_BOLD" "$1" "$RESET"
}

info() {
    printf "%s[INFO]%s %s\n" "$BOLD" "$RESET" "$1"
}

warn() {
    printf "%s[ATENCAO]%s %s\n" "$YELLOW_BOLD" "$RESET" "$1"
}

success() {
    printf "%s[OK]%s %s\n" "$GREEN_BOLD" "$RESET" "$1"
}

error() {
    printf "%s[ERRO]%s %s\n" "$ERR_RED_BOLD" "$ERR_RESET" "$1" >&2
}

# shellcheck source=scripts/rgw_credentials.sh
source "${SCRIPT_DIR}/scripts/rgw_credentials.sh"
# shellcheck source=scripts/rgw_guardrails.sh
source "${SCRIPT_DIR}/scripts/rgw_guardrails.sh"
# shellcheck source=scripts/tfvars_helpers.sh
source "${SCRIPT_DIR}/scripts/tfvars_helpers.sh"

if ! command -v tofu &> /dev/null; then
    error "OpenTofu nao esta instalado ou nao esta no PATH."
    error "Instale o OpenTofu antes de continuar."
    exit 1
fi

if [ -z "$1" ]; then
    echo "Uso: $0 <ambiente> (dev|homolog)"
    exit 1
fi

ENVIRONMENT=$(echo "$1" | tr '[:upper:]' '[:lower:]')

critical_destroy_abort() {
    local title="$1"
    local reason="$2"

    {
        printf "%s\n" "$ERR_RED_BOLD"
        printf "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"
        printf "!! ERRO CRITICO: DESTROY BLOQUEADO                                          !!\n"
        printf "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"
        printf "%s\n" "$title"
        printf "Motivo: %s\n" "$reason"
        printf "\n"
        printf "Nenhum comando OpenTofu sera executado.\n"
        printf "O destroy.sh e permitido somente para dev e homolog, fora das redes de producao.\n"
        printf "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"
        printf "%s" "$ERR_RESET"
    } >&2
}

case "$ENVIRONMENT" in
    dev|homolog) ;;
    prod)
        critical_destroy_abort \
            "DESTRUICAO DE PRODUCAO NAO E PERMITIDA POR ESTE SCRIPT." \
            "ambiente informado foi 'prod'"
        exit 1
        ;;
    *)
        error "Ambiente invalido: $1"
        echo "Uso: $0 <ambiente> (dev|homolog)"
        exit 1
        ;;
esac

VSPHERE_USER=${VSPHERE_USER:-$(whoami)}
VARS_FILE="${SCRIPT_DIR}/env_vars/${ENVIRONMENT}.tfvars"
COMMON_VARS="${SCRIPT_DIR}/env_vars/common.tfvars"
CREDENTIALS_FILE="${SCRIPT_DIR}/terraform.tfvars"
BACKEND_CONFIG="${SCRIPT_DIR}/backend/${ENVIRONMENT}.s3.tfbackend"
DESTROY_PLAN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/opentofu-destroy-plan.${ENVIRONMENT}.XXXXXX") || exit 1
DESTROY_PLAN_FILE="${DESTROY_PLAN_DIR}/tfplan.destroy"

cleanup_destroy_plan() {
    rm -rf "$DESTROY_PLAN_DIR"
}

trap cleanup_destroy_plan EXIT

require_file() {
    if [ ! -f "$1" ]; then
        error "Arquivo obrigatorio nao encontrado: $1"
        exit 1
    fi
}

require_backend_credentials() {
    if ! load_rgw_backend_credentials "$ENVIRONMENT"; then
        exit 1
    fi
}

run_backend_guardrail() {
    if ! rgw_backend_guardrail "$ENVIRONMENT" "$VARS_FILE" "$BACKEND_CONFIG"; then
        exit 1
    fi
}

production_destroy_block_reason() {
    local vars_file="$1"
    local tfvars_json
    local prod_vm

    if ! tfvars_json=$(tfvars_environment_summary_json "$SCRIPT_DIR" "$vars_file" "$COMMON_VARS"); then
        echo "nao foi possivel validar tfvars com leitura estruturada"
        return 0
    fi

    if [ "$(printf "%s" "$tfvars_json" | jq -r '.environment')" = "prod" ]; then
        echo "env_vars informa environment='prod'"
        return 0
    fi

    prod_vm=$(printf "%s" "$tfvars_json" | jq -r '
      (.vm // {})
      | to_entries[]
      | select(.value.ipv4_address | test("^203\\.0\\.113\\."))
      | .key
    ')
    if [ -n "$prod_vm" ]; then
        echo "VM possui IP em rede de producao 203.0.113.0/24"
        return 0
    fi

    prod_vm=$(printf "%s" "$tfvars_json" | jq -r '
      . as $root
      | (.vm // {})
      | to_entries[]
      | . as $vm
      | ($vm.value.zone // $root.default_zone) as $zone
      | ($root.zones[$zone].networks[$vm.value.network].gateway // "") as $gateway
      | select($gateway | test("^203\\.0\\.113\\."))
      | $vm.key
    ')
    if [ -n "$prod_vm" ]; then
        echo "gateway de VM aponta para rede de producao 203.0.113.0/24"
        return 0
    fi

    prod_vm=$(printf "%s" "$tfvars_json" | jq -r '
      (.vm // {})
      | to_entries[]
      | select(.value.folder == "PRODUCTION")
      | .key
    ')
    if [ -n "$prod_vm" ]; then
        echo "folder PRODUCTION encontrado no tfvars"
        return 0
    fi

    return 1
}

get_workspace() {
    case "$1" in
        dev) echo "DEVELOP" ;;
        homolog) echo "HOMOLOG" ;;
        prod) echo "PRODUCTION" ;;
        *) echo "$1" ;;
    esac
}

init_backend() {
    section "Backend remoto"
    info "Inicializando backend remoto do ambiente $ENVIRONMENT"
    if ! tofu init -reconfigure -backend-config="$BACKEND_CONFIG"; then
        error "Falha ao inicializar o backend remoto."
        exit 1
    fi
}

select_workspace() {
    section "Workspace"
    info "Selecionando workspace $WORKSPACE"
    if ! tofu workspace select "$WORKSPACE"; then
        error "Workspace $WORKSPACE nao encontrado no backend remoto."
        info "Execute apply para criar o workspace antes de destruir recursos."
        exit 1
    fi
}

validate_selected_workspace() {
    local selected_workspace

    selected_workspace=$(tofu workspace show)
    if [ "$selected_workspace" != "$WORKSPACE" ]; then
        critical_destroy_abort \
            "WORKSPACE SELECIONADO NAO CONFERE COM O AMBIENTE." \
            "esperado '$WORKSPACE', selecionado '$selected_workspace'"
        exit 1
    fi
}

generate_destroy_plan() {
    section "Plano de destruicao"
    warn "O plano abaixo deve ser revisado antes de qualquer confirmacao."
    rm -f "$DESTROY_PLAN_FILE"

    if ! tofu plan \
        -destroy \
        -out="$DESTROY_PLAN_FILE" \
        -var-file="$COMMON_VARS" \
        -var-file="$VARS_FILE" \
        -var-file="$CREDENTIALS_FILE" \
        -input=false; then
        error "Falha ao gerar plano de destruicao."
        exit 1
    fi
}

validate_destroy_plan() {
    local plan_json
    local unsafe_actions
    local production_resources
    local delete_count

    section "Validacao do plano"

    if ! command -v jq >/dev/null 2>&1; then
        critical_destroy_abort \
            "NAO FOI POSSIVEL VALIDAR O PLANO DE DESTRUICAO." \
            "jq nao esta instalado"
        exit 1
    fi

    if ! plan_json=$(tofu show -json "$DESTROY_PLAN_FILE"); then
        critical_destroy_abort \
            "NAO FOI POSSIVEL LER O PLANO DE DESTRUICAO." \
            "tofu show -json falhou para $DESTROY_PLAN_FILE"
        exit 1
    fi

    unsafe_actions=$(printf "%s" "$plan_json" | jq -r '
      (.resource_changes // [])
      | map(
          select(.mode == "managed")
          | select((.change.actions // []) as $actions | ($actions != ["delete"] and $actions != ["no-op"]))
          | "\(.address): \(.change.actions | join(","))"
        )
      | .[]
    ')

    if [ -n "$unsafe_actions" ]; then
        critical_destroy_abort \
            "PLANO DE DESTRUICAO CONTEM ACOES NAO PERMITIDAS." \
            "$unsafe_actions"
        exit 1
    fi

    production_resources=$(printf "%s" "$plan_json" | jq -r '
      (.resource_changes // [])
      | map(
          select(.mode == "managed")
          | select((.change.actions // []) == ["delete"])
          | select((.change.before // {} | tostring | test("203\\.0\\.113\\.|PRODUCTION|\"environment\":\"prod\"")))
          | .address
        )
      | .[]
    ')

    if [ -n "$production_resources" ]; then
        critical_destroy_abort \
            "PLANO DE DESTRUICAO CONTEM RECURSO COM SINAL DE PRODUCAO." \
            "$production_resources"
        exit 1
    fi

    delete_count=$(printf "%s" "$plan_json" | jq -r '
      [
        (.resource_changes // [])
        | .[]
        | select(.mode == "managed")
        | select((.change.actions // []) == ["delete"])
      ]
      | length
    ')

    if [ "$delete_count" -eq 0 ]; then
        warn "Plano nao contem recursos gerenciados para destruir. Nenhuma acao sera executada."
        exit 0
    fi

    success "Plano validado: $delete_count recurso(s) gerenciado(s) marcado(s) para destruicao."
}

confirm_destroy_plan() {
    local confirm

    CONFIRMATION_PHRASE="DESTROY $ENVIRONMENT $WORKSPACE"

    section "Confirmacao critica"
    warn "Voce esta prestes a DESTRUIR recursos do ambiente $ENVIRONMENT no workspace $WORKSPACE."
    warn "Esta acao e IRREVERSIVEL."
    warn "Revise o plano acima antes de continuar."
    printf "%sPara confirmar, digite exatamente:%s %s\n" "$BOLD" "$RESET" "$CONFIRMATION_PHRASE"
    read -r -p "Confirmacao: " confirm
    echo

    if [ "$confirm" != "$CONFIRMATION_PHRASE" ]; then
        info "Operacao cancelada - confirmacao incorreta."
        exit 1
    fi
}

apply_destroy_plan() {
    section "Aplicacao do plano"
    warn "Aplicando exatamente o plano de destruicao revisado."

    if tofu apply "$DESTROY_PLAN_FILE"; then
        destroy_status=0
    else
        destroy_status=$?
    fi
}

require_file "$VARS_FILE"
require_file "$COMMON_VARS"
require_file "$CREDENTIALS_FILE"
require_file "$BACKEND_CONFIG"
"${SCRIPT_DIR}/scripts/check_sensitive_files.sh" --preflight

EXPECTED_BUCKET=$(rgw_expected_bucket "$ENVIRONMENT")
WORKSPACE=$(get_workspace "$ENVIRONMENT")

section "Contexto"
info "Ambiente: $ENVIRONMENT"
info "Workspace esperado: $WORKSPACE"
info "Backend config: $BACKEND_CONFIG"
info "Bucket esperado: $EXPECTED_BUCKET"

if block_reason=$(production_destroy_block_reason "$VARS_FILE"); then
    critical_destroy_abort \
        "DESTRUICAO DE CAMADA DE PRODUCAO DETECTADA." \
        "$block_reason"
    exit 1
fi

require_backend_credentials
run_backend_guardrail
init_backend
select_workspace
validate_selected_workspace

generate_destroy_plan
validate_destroy_plan
confirm_destroy_plan
apply_destroy_plan

update_environments_md() {
    info "Atualizando ENVIRONMENTS.md..."
    "${SCRIPT_DIR}/scripts/update_environments_md.sh" "$ENVIRONMENT" "destroy" "$VSPHERE_USER"
    success "ENVIRONMENTS.md atualizado com sucesso"
}

if [ $destroy_status -eq 0 ]; then
    success "Recursos destruidos com sucesso"
    tofu workspace select default
    tofu workspace delete "$WORKSPACE" || true
    section "Documentacao"
    "${SCRIPT_DIR}/scripts/update_vm_state.sh" "$ENVIRONMENT"
    "${SCRIPT_DIR}/scripts/update_changelog.sh"
    "${SCRIPT_DIR}/scripts/update_env_docs.sh"
    update_environments_md
    success "Toda a documentacao foi atualizada com sucesso"
else
    error "Falha ao destruir os recursos. Codigo de saida: $destroy_status"
    exit 1
fi
