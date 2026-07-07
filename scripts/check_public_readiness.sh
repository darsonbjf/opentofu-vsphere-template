#!/bin/bash

# Checks public portfolio hygiene without requiring cloud credentials.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)

if ! command -v git >/dev/null 2>&1; then
    printf "[ERRO] git nao esta instalado ou nao esta no PATH.\n" >&2
    exit 1
fi

cd "$REPO_DIR"

blocked_pattern='(pcce|policia|polícia|\.gov\.br|10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|BEGIN (RSA|OPENSSH|PRIVATE) KEY|ansible_sudo_pass)'

if git grep -nEI "$blocked_pattern" -- . \
    ':!.git/**' \
    ':!.github/workflows/sensitive-upload-alert.yml' \
    ':!scripts/check_public_readiness.sh'; then
    printf "\n[ERRO] Conteudo possivelmente interno ou sensivel encontrado.\n" >&2
    printf "Use dados de exemplo RFC 5737 e placeholders antes de publicar.\n" >&2
    exit 1
fi

if git ls-files -ci --exclude-standard | grep -q .; then
    printf "[ERRO] Existem arquivos versionados que deveriam estar ignorados:\n" >&2
    git ls-files -ci --exclude-standard | sed 's/^/ - /' >&2
    exit 1
fi

printf "[OK] Repositorio pronto para publicacao: sem marcadores internos conhecidos.\n"
