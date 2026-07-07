# OpenTofu vSphere Template

[![Quality and security](https://github.com/darsonbjf/opentofu-vsphere-template/actions/workflows/quality-security.yml/badge.svg)](https://github.com/darsonbjf/opentofu-vsphere-template/actions/workflows/quality-security.yml)
[![Prod safety guardrails](https://github.com/darsonbjf/opentofu-vsphere-template/actions/workflows/prod-safety.yml/badge.svg)](https://github.com/darsonbjf/opentofu-vsphere-template/actions/workflows/prod-safety.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-1.11.x-blue.svg)](.opentofu-version)

Template publico de Infrastructure as Code para provisionar maquinas virtuais no VMware vSphere com OpenTofu, backend remoto S3-compatible, ambientes separados e guardrails contra destruicao acidental de producao.

Este repositorio foi preparado para portfolio DevOps/SRE: exemplos sem dados internos, CI reproduzivel, politica contra secrets, documentacao operacional, TechDocs e evidencias de validacao.

## O Que Este Projeto Demonstra

- IaC com OpenTofu para vSphere, usando provider pinado e lockfile versionado.
- Separacao entre `dev`, `homolog` e `prod`, com workspaces e backend remoto por ambiente.
- Guardrails de producao: `prevent_destroy`, bloqueio de `destroy.sh prod`, validacao de plano e processo break-glass documentado.
- Higiene publica: `.gitignore`, checks contra state/plan/secrets e varredura de marcadores internos.
- Qualidade continua: `tofu fmt`, `tofu validate`, ShellCheck, TFLint, Trivy, TechDocs e checks customizados no GitHub Actions.
- Documentacao tecnica gerada e revisavel para ambientes, zonas, backend, operacao e evidencias.

## Arquitetura Operacional

```text
operator
  |
  |  ./apply.sh dev|homolog|prod
  v
OpenTofu CLI
  |
  |-- backend/*.s3.tfbackend  -> state remoto S3-compatible/Ceph RGW
  |-- env_vars/*.tfvars       -> contrato de ambiente sem segredos
  |-- terraform.tfvars        -> credenciais locais ignoradas pelo Git
  v
VMware vSphere
  |
  |-- datacenter/cluster/datastore por zona
  |-- redes, DNS e gateway declarados por ambiente
  |-- VMs nomeadas por workspace, prefixo, nome logico e IP
```

## Validacao Rapida

```bash
make validate
```

Esse target valida formatacao OpenTofu, inicializacao sem backend, `tofu validate`, guardrails de producao, checks publicos e tabelas de documentacao. Consulte [evidencias de validacao](docs/evidence.md) para o escopo completo.

## Pré-Requisitos

- OpenTofu v1.11.6 ou superior, limitado à série 1.11.x até validação da 1.12
- Acesso ao vCenter
- Bash Shell
- Git
- `jq` para validações estruturadas dos planos e arquivos `tfvars`
- `shellcheck` recomendado para validar alterações nos scripts Bash
- Docker para reproduzir localmente os checks de ShellCheck, TFLint e Trivy usados no CI
- Go 1.23+ para o fallback versionado do `terraform-docs`
- Python 3.12+ para validar o build TechDocs localmente
- `terraform-docs` opcional; se nao estiver instalado, `./scripts/update_readme_tfdocs.sh` usa `go run` com versao fixada

## Estrutura do Projeto

```
.
├── env_vars/              # Configurações dos ambientes
│   ├── common.tfvars      # Variáveis comuns a todos ambientes
│   ├── dev.tfvars         # Configuração do ambiente de desenvolvimento
│   ├── homolog.tfvars     # Configuração do ambiente de homologação
│   └── prod.tfvars        # Configuração do ambiente de produção
├── backend/               # Configurações não sensíveis do backend remoto
├── scripts/               # Scripts de automação
├── docs/                  # Documentação gerada automaticamente
├── *.tf                   # Arquivos de configuração OpenTofu
├── tfdocs-config.yml      # Configuração do terraform-docs
├── apply.sh               # Script para aplicar mudanças
├── destroy.sh             # Script para destruir ambiente
└── workspace.sh           # Gerenciador de workspaces
```

## Começando

1. Clone o repositório:
```bash
git clone https://github.com/darsonbjf/opentofu-vsphere-template.git
cd opentofu-vsphere-template
```

2. Configure as variáveis de ambiente no diretório `env_vars/`:
   - Copie os arquivos de exemplo e ajuste conforme necessário
   - Defina as configurações específicas de cada ambiente

3. Obtenha no gerenciador de segredos da sua organizacao as credenciais RGW/S3-compatible do ambiente que sera usado.

Voce pode exportar as variaveis antes de executar:
```bash
export CEPH_RGW_ACCESS_KEY_ID="<access-key-do-ambiente>"
export CEPH_RGW_SECRET_ACCESS_KEY="<secret-key-do-ambiente>"
```

Se essas variaveis nao estiverem definidas, o `apply.sh` pedira os valores interativamente no terminal. O `CEPH_RGW_ACCESS_KEY_ID` fica visivel; o `CEPH_RGW_SECRET_ACCESS_KEY` fica oculto por padrao. Para conferir o secret em um terminal privado, use `CEPH_RGW_VISIBLE_SECRET=1 ./apply.sh <ambiente>`.

Depois da primeira leitura, as credenciais ficam em cache local por ambiente: `dev` e `homolog` ate 00:00 do dia atual; `prod` por 30 minutos. O cache fica fora do repositorio, com permissao `600`, e evita nova colagem em execucoes seguintes do `apply.sh`. Para forcar nova leitura do gerenciador de senhas e substituir o cache, use `CEPH_RGW_REFRESH_CACHE=1 ./apply.sh <ambiente>`. Para ignorar o cache em uma execucao sem reutiliza-lo nem atualiza-lo, use `CEPH_RGW_DISABLE_CACHE=1 ./apply.sh <ambiente>`. Nao cole secrets em terminal compartilhado, sessao gravada ou screen recording.

4. Inicialize ou aplique pelo script do ambiente:
```bash
./apply.sh dev
```

### Provider vSphere

O vCenter usado pelo provider vSphere vem da zona de infraestrutura, nao do `terraform.tfvars` local. A zona de exemplo `primary-zone` define esse valor nos arquivos `env_vars/*.tfvars`. Exemplo de formato:

```hcl
vsphere_server = "<vcenter-fqdn>"
```

O `terraform.tfvars` local deve conter apenas credenciais/opcoes locais do vSphere, como `username`, `password` e `vsphere_allow_unverified_ssl`. Tambem e possivel usar `TF_VAR_username`, `TF_VAR_password` e `TF_VAR_vsphere_allow_unverified_ssl` em automacoes.

`vsphere_allow_unverified_ssl` tem default `true` por decisao operacional em ambiente controlado por firewall e restricoes. Se uma zona futura exigir outro vCenter, ela deve declarar seu proprio `vsphere_server`; enquanto houver um unico provider por execucao, todas as zonas do mesmo ambiente devem apontar para o mesmo vCenter.

## Uso

### Aplicando Mudanças

```bash
./apply.sh <ambiente>  # dev, homolog, ou prod
```

### Destruindo Ambiente

```bash
./destroy.sh <ambiente>  # somente dev ou homolog
```

O `destroy.sh` reutiliza o mesmo cache de credenciais RGW do `apply.sh`. Se nao houver cache valido para o ambiente, ele pedira `CEPH_RGW_ACCESS_KEY_ID` visivel e `CEPH_RGW_SECRET_ACCESS_KEY` oculto por padrao, mantendo o cache local de `dev` e `homolog` ate 00:00.

Antes de destruir, o script gera e exibe um plano com `tofu plan -destroy`. A frase critica `DESTROY <ambiente> <workspace>` so e solicitada depois da revisao do plano, e a execucao usa um plano temporario fora da raiz do repositorio para aplicar exatamente o que foi revisado. Esse arquivo e removido ao final da execucao.

### Gerenciando Workspaces

O helper de workspaces opera sobre o backend remoto. Use-o depois de `./apply.sh <ambiente>` inicializar o diretório, ou informe explicitamente o backend:

```bash
TOFU_BACKEND_CONFIG=backend/dev.s3.tfbackend ./workspace.sh list
TOFU_BACKEND_CONFIG=backend/dev.s3.tfbackend ./workspace.sh new DEVELOP
TOFU_BACKEND_CONFIG=backend/dev.s3.tfbackend ./workspace.sh select DEVELOP
TOFU_BACKEND_CONFIG=backend/dev.s3.tfbackend ./workspace.sh delete DEVELOP
```

### Backend Remoto Ceph RGW

O state do OpenTofu usa backend S3-compatible no Ceph RGW, com um bucket por ambiente:

| Ambiente | Bucket | Usuário técnico |
| --- | --- | --- |
| dev | `opentofu-vsphere-template-dev` | `rgw-opentofu-template-dev` |
| homolog | `opentofu-vsphere-template-homolog` | `rgw-opentofu-template-homolog` |
| prod | `opentofu-vsphere-template-prod` | `rgw-opentofu-template-prod` |

As configurações versionadas ficam em `backend/*.s3.tfbackend` e não contêm segredos. O fluxo operacional é:

```bash
# 1. Obter a credencial do ambiente no gerenciador de senhas e exportar, se desejar
export CEPH_RGW_ACCESS_KEY_ID="<access-key-do-ambiente>"
export CEPH_RGW_SECRET_ACCESS_KEY="<secret-key-do-ambiente>"

# 2. Executar o ambiente desejado.
# Se as variaveis CEPH_RGW_* nao existirem, o script pedira access key visivel e secret oculto.
./apply.sh dev
```

As chaves devem ser únicas por ambiente, compartilhadas via gerenciador de senhas e rotacionadas regularmente. Não grave `ACCESS_KEY`, `SECRET_KEY` ou conteúdo sensível no repositório.

Quando as chaves forem informadas pelo prompt ou ja estiverem exportadas, o `apply.sh` salva um cache local por ambiente. `dev` e `homolog` ficam validos ate 00:00 do dia atual; `prod` fica valido por 30 minutos. Em Linux, o caminho usa `${XDG_RUNTIME_DIR}/opentofu-vsphere-template/rgw-credentials` quando disponivel; caso contrario usa `~/.cache/opentofu-vsphere-template/rgw-credentials`. Os arquivos sao criados com permissao `600`. Use `CEPH_RGW_REFRESH_CACHE=1` para forcar nova leitura do gerenciador de senhas e substituir o cache, ou `CEPH_RGW_DISABLE_CACHE=1` para nao reutilizar nem atualizar o cache. Use `CEPH_RGW_VISIBLE_SECRET=1` somente quando for necessario conferir o secret em terminal privado, sem compartilhamento de tela ou gravacao.

Campos recomendados no gerenciador de senhas: `CEPH_RGW_ACCESS_KEY_ID`, `CEPH_RGW_SECRET_ACCESS_KEY`, `RGW_ENDPOINT`, `BUCKET` e `RGW_USER`. Nao ha zona operacional de Ceph RGW para o operador escolher; o cluster RGW e acessado pelo endpoint do ambiente.

O `apply.sh` possui um guardrail bloqueante antes de qualquer chamada ao OpenTofu. Ele valida o `environment` do tfvars, o bucket configurado no backend e o acesso real ao bucket RGW esperado:

| Comando | Bucket obrigatório |
| --- | --- |
| `./apply.sh dev` | `opentofu-vsphere-template-dev` |
| `./apply.sh homolog` | `opentofu-vsphere-template-homolog` |
| `./apply.sh prod` | `opentofu-vsphere-template-prod` |

Se o backend ou as credenciais apontarem para outro bucket, a execução é cancelada imediatamente com aviso crítico em vermelho.

Limitações operacionais atuais:

- `insecure = false` e o endpoint `https://s3.example.com` sao placeholders; ajuste para o RGW/S3 da sua organizacao.
- SSE/SSE-KMS deve ser habilitado conforme o padrao de seguranca do seu backend S3-compatible.
- `region = "default"` nos arquivos `backend/*.s3.tfbackend` e apenas compatibilidade com o backend S3-compatible do OpenTofu/Ceph RGW.
- Planos OpenTofu sao artefatos locais e temporarios. Os scripts criam esses arquivos fora da raiz do repositorio e os removem ao final da execucao; eles nao devem ser versionados, enviados ao bucket de state ou compartilhados como artefato permanente.

Para mais detalhes, consulte [Backend Ceph RGW](docs/BACKEND_CEPH_RGW.md).

### Zonas de Infraestrutura

Os arquivos `env_vars/*.tfvars` devem declarar `default_zone = "primary-zone"` de forma explicita e manter essa chave em `zones`. Cada zona define vCenter, datacenter, cluster, datastore, redes e um prefixo opcional para nome de VM. Os Markdown gerados nao publicam nomes, hostnames, IPs, portgroups ou demais detalhes de inventario.

Cada VM pode sobrescrever a zona no futuro com `zone = "nome-da-zona"`. O `folder` e derivado automaticamente pelo IP da VM; o campo `folder` ainda pode ser informado nos `tfvars` por compatibilidade, mas, quando informado, deve bater com a faixa do IP:

| CIDR | Folder vSphere |
| --- | --- |
| `192.0.2.0/24` | `DEVELOPMENT` |
| `198.51.100.0/24` | `STAGING` |
| `203.0.113.0/24` | `PRODUCTION` |

Esses folders sao fixos no vSphere. Para liberar uma nova faixa de IP, atualize `local.vm_folder_by_cidr` em `variables.tf`, replique a tabela neste README e em `docs/INFRASTRUCTURE_ZONES.md`, e rode `./scripts/check_folder_mapping_docs.sh` junto de `./scripts/check_generated_docs.sh`. O CI falha se a documentacao divergir do mapeamento usado pelo OpenTofu.

Para mais detalhes, consulte [Zonas de Infraestrutura](docs/INFRASTRUCTURE_ZONES.md).

## Segurança e Proteções

### Proteção contra Destruição de Produção

Este template inclui **proteções críticas de segurança** que impedem a destruição acidental de ambientes de produção:

- **Bloqueio de argumento**: `./destroy.sh prod` aborta imediatamente antes de carregar credenciais ou executar OpenTofu
- **Lifecycle no recurso de produção**: `vsphere_virtual_machine.vm` gerencia somente produção e usa `prevent_destroy = true`
- **Separação de recursos por ambiente**: `dev` e `homolog` usam `vsphere_virtual_machine.vm_nonprod`, mantendo seus fluxos destrutivos legítimos
- **Detecção Inteligente**: O script `destroy.sh` analisa automaticamente os arquivos de configuração para detectar camadas de produção
- **Múltiplos Critérios**: Verifica nome do ambiente, padrões de rede produtiva, gateways e folders de produção definidos nos guardrails
- **Aborto Imediato**: Se produção for detectada, o script aborta imediatamente sem executar nenhuma operação OpenTofu
- **Bloqueio fora do script**: `tofu destroy` ou plano que exigiria replacement destrutivo em produção falha enquanto o `prevent_destroy` estiver versionado
- **Plano Antes da Confirmação**: Para `dev` e `homolog`, mostra `tofu plan -destroy` antes de pedir confirmação
- **Confirmação Forte**: Exige digitar exatamente `DESTROY <ambiente> <workspace>` e aplica somente o plano salvo
- **Verificação em CI**: o workflow `Prod safety guardrails` falha se o guardrail de produção for removido
- **Mensagem Clara**: Exibe alerta visual crítico explicando por que a operação foi bloqueada

**Exemplo de proteção em ação:**
```bash
$ ./destroy.sh prod
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!! ERRO CRITICO: DESTROY BLOQUEADO                                          !!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
DESTRUICAO DE PRODUCAO NAO E PERMITIDA POR ESTE SCRIPT.
Motivo: ambiente informado foi 'prod'
```

### Gerenciamento Seguro de Produção

Destruicao de recursos de producao fica fora do `destroy.sh` e deve seguir processo operacional separado, com revisao explicita do escopo e das aprovacoes necessarias. O fluxo autorizado de excecao esta documentado em [Mudancas destrutivas em producao](docs/PROD_DESTRUCTIVE_CHANGES.md).

Depois da separacao de recursos por ambiente, `dev` e `homolog` precisam de uma migracao unica de state:

```bash
./scripts/migrate_nonprod_vm_state.sh dev
./scripts/migrate_nonprod_vm_state.sh homolog
```

Esse helper recusa `prod` e move apenas enderecos antigos `vsphere_virtual_machine.vm[...]` para `vsphere_virtual_machine.vm_nonprod[...]` nos workspaces nao produtivos.
## Extensibilidade e Módulos

Este template é projetado para ser extensível. Você pode:

- **Adicionar novos recursos**: Inclua novos recursos Terraform no `main.tf` ou crie módulos na pasta `modules/`
- **Personalizar configurações**: Modifique os arquivos `.tfvars` para diferentes ambientes
- **Integrar ferramentas**: Adicione scripts em `scripts/` para automação adicional

### Estrutura de Módulos

Para projetos maiores, considere mover recursos para módulos:

```
modules/
├── networking/     # Configurações de rede
├── compute/        # Recursos de computação
└── storage/        # Configurações de storage
```

## Documentação

- [Especificações dos Ambientes](docs/ENVIRONMENTS.md)
- [Detalhes das VMs](docs/VM_DETAILS.md)
- [Backend remoto S3-compatible/Ceph RGW](docs/BACKEND_CEPH_RGW.md)
- [Zonas de infraestrutura](docs/INFRASTRUCTURE_ZONES.md)
- [Mudancas destrutivas em producao](docs/PROD_DESTRUCTIVE_CHANGES.md)
- [Evidencias de validacao](docs/evidence.md)
- [Changelog](docs/CHANGELOG.md)

## Qualidade e CI

O workflow `Quality and security` roda em pull requests e pushes para `develop` e `main`. Ele valida formatação, sintaxe OpenTofu, scripts Bash, lint IaC, segurança IaC, segredos, documentação gerada e TechDocs sem usar credenciais reais do vSphere nem backend remoto.

Os comandos principais podem ser reproduzidos localmente:

```bash
tofu fmt -check -recursive -diff
TOFU_CI_DATA_DIR=$(mktemp -d)
export TF_DATA_DIR="$TOFU_CI_DATA_DIR"
tofu init -backend=false -input=false
tofu validate -no-color
rm -rf "$TOFU_CI_DATA_DIR"
unset TF_DATA_DIR

docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck-alpine@sha256:9955be09ea7f0dbf7ae942ac1f2094355bb30d96fffba0ec09f5432207544002 shellcheck $(git ls-files '*.sh')
docker run --rm -v "$PWD:/data" -w /data ghcr.io/terraform-linters/tflint@sha256:80979608a412232a918a0178765b98149bdc43181276cee6612ad1cf4cdf35e1 --recursive --minimum-failure-severity=warning
docker run --rm -v "$PWD:/workspace" -w /workspace ghcr.io/aquasecurity/trivy@sha256:be1190afcb28352bfddc4ddeb71470835d16462af68d310f9f4bca710961a41e fs --scanners misconfig,secret --severity HIGH,CRITICAL --exit-code 1 --no-progress --skip-dirs .git --skip-dirs .terraform .

./scripts/check_sensitive_files.sh
# Opcional: verifica artefatos sensiveis ignorados no disco local.
./scripts/check_sensitive_files.sh --local
# Opcional: lista/remove planos persistentes e metadados locais de state.
./scripts/clean_local_artifacts.sh --dry-run
./scripts/clean_local_artifacts.sh
./scripts/check_generated_docs.sh

TECHDOCS_VENV=$(mktemp -d)
python3 -m venv "$TECHDOCS_VENV"
"$TECHDOCS_VENV/bin/python" -m pip install "mkdocs-techdocs-core==1.6.2"
"$TECHDOCS_VENV/bin/mkdocs" build --strict
rm -rf "$TECHDOCS_VENV"
```

Evite gerar planos persistentes na raiz, como `tofu plan -out=tfplan`. Os scripts `apply.sh` e `destroy.sh` usam planos temporarios e o preflight bloqueia planos locais obsoletos antes de aplicar mudancas.

O workflow `Prod safety guardrails` continua separado e verifica somente os bloqueios contra destruicao de producao.

## Resumo de Segurança

- O ambiente de producao possui protecoes especiais e `prevent_destroy`.
- Operacoes destrutivas exigem plano revisado e confirmacao forte em `dev` e `homolog`.
- `prod` nao pode ser destruido pelo `destroy.sh`; excecoes seguem processo break-glass documentado.
- States, planos, credenciais e arquivos locais sensiveis sao bloqueados por `.gitignore`, scripts e CI.

## 🤝 Contribuindo

1. Fork o projeto
2. Crie uma branch para sua feature (`git checkout -b feature/AmazingFeature`)
3. Commit suas mudanças (`git commit -m 'feat: Add amazing feature'`)
4. Push para a branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

## 📄 Convenções de Commit

Seguimos o padrão [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` Nova funcionalidade
- `fix:` Correção de bug
- `docs:` Documentação
- `chore:` Manutenção
- `refactor:` Refatoração
- `test:` Testes

## ⚠️ Notas Importantes

- Sempre revise os planos antes de aplicar
- Mantenha os arquivos de configuração atualizados
- Use tags semânticas para releases
- Atualize a documentação após mudanças significativas

## Suporte

Para suporte, abra uma issue no repositorio com o contexto, comandos executados e logs sanitizados. Nunca publique credenciais, state, planos ou detalhes reais de inventario.

## 📜 Licença

Este projeto está sob a licença MIT. Veja o arquivo [LICENSE](LICENSE) para mais detalhes.

## CI/CD

Os principais checks locais estao agrupados no `Makefile`:

```bash
make validate
make security-check
make techdocs
```

A documentação é atualizada através dos scripts em `scripts/`:
- `update_changelog.sh`: Mantém o CHANGELOG.md atualizado
- `update_env_docs.sh`: Atualiza a documentação dos ambientes
- `update_environments_md.sh`: Atualiza o resumo redigido por ambiente
- `update_vm_state.sh`: Atualiza o resumo redigido das VMs
- `update_readme_tfdocs.sh`: Regenera o bloco OpenTofu do README com `terraform-docs`

## Referência OpenTofu

O contrato de entrada usa `zones` como fonte única para vCenter, datacenter, cluster, datastore e redes. Variáveis globais antigas como `data_center`, `cluster`, `data_store`, `networks`, `dns_servers`, `interface`, `tags`, `firewall_rules`, `backup_policies`, `security_levels` e `efi_secure_boot_enabled` não fazem parte do contrato atual.

Ao migrar `tfvars` antigos, mantenha `default_zone` explicito em cada ambiente e remova `interface` das redes. O nome de interface Linux do guest nao e usado porque a customizacao de rede passa pelo provider vSphere.

O bloco abaixo e gerado a partir dos arquivos `.tf`:

```bash
./scripts/update_readme_tfdocs.sh
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11.6, < 1.12.0 |
| <a name="requirement_vsphere"></a> [vsphere](#requirement\_vsphere) | 2.14.2 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_vsphere"></a> [vsphere](#provider\_vsphere) | 2.14.2 |

## Resources

| Name | Type |
|------|------|
| [vsphere_virtual_machine.vm](https://registry.terraform.io/providers/vmware/vsphere/2.14.2/docs/resources/virtual_machine) | resource |
| [vsphere_virtual_machine.vm_nonprod](https://registry.terraform.io/providers/vmware/vsphere/2.14.2/docs/resources/virtual_machine) | resource |

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|:--------:|
| <a name="input_default_zone"></a> [default\_zone](#input\_default\_zone) | Zona padrao de infraestrutura usada por VMs que nao definem zone | `string` | no |
| <a name="input_domain"></a> [domain](#input\_domain) | Nome do domínio | `string` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Ambiente de deploy (dev, homolog, prod) | `string` | yes |
| <a name="input_firmware"></a> [firmware](#input\_firmware) | Defina o firmware. EX: efi | `string` | no |
| <a name="input_guest_id"></a> [guest\_id](#input\_guest\_id) | ID padrao do sistema operacional guest usado quando a VM nao define guest\_id | `string` | no |
| <a name="input_net_adapter_type"></a> [net\_adapter\_type](#input\_net\_adapter\_type) | Defina o tipo de adaptador. EX: e1000e, vmxnet3 | `string` | no |
| <a name="input_password"></a> [password](#input\_password) | Defina a senha de usuário do Vsphere | `string` | yes |
| <a name="input_thin_provisioned"></a> [thin\_provisioned](#input\_thin\_provisioned) | Defina o thin\_provisioned. EX: true | `bool` | no |
| <a name="input_username"></a> [username](#input\_username) | Defina o nome de usuario com acesso ao Vsphere | `string` | yes |
| <a name="input_vm"></a> [vm](#input\_vm) | Configuração das máquinas virtuais | <pre>map(object({<br/>    ipv4_address               = string<br/>    name                       = string<br/>    hostname                   = string<br/>    network                    = string<br/>    zone                       = optional(string)<br/>    memory                     = number<br/>    cpus                       = number<br/>    disk_size                  = number<br/>    disk_size_data             = optional(number)<br/>    folder                     = optional(string)<br/>    guest_id                   = optional(string)<br/>    wait_for_guest_net_timeout = optional(number, 5)<br/>  }))</pre> | yes |
| <a name="input_vm_template"></a> [vm\_template](#input\_vm\_template) | Caminho do template da VM | `string` | yes |
| <a name="input_vsphere_allow_unverified_ssl"></a> [vsphere\_allow\_unverified\_ssl](#input\_vsphere\_allow\_unverified\_ssl) | Permite conexao TLS sem verificacao com o vCenter. Mantido como true por decisao operacional em ambiente controlado. | `bool` | no |
| <a name="input_zones"></a> [zones](#input\_zones) | Zonas de infraestrutura que decidem vCenter, datacenter, cluster, datastore, redes e prefixo opcional de nome | <pre>map(object({<br/>    vsphere_server = string<br/>    data_center    = string<br/>    cluster        = string<br/>    data_store     = string<br/>    vm_name_prefix = optional(string, "")<br/>    networks = map(object({<br/>      name            = string<br/>      gateway         = string<br/>      netmask         = number<br/>      dns_server_list = list(string)<br/>      domain_name     = string<br/>    }))<br/>  }))</pre> | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_primary_vm_ip"></a> [primary\_vm\_ip](#output\_primary\_vm\_ip) | IP da VM principal |
| <a name="output_primary_vm_name"></a> [primary\_vm\_name](#output\_primary\_vm\_name) | Nome da VM principal |
| <a name="output_primary_vm_status"></a> [primary\_vm\_status](#output\_primary\_vm\_status) | Status da VM principal |
| <a name="output_vm_details"></a> [vm\_details](#output\_vm\_details) | n/a |
| <a name="output_vm_info_json"></a> [vm\_info\_json](#output\_vm\_info\_json) | Todas as informações das VMs em formato JSON |
| <a name="output_vm_ip"></a> [vm\_ip](#output\_vm\_ip) | IP addresses of provisioned VMs (JSON encoded) |
| <a name="output_vm_names"></a> [vm\_names](#output\_vm\_names) | Names of created VMs (JSON encoded) |
| <a name="output_vm_summary"></a> [vm\_summary](#output\_vm\_summary) | Resumo formatado das informações das VMs |
<!-- END_TF_DOCS -->

## 🔧 Troubleshooting

### Problemas Comuns

1. **Erro de autenticação no vSphere**
   - Verifique se as credenciais em `terraform.tfvars` estão corretas
   - Confirme se o usuário tem permissões adequadas no vCenter

2. **Template não encontrado**
   - Verifique se o template especificado em `vm_template` existe no vCenter
   - Use o caminho completo do template

3. **Erro de rede**
   - Confirme se as redes especificadas existem no datacenter
   - Verifique se os IPs estão disponíveis na rede

4. **Timeout na customização**
   - Aumente o `wait_for_guest_net_timeout` se necessário
   - Verifique conectividade de rede da VM

### Comandos Úteis

```bash
# Verificar estado dos recursos
tofu plan

# Aplicar pelo fluxo seguro do ambiente
./apply.sh dev

# Destruir ambiente nao produtivo com guardrails
./destroy.sh dev
```
