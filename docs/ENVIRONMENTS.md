# Ambientes Gerenciados

Este documento e gerado automaticamente a partir de `env_vars/*.tfvars`.

Detalhes de inventario como vCenter, datacenter, cluster, datastore, portgroups, enderecos IP, DNS, nomes de VM e hostnames nao sao publicados aqui. Consulte os arquivos de variaveis e o state remoto apenas nos fluxos operacionais autorizados.

## Lista de Ambientes

| Ambiente | Zonas declaradas | Redes declaradas | VMs declaradas |
| --- | ---: | ---: | ---: |
| dev | 1 | 1 | 1 |
| homolog | 1 | 2 | 1 |
| prod | 1 | 2 | 1 |

## Politica de Exposicao

- Os Markdown gerados publicam somente metadados agregados.
- Inventario sensivel deve permanecer nos `tfvars`, no vCenter, no gerenciador de senhas ou no state remoto, conforme o fluxo operacional autorizado.
- Regere este arquivo com `./scripts/update_env_docs.sh` apos alteracoes em `env_vars/*.tfvars`.
