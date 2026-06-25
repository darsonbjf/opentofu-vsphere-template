#!/bin/bash

# Atualiza o changelog operacional sem registrar hostname local.
# Uso: ./scripts/update_changelog.sh [mensagem]

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CHANGELOG_FILE="${SCRIPT_DIR}/docs/CHANGELOG.md"
MESSAGE="$*"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/opentofu-changelog.XXXXXX")

cleanup_temp_dir() {
    rm -rf "$TEMP_DIR"
}

trap cleanup_temp_dir EXIT

initialize_changelog() {
    mkdir -p "$(dirname "$CHANGELOG_FILE")"

    cat > "$CHANGELOG_FILE" << EOL
# Historico de Alteracoes

Este documento registra alteracoes feitas pelos fluxos operacionais do OpenTofu.

## Alteracoes Recentes
EOL
}

get_current_workspace() {
    tofu workspace show 2>/dev/null || echo "default"
}

sanitize_existing_changelog() {
    local temp_file="${TEMP_DIR}/CHANGELOG.sanitized.md"

    grep -Ev '^(<<<<<<<|=======|>>>>>>>)' "$CHANGELOG_FILE" > "$temp_file" || true
    mv "$temp_file" "$CHANGELOG_FILE"
}

if [ ! -f "$CHANGELOG_FILE" ]; then
    initialize_changelog
fi

sanitize_existing_changelog

if [ -z "$MESSAGE" ]; then
    CURRENT_WORKSPACE=$(get_current_workspace)
    MESSAGE="Atualizacao de infraestrutura no ambiente $CURRENT_WORKSPACE"
fi

add_changelog_entry() {
    local temp_file="${TEMP_DIR}/CHANGELOG.md"
    local workspace

    workspace=$(get_current_workspace)

    awk '
      /^## (Alteracoes Recentes|🔄 Alterações Recentes)/ { print "## Alteracoes Recentes"; found=1; exit }
      { print }
      END {
        if (!found) {
          print "# Historico de Alteracoes"
          print ""
          print "Este documento registra alteracoes feitas pelos fluxos operacionais do OpenTofu."
          print ""
          print "## Alteracoes Recentes"
        }
      }
    ' "$CHANGELOG_FILE" > "$temp_file"

    cat >> "$temp_file" << EOL

### ${TIMESTAMP} - ${workspace^^}

**Ambiente:** ${workspace}
**Alteracao:** ${MESSAGE}

EOL

    awk '
      BEGIN { found=0 }
      /^## (Alteracoes Recentes|🔄 Alterações Recentes)/ { found=1; next }
      found { print }
    ' "$CHANGELOG_FILE" >> "$temp_file"

    mv "$temp_file" "$CHANGELOG_FILE"
}

add_changelog_entry

echo "Changelog atualizado em $CHANGELOG_FILE"
