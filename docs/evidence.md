# Evidencias de Validacao

Ultima atualizacao: 2026-07-07

Este documento registra os checks que podem ser reproduzidos sem acesso ao
vCenter, ao backend S3-compatible ou a credenciais reais.

## Escopo Validado

| Area | Evidencia | Resultado esperado |
| --- | --- | --- |
| Formatacao IaC | `tofu fmt -check -recursive -diff` | Sem diff |
| Sintaxe OpenTofu | `tofu init -backend=false -input=false && tofu validate -no-color` | Configuracao valida sem backend remoto |
| Guardrails de producao | `./scripts/check_prod_destroy_guardrails.sh` | `prevent_destroy` e bloqueio de `destroy.sh prod` preservados |
| Higiene publica | `./scripts/check_sensitive_files.sh && ./scripts/check_public_readiness.sh` | Sem secrets, state, planos ou marcadores internos |
| Documentacao de redes | `./scripts/check_folder_mapping_docs.sh` | Tabelas CIDR/folder alinhadas com `variables.tf` |
| Scan IaC/secret | `make security-check` | Trivy sem misconfiguracoes HIGH/CRITICAL e sem secrets |
| TechDocs | `mkdocs build --strict` com `mkdocs-techdocs-core==1.6.2` | Build concluido |
| CI | GitHub Actions `Quality and security` e `Prod safety guardrails` | Workflows obrigatorios passando em `main` |

## Comando Consolidado

```bash
make validate
```

## Evidencias de Design

- Os arquivos `env_vars/*.tfvars` usam IPs reservados para documentacao
  publica: `192.0.2.0/24`, `198.51.100.0/24` e `203.0.113.0/24`.
- Credenciais vSphere ficam fora do Git em `terraform.tfvars`, que e bloqueado
  pelo `.gitignore` e por `scripts/check_sensitive_files.sh`.
- States e planos locais sao bloqueados por `.gitignore`, pelo CI e pelo
  preflight dos scripts operacionais.
- `destroy.sh` aceita somente `dev` e `homolog`; producao exige processo
  break-glass documentado em `docs/PROD_DESTRUCTIVE_CHANGES.md`.
- O backend remoto e parametrizado por ambiente em `backend/*.s3.tfbackend`,
  sem access key ou secret key versionados.

## Limitacoes

- `tofu plan` e `tofu apply` exigem acesso real ao vCenter, ao backend remoto e
  as credenciais de cada ambiente.
- O scan Trivy local depende de Docker disponivel; o CI executa o mesmo tipo de
  verificacao em ambiente controlado.
