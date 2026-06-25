# Backend Ceph RGW

O state do OpenTofu é armazenado em buckets S3-compatible no Ceph RGW. Cada ambiente tem bucket e credencial próprios para reduzir o escopo de acesso.

| Ambiente | Bucket | Usuário técnico |
| --- | --- | --- |
| dev | `opentofu-vsphere-template-dev` | `rgw-opentofu-template-dev` |
| homolog | `opentofu-vsphere-template-homolog` | `rgw-opentofu-template-homolog` |
| prod | `opentofu-vsphere-template-prod` | `rgw-opentofu-template-prod` |

## Autenticação

As credenciais ficam no gerenciador de senhas e não devem ser versionadas. Antes de executar qualquer operação, obtenha a credencial do ambiente no gerenciador de senhas.

Para uso nao interativo, exporte as variaveis:

```bash
export CEPH_RGW_ACCESS_KEY_ID="<access-key-do-ambiente>"
export CEPH_RGW_SECRET_ACCESS_KEY="<secret-key-do-ambiente>"
```

Para uso interativo, `./apply.sh <ambiente>` e `./destroy.sh <ambiente>` pedirao `CEPH_RGW_ACCESS_KEY_ID` e `CEPH_RGW_SECRET_ACCESS_KEY` quando elas nao estiverem definidas nem existirem em cache local valido. A entrada fica visivel no terminal para que a pessoa confira o valor colado. Os valores sao exportados somente no processo do script e nos comandos filhos.

Depois da primeira leitura, os scripts salvam as credenciais em cache local por ambiente ate 00:00 do dia atual. O cache fica fora do repositorio, com permissao `600`, em `${XDG_RUNTIME_DIR}/opentofu-vsphere-template/rgw-credentials` quando disponivel ou em `~/.cache/opentofu-vsphere-template/rgw-credentials` como fallback. Use `CEPH_RGW_REFRESH_CACHE=1 ./apply.sh <ambiente>` para forcar nova leitura do gerenciador de senhas e substituir o cache, ou `CEPH_RGW_DISABLE_CACHE=1 ./apply.sh <ambiente>` para nao reutilizar nem atualizar o cache.

As credenciais devem ser únicas por ambiente, compartilhadas via gerenciador de senhas e rotacionadas regularmente. Não use credencial de um ambiente para outro.

Campos recomendados no gerenciador de senhas: `CEPH_RGW_ACCESS_KEY_ID`, `CEPH_RGW_SECRET_ACCESS_KEY`, `RGW_ENDPOINT`, `BUCKET` e `RGW_USER`.

O Ceph RGW nao exige selecao de zona pelo operador deste projeto. O valor `region = "default"` nos arquivos `backend/*.s3.tfbackend` existe apenas por compatibilidade com o backend S3-compatible do OpenTofu.

## Guardrail Antes do OpenTofu

O `apply.sh` e o `destroy.sh` validam o backend e o acesso ao bucket antes de executar qualquer comando OpenTofu. A operacao so continua se o ambiente solicitado, o `env_vars/<ambiente>.tfvars`, o `backend/<ambiente>.s3.tfbackend` e a credencial RGW apontarem para o bucket correto.

| Comando | Bucket obrigatorio |
| --- | --- |
| `./apply.sh dev` | `opentofu-vsphere-template-dev` |
| `./apply.sh homolog` | `opentofu-vsphere-template-homolog` |
| `./apply.sh prod` | `opentofu-vsphere-template-prod` |

O `destroy.sh` e permitido somente para `dev` e `homolog`. Ele bloqueia `prod` antes de carregar credenciais, bloqueia tfvars com sinais de producao, bloqueia VMs nas redes produtivas configuradas no guardrail, gera `tofu plan -destroy` para revisao e so entao exige confirmacao exata `DESTROY <ambiente> <workspace>`. A execucao usa um plano temporario fora da raiz do repositorio com `tofu apply`, removido ao final da execucao.

A protecao de producao nao depende apenas do script. O recurso `vsphere_virtual_machine.vm` gerencia somente producao e usa `lifecycle.prevent_destroy = true`, entao comandos diretos como `tofu destroy` ou planos que exigiriam replacement destrutivo em `prod` devem falhar enquanto o guardrail estiver versionado. `dev` e `homolog` usam `vsphere_virtual_machine.vm_nonprod` e continuam operaveis pelo fluxo normal.

O fluxo de excecao para mudancas destrutivas de producao esta em [Mudancas destrutivas em producao](PROD_DESTRUCTIVE_CHANGES.md). A migracao unica de state para ambientes nao produtivos deve ser feita com:

```bash
./scripts/migrate_nonprod_vm_state.sh dev
./scripts/migrate_nonprod_vm_state.sh homolog
```

Se houver divergencia de ambiente, bucket ou permissao RGW, o script cancela imediatamente com aviso critico em vermelho e nao executa `tofu init`, `tofu plan`, `tofu apply` ou `tofu destroy`.

## Inicialização

Os scripts executam `tofu init -reconfigure` usando o arquivo de backend correto:

```bash
./apply.sh dev
./apply.sh homolog
./apply.sh prod
```

Para inicialização manual:

```bash
tofu init -reconfigure -backend-config=backend/dev.s3.tfbackend
tofu workspace select DEVELOP
```

## Locking e Versionamento

Os buckets foram validados com versionamento habilitado. O backend usa `use_lockfile = true`, então o OpenTofu cria um objeto de lock no próprio bucket durante operações que exigem exclusividade.

## Limitações Temporárias

- `insecure = false` nos arquivos versionados. Altere somente se o seu endpoint S3-compatible exigir.
- SSE/SSE-KMS no Ceph RGW ainda não está habilitado porque depende da implantação do HashiCorp Vault.
- O endpoint configurado é `https://s3.example.com`, usado apenas como placeholder. Não use HTTP para operação real com state.

## Artefatos de Plano

Planos OpenTofu sao artefatos locais e temporarios. Os scripts criam esses arquivos fora da raiz do repositorio e os removem ao final da execucao; eles nao devem ser versionados, enviados ao bucket de state ou compartilhados como artefato permanente.
