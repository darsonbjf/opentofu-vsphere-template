# Changelog

Todas as alteracoes notaveis deste projeto serao documentadas neste arquivo.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/)
e o versionamento segue [Semantic Versioning](https://semver.org/lang/pt-BR/).

## [Nao Publicado]

### Adicionado

- Check de prontidao publica para bloquear marcadores internos antes de publicacao.
- Makefile com comandos locais de validacao, seguranca e TechDocs.
- Dependabot para GitHub Actions e providers OpenTofu/Terraform.
- Documento de evidencias reproduziveis em `docs/evidence.md`.

### Alterado

- README, TechDocs e catalog-info reposicionados para uso publico e avaliacao de portfolio.

## [0.1.0] - 2026-07-07

### Adicionado

- Template OpenTofu para provisionamento de VMs no VMware vSphere.
- Separacao de ambientes `dev`, `homolog` e `prod` com arquivos `env_vars/*.tfvars`.
- Backend remoto S3-compatible/Ceph RGW por ambiente.
- Guardrails contra destruicao de producao com `prevent_destroy`, bloqueio em `destroy.sh` e CI dedicado.
- Validacoes de variaveis para redes, ambientes, folders, zonas, CPU, memoria e discos.
- Scripts operacionais para apply, destroy, workspaces, cache de credenciais RGW e documentacao gerada.
- GitHub Actions para formatacao, validacao OpenTofu, ShellCheck, TFLint, Trivy, secrets e TechDocs.
- Documentacao operacional para backend, zonas, ambientes, VMs e mudancas destrutivas em producao.

### Seguranca

- Dados de exemplo redigidos com IPs reservados para documentacao publica.
- `terraform.tfvars`, states, planos, chaves e artefatos sensiveis bloqueados por `.gitignore` e scripts.
