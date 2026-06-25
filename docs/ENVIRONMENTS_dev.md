## Informacoes Redigidas do Ambiente dev

Este documento e gerado automaticamente por `scripts/update_environments_md.sh`.

Valores de inventario como vCenter, datacenter, cluster, datastore, portgroups, enderecos IP, DNS, nomes de VM e hostnames foram omitidos de proposito.

### Resumo

| Campo | Valor |
| --- | --- |
| Ambiente | dev |
| Zonas declaradas | 1 |
| Redes declaradas | 1 |
| VMs declaradas | 1 |

### Perfis de VM

| Item | vCPUs | Memoria | Disco de SO | Disco de dados | Timeout de rede |
| --- | ---: | ---: | ---: | ---: | ---: |
| VM 1 | 4 | 2,0 GiB | 100 GiB | 500 GiB | 300 s |

### Acesso ao Guest

O template OpenTofu nao gerencia acesso nem configuracao interna do guest. Use o procedimento operacional do template base da VM ou da equipe responsavel pelo sistema operacional.
