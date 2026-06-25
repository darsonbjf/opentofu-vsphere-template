#!/bin/bash

# Bloqueia arquivos sensiveis versionados e valida credenciais locais.
# Uso:
#   ./scripts/check_sensitive_files.sh
#   ./scripts/check_sensitive_files.sh --preflight
#   ./scripts/check_sensitive_files.sh --local

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
CREDENTIALS_FILE="${REPO_DIR}/terraform.tfvars"
PLACEHOLDER_FILE="${REPO_DIR}/terraform.tfvars.example"
MODE=${1:-}

usage() {
    printf "Uso: %s [--preflight|--local]\n" "$0" >&2
}

require_git() {
    if ! command -v git >/dev/null 2>&1; then
        printf "[ERRO] git nao esta instalado ou nao esta no PATH.\n" >&2
        exit 1
    fi
}

file_mode() {
    local file="$1"
    local mode

    if mode=$(stat -c "%a" "$file" 2>/dev/null); then
        printf "%s" "$mode"
        return 0
    fi

    if mode=$(stat -f "%Lp" "$file" 2>/dev/null); then
        printf "%s" "$mode"
        return 0
    fi

    return 1
}

hcl_string_value() {
    local key="$1"
    local file="$2"

    awk -v key="$key" '
        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            return value
        }

        $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            value = $0
            sub(/^[^=]*=[[:space:]]*/, "", value)
            value = trim(value)

            if (value ~ /^"/) {
                value = substr(value, 2)
                previous = ""
                for (i = 1; i <= length(value); i++) {
                    character = substr(value, i, 1)
                    if (character == "\"" && previous != "\\") {
                        print substr(value, 1, i - 1)
                        exit
                    }
                    previous = character
                }
                print value
                exit
            }

            sub(/[[:space:]]*#.*/, "", value)
            print trim(value)
            exit
        }
    ' "$file"
}

warn_if_placeholder_changed() {
    local key="$1"
    local actual_value
    local placeholder_value

    if [ ! -f "$PLACEHOLDER_FILE" ]; then
        printf "[AVISO] Arquivo de placeholder nao encontrado: %s\n" "$PLACEHOLDER_FILE" >&2
        return 0
    fi

    actual_value=$(hcl_string_value "$key" "$CREDENTIALS_FILE")
    placeholder_value=$(hcl_string_value "$key" "$PLACEHOLDER_FILE")

    if [ -n "$actual_value" ] &&
       [ -n "$placeholder_value" ] &&
       [ "$actual_value" != "$placeholder_value" ]; then
        printf "[AVISO] terraform.tfvars contem %s diferente do placeholder. Mantenha este arquivo local protegido e fora do Git.\n" "$key" >&2
    fi
}

check_tfvars_preflight() {
    local mode

    if [ ! -f "$CREDENTIALS_FILE" ]; then
        printf "[ERRO] Arquivo obrigatorio nao encontrado: %s\n" "$CREDENTIALS_FILE" >&2
        return 1
    fi

    if ! mode=$(file_mode "$CREDENTIALS_FILE"); then
        printf "[ERRO] Nao foi possivel ler permissao de %s.\n" "$CREDENTIALS_FILE" >&2
        return 1
    fi

    if [ "$mode" != "600" ]; then
        printf "[AVISO] Ajustando permissao de terraform.tfvars de %s para 600.\n" "$mode" >&2
        chmod 600 "$CREDENTIALS_FILE" || {
            printf "[ERRO] Falha ao ajustar permissao de %s para 600.\n" "$CREDENTIALS_FILE" >&2
            return 1
        }

        if ! mode=$(file_mode "$CREDENTIALS_FILE") || [ "$mode" != "600" ]; then
            printf "[ERRO] Permissao de %s continua diferente de 600.\n" "$CREDENTIALS_FILE" >&2
            return 1
        fi
    fi

    warn_if_placeholder_changed "username"
    warn_if_placeholder_changed "password"
    printf "[OK] terraform.tfvars local validado com permissao 600.\n"
}

