# OpenTofu vSphere Template

Template publico de Infrastructure as Code para provisionar maquinas virtuais no VMware vSphere com OpenTofu, backend remoto S3-compatible, ambientes separados e guardrails contra destruicao acidental de producao.

## Leitura Recomendada

- `catalog-info.yaml` registra o componente no catálogo.
- `mkdocs.yml` e `docs/index.md` habilitam a documentacao TechDocs.
- [Backend Ceph RGW](BACKEND_CEPH_RGW.md) documenta o backend remoto de state.
- [Zonas de Infraestrutura](INFRASTRUCTURE_ZONES.md) documenta a zona atual e o modelo de override por VM.
- [Ambientes](ENVIRONMENTS.md) resume os arquivos `env_vars/*.tfvars`.
- [Detalhes das VMs](VM_DETAILS.md) apresenta o inventario redigido usado como exemplo.
- [Mudancas destrutivas em producao](PROD_DESTRUCTIVE_CHANGES.md) descreve o fluxo break-glass.
- [Evidencias de validacao](evidence.md) registra checks reproduziveis sem credenciais reais.

## Sinais Tecnicos

- Provider vSphere pinado e lockfile versionado.
- State remoto S3-compatible separado por ambiente.
- `terraform.tfvars`, state e planos fora do Git.
- `destroy.sh prod` bloqueado por script, lifecycle e CI.
- GitHub Actions com validacao OpenTofu, lint, scan IaC/secret e TechDocs.
