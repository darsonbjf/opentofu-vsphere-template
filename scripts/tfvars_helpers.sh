#!/bin/bash

tfvars_console_json() {
    local repo_dir="$1"
    local env_file="$2"
    local common_file="$3"
    local expression="$4"
    local temp_dir
    local console_output
    local console_status
    local json_status
    local console_args=()

    if ! command -v tofu >/dev/null 2>&1; then
        printf "[ERRO] OpenTofu nao esta instalado ou nao esta no PATH.\n" >&2
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        printf "[ERRO] jq nao esta instalado ou nao esta no PATH.\n" >&2
        return 1
    fi

    if [ ! -f "${repo_dir}/variables.tf" ]; then
        printf "[ERRO] Arquivo variables.tf nao encontrado em %s.\n" "$repo_dir" >&2
        return 1
    fi

    if [ ! -f "$env_file" ]; then
        printf "[ERRO] Arquivo de variaveis nao encontrado: %s\n" "$env_file" >&2
        return 1
    fi

    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/opentofu-tfvars.XXXXXX") || return 1
    cp "${repo_dir}/variables.tf" "${temp_dir}/variables.tf" || {
        rm -rf "$temp_dir"
        return 1
    }

    if [ -n "$common_file" ] && [ -f "$common_file" ]; then
        console_args+=("-var-file=$common_file")
    fi
    console_args+=("-var-file=$env_file")

    console_output=$(
        printf "%s\n" "$expression" |
            TF_DATA_DIR="${temp_dir}/.tofu-data" \
            TF_IN_AUTOMATION=1 \
            tofu -chdir="$temp_dir" console -no-color "${console_args[@]}" 2>&1
    )
    console_status=$?
    rm -rf "$temp_dir"

    if [ "$console_status" -ne 0 ]; then
        printf "[ERRO] Falha ao ler tfvars com tofu console: %s\n" "$console_output" >&2
        return "$console_status"
    fi

    printf "%s\n" "$console_output" | jq -er .
    json_status=$?
    if [ "$json_status" -ne 0 ]; then
        printf "[ERRO] Saida do tofu console nao e JSON valido.\n" >&2
        return "$json_status"
    fi
}

tfvars_environment_summary_json() {
    local repo_dir="$1"
    local env_file="$2"
    local common_file="$3"
    local expression

    expression='jsonencode({
      environment = var.environment,
      default_zone = var.default_zone,
      datacenter = var.zones[var.default_zone].data_center,
      cluster = var.zones[var.default_zone].cluster,
      datastore = var.zones[var.default_zone].data_store,
      zones = var.zones,
      vm = var.vm
    })'

    tfvars_console_json "$repo_dir" "$env_file" "$common_file" "$expression"
}

tfvars_dev_allowed_vms_json() {
    local repo_dir="$1"
    local env_file="$2"
    local common_file="$3"
    local workspace="$4"
    local workspace_json
    local expression

    if ! command -v jq >/dev/null 2>&1; then
        printf "[ERRO] jq nao esta instalado ou nao esta no PATH.\n" >&2
        return 1
    fi

    workspace_json=$(jq -Rn --arg value "$workspace" '$value')

    expression="
jsonencode({
  environment = var.environment,
  allowed_vms = {
    for vm_key, vm_config in var.vm :
    format(\"vsphere_virtual_machine.vm_nonprod[%s]\", jsonencode(vm_key)) => {
      name = (
        trimspace(try(var.zones[coalesce(vm_config.zone, var.default_zone)].vm_name_prefix, \"\")) != \"\"
        ? format(\"%s-%s-%s-%s\", ${workspace_json}, trimspace(try(var.zones[coalesce(vm_config.zone, var.default_zone)].vm_name_prefix, \"\")), vm_config.name, vm_config.ipv4_address)
        : format(\"%s-%s-%s\", ${workspace_json}, vm_config.name, vm_config.ipv4_address)
      )
    }
  }
})
"

    tfvars_console_json "$repo_dir" "$env_file" "$common_file" "$expression"
}
