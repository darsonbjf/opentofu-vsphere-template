SHELL := /usr/bin/env bash

.PHONY: help fmt init-validate validate guardrails docs public-check security-check techdocs clean

help:
	@printf "Targets disponiveis:\n"
	@printf "  make fmt             - valida formatacao OpenTofu\n"
	@printf "  make init-validate   - init sem backend e tofu validate\n"
	@printf "  make guardrails      - valida bloqueios de destroy em producao\n"
	@printf "  make public-check    - procura arquivos sensiveis e marcadores internos\n"
	@printf "  make security-check  - executa Trivy via Docker quando disponivel\n"
	@printf "  make docs            - valida documentacao gerada e tabelas CIDR/folder\n"
	@printf "  make techdocs        - gera TechDocs localmente\n"
	@printf "  make validate        - executa o conjunto principal de validacoes locais\n"

fmt:
	tofu fmt -check -recursive -diff

init-validate:
	TF_DATA_DIR="$${TF_DATA_DIR:-$$(mktemp -d)}"; \
	export TF_DATA_DIR; \
	tofu init -backend=false -input=false -no-color; \
	tofu validate -no-color

guardrails:
	bash scripts/check_prod_destroy_guardrails.sh

public-check:
	bash scripts/check_sensitive_files.sh
	bash scripts/check_public_readiness.sh

security-check:
	@if ! command -v docker >/dev/null 2>&1; then \
		printf "[AVISO] Docker nao encontrado; pulando Trivy local.\n"; \
		exit 0; \
	fi
	@if ! docker info >/dev/null 2>&1; then \
		printf "[AVISO] Docker daemon indisponivel; pulando Trivy local.\n"; \
		exit 0; \
	fi
	docker run --rm -v "$$PWD:/workspace" -w /workspace \
		ghcr.io/aquasecurity/trivy@sha256:be1190afcb28352bfddc4ddeb71470835d16462af68d310f9f4bca710961a41e \
		fs --scanners misconfig,secret --severity HIGH,CRITICAL --exit-code 1 --no-progress \
		--skip-dirs .git --skip-dirs .terraform --skip-files .github/workflows/sensitive-upload-alert.yml .

docs:
	bash scripts/check_folder_mapping_docs.sh

techdocs:
	@if ! command -v mkdocs >/dev/null 2>&1; then \
		printf "[AVISO] mkdocs nao encontrado; instale mkdocs-techdocs-core para validar TechDocs localmente.\n"; \
		exit 0; \
	fi
	mkdocs build --strict

validate: fmt init-validate guardrails public-check docs

clean:
	bash scripts/clean_local_artifacts.sh --dry-run
