#!/bin/bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MAIN_TF="${ROOT_DIR}/main.tf"
DESTROY_SH="${ROOT_DIR}/destroy.sh"
MIGRATION_SH="${ROOT_DIR}/scripts/migrate_nonprod_vm_state.sh"
BREAK_GLASS_DOC="${ROOT_DIR}/docs/PROD_DESTRUCTIVE_CHANGES.md"

fail() {
    printf '[ERRO] %s\n' "$1" >&2
    exit 1
}

require_file() {
    [ -f "$1" ] || fail "Arquivo obrigatorio nao encontrado: $1"
}

extract_resource_block() {
    local resource_type="$1"
    local resource_name="$2"
    local file="$3"

    awk -v header="resource \"${resource_type}\" \"${resource_name}\"" '
        index($0, header) {
            in_block = 1
        }
        in_block {
            print
            opens += gsub(/{/, "{")
            closes += gsub(/}/, "}")
            if (opens > 0 && opens == closes) {
                exit
            }
        }
    ' "$file"
}

require_file "$MAIN_TF"
require_file "$DESTROY_SH"
require_file "$MIGRATION_SH"
require_file "$BREAK_GLASS_DOC"

grep -Eq 'production_vms[[:space:]]*=[[:space:]]*local\.is_production[[:space:]]*\?[[:space:]]*var\.vm[[:space:]]*:[[:space:]]*\{\}' "$MAIN_TF" \
    || fail "local.production_vms deve apontar para var.vm somente em prod."

grep -Eq 'non_production_vms[[:space:]]*=[[:space:]]*local\.is_production[[:space:]]*\?[[:space:]]*\{\}[[:space:]]*:[[:space:]]*var\.vm' "$MAIN_TF" \
    || fail "local.non_production_vms deve apontar para var.vm somente fora de prod."

if grep -Eq 'prevent_destroy[[:space:]]*=[[:space:]]*false' "$MAIN_TF"; then
    fail "prevent_destroy = false nao deve existir em main.tf."
fi

PROD_BLOCK=$(extract_resource_block "vsphere_virtual_machine" "vm" "$MAIN_TF")
NONPROD_BLOCK=$(extract_resource_block "vsphere_virtual_machine" "vm_nonprod" "$MAIN_TF")

[ -n "$PROD_BLOCK" ] || fail "Recurso de producao vsphere_virtual_machine.vm nao encontrado."
[ -n "$NONPROD_BLOCK" ] || fail "Recurso non-prod vsphere_virtual_machine.vm_nonprod nao encontrado."

printf "%s\n" "$PROD_BLOCK" | grep -Eq 'for_each[[:space:]]*=[[:space:]]*local\.production_vms' \
    || fail "vsphere_virtual_machine.vm deve usar for_each = local.production_vms."

printf "%s\n" "$PROD_BLOCK" | grep -Eq 'prevent_destroy[[:space:]]*=[[:space:]]*true' \
    || fail "vsphere_virtual_machine.vm deve manter lifecycle.prevent_destroy = true."

printf "%s\n" "$NONPROD_BLOCK" | grep -Eq 'for_each[[:space:]]*=[[:space:]]*local\.non_production_vms' \
    || fail "vsphere_virtual_machine.vm_nonprod deve usar for_each = local.non_production_vms."

if grep -Eq 'dev\|homolog\|prod\)[[:space:]]*;;' "$DESTROY_SH"; then
    fail "destroy.sh nao pode aceitar prod como ambiente permitido."
fi

grep -Eq 'dev\|homolog\)[[:space:]]*;;' "$DESTROY_SH" \
    || fail "destroy.sh deve permitir somente dev e homolog."

grep -q "ambiente informado foi 'prod'" "$DESTROY_SH" \
    || fail "destroy.sh deve manter bloqueio explicito para prod."

if grep -Eq 'dev\|homolog\|prod\)[[:space:]]*;;' "$MIGRATION_SH"; then
    fail "Script de migracao nao pode aceitar prod como ambiente permitido."
fi

grep -Eq 'dev\|homolog\)[[:space:]]*;;' "$MIGRATION_SH" \
    || fail "Script de migracao deve permitir somente dev e homolog."

grep -q 'Migracao de state de producao recusada' "$MIGRATION_SH" \
    || fail "Script de migracao deve recusar prod explicitamente."

grep -q 'prevent_destroy' "$BREAK_GLASS_DOC" \
    || fail "Documento break-glass deve citar prevent_destroy."

printf '[OK] Guardrails de destroy de producao verificados.\n'