check_root_persistent_plans() {
    local plans=()
    local path

    while IFS= read -r -d '' path; do
        plans+=("${path#"$REPO_DIR"/}")
    done < <(
        find "$REPO_DIR" -maxdepth 1 -type f \
            \( -name 'tfplan' -o -name 'tfplan.*' -o -name '*.tfplan' -o -name '*.plan' -o -name 'out.plan' \) \
            -print0 | sort -z
    )

    if [ "${#plans[@]}" -gt 0 ]; then
        printf "[ERRO] Planos persistentes foram encontrados na raiz do repositorio:\n" >&2
        printf " - %s\n" "${plans[@]}" >&2
        printf "\nNao use 'tofu plan -out=tfplan' na raiz. Use os scripts principais, que geram planos temporarios.\n" >&2
        printf "Para limpar estes artefatos, execute: ./scripts/clean_local_artifacts.sh\n" >&2
        exit 1
    fi

    printf "[OK] Nenhum plano persistente foi encontrado na raiz.\n"
}

is_versioned_sensitive_path() {
    local file="$1"

    case "$file" in
        terraform.tfvars | terraform.tfvars.json | *.auto.tfvars | *.auto.tfvars.json | *.tfvars.local | *.tfvars.local.json)
            return 0
            ;;
        terraform.tfstate.d/* | */terraform.tfstate.d/*)
            return 0
            ;;
        *.tfstate | *.tfstate.* | .terraform/* | */.terraform/* | .terraform.d/* | */.terraform.d/*)
            return 0
            ;;
        out.plan | */out.plan)
            return 0
            ;;
        tfplan | tfplan.* | *.tfplan | *.plan | crash.log)
            return 0
            ;;
        .env | .env.* | */.env | */.env.*)
            return 0
            ;;
        *.pem | *.key | *.crt | RGW-USERS.md | */RGW-USERS.md)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_local_sensitive_artifact() {
    local file="$1"

    case "$file" in
        terraform.tfvars)
            return 1
            ;;
        terraform.tfvars.json | *.auto.tfvars | *.auto.tfvars.json | *.tfvars.local | *.tfvars.local.json)
            return 0
            ;;
        terraform.tfstate.d/* | */terraform.tfstate.d/*)
            return 0
            ;;
        *.tfstate | *.tfstate.*)
            return 0
            ;;
        out.plan | */out.plan)
            return 0
            ;;
        tfplan | tfplan.* | *.tfplan | *.plan | crash.log)
            return 0
            ;;
        .env | .env.* | */.env | */.env.*)
            return 0
            ;;
        *.pem | *.key | *.crt | RGW-USERS.md | */RGW-USERS.md)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

check_versioned_sensitive_files() {
    local blocked_files=()
    local file

    require_git

    while IFS= read -r -d '' file; do
        if is_versioned_sensitive_path "$file"; then
            blocked_files+=("$file")
        fi
    done < <(git -C "$REPO_DIR" ls-files -z)

    if [ "${#blocked_files[@]}" -gt 0 ]; then
        printf "[ERRO] Arquivos sensiveis versionados foram encontrados:\n" >&2
        printf " - %s\n" "${blocked_files[@]}" >&2
        printf "\nRemova esses arquivos do indice e mantenha segredos, states e planos fora do repositorio.\n" >&2
        exit 1
    fi

    printf "[OK] Nenhum arquivo sensivel proibido esta versionado.\n"
}

check_local_sensitive_artifacts() {
    local artifacts=()
    local path
    local relative_path

    while IFS= read -r -d '' path; do
        relative_path=${path#"$REPO_DIR"/}
        if is_local_sensitive_artifact "$relative_path"; then
            artifacts+=("$relative_path")
        fi
    done < <(find "$REPO_DIR" -path "${REPO_DIR}/.git" -prune -o -type f -print0)

    if [ "${#artifacts[@]}" -gt 0 ]; then
        printf "[ERRO] Artefatos sensiveis locais foram encontrados:\n" >&2
        printf " - %s\n" "${artifacts[@]}" >&2
        printf "\nRemova os artefatos locais quando nao forem mais necessarios. O modo --local nao remove arquivos automaticamente.\n" >&2
        exit 1
    fi

    printf "[OK] Nenhum artefato sensivel local proibido foi encontrado.\n"
}

case "$MODE" in
    "")
        check_versioned_sensitive_files
        ;;
    --preflight)
        check_root_persistent_plans
        check_tfvars_preflight
        ;;
    --local)
        check_versioned_sensitive_files
        if [ -f "$CREDENTIALS_FILE" ]; then
            check_tfvars_preflight
        else
            printf "[AVISO] terraform.tfvars local nao encontrado; preflight de credenciais ignorado.\n" >&2
        fi
        check_local_sensitive_artifacts
        ;;
    -h | --help)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
