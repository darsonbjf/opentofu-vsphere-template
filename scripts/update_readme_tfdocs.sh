#!/bin/bash

# Regenera o bloco BEGIN_TF_DOCS do README a partir dos arquivos OpenTofu.
# Uso: ./scripts/update_readme_tfdocs.sh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
TERRAFORM_DOCS_VERSION="v0.20.0"
TERRAFORM_DOCS_IMAGE="quay.io/terraform-docs/terraform-docs@sha256:37329e2dc2518e7f719a986a3954b10771c3fe000f50f83fd4d98d489df2eae2"

if command -v terraform-docs >/dev/null 2>&1; then
    terraform-docs markdown table --config "${REPO_DIR}/tfdocs-config.yml" "$REPO_DIR"
elif command -v go >/dev/null 2>&1; then
    go run "github.com/terraform-docs/terraform-docs@${TERRAFORM_DOCS_VERSION}" \
        markdown table \
        --config "${REPO_DIR}/tfdocs-config.yml" \
        "$REPO_DIR"
elif command -v docker >/dev/null 2>&1; then
    docker run --rm \
        -v "${REPO_DIR}:/workspace" \
        -w /workspace \
        "$TERRAFORM_DOCS_IMAGE" \
        markdown table \
        --config /workspace/tfdocs-config.yml \
        /workspace
else
    echo "[ERRO] terraform-docs, go ou docker precisam estar instalados para atualizar o README." >&2
    exit 1
fi
