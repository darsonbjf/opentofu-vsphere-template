# Zonas de Infraestrutura

As zonas definem onde cada VM sera provisionada no vSphere. A zona decide vCenter, datacenter, cluster, datastore, redes e um prefixo opcional para nome de VM.

As redes declaradas em uma zona representam portgroups do vSphere e parametros de customizacao do guest, como gateway, mascara, DNS e dominio. O nome de interface Linux do guest nao faz parte do contrato atual porque nao ha cloud-init/netplan ativo neste template.

## Zona Atual

A zona de exemplo versionada e `primary-zone`.

```hcl
default_zone = "primary-zone"
```

Cada arquivo `env_vars/<ambiente>.tfvars` deve declarar `default_zone` explicitamente e manter uma chave correspondente em `zones`.

Essa zona aponta para o vCenter declarado no `tfvars` do ambiente:

```hcl
vsphere_server = "<vcenter-fqdn>"
```

Essa zona usa os valores de vSphere declarados no ambiente e preserva o padrao de nomes existente. Com `vm_name_prefix = ""`, a VM continua seguindo o formato:

```text
WORKSPACE-NOME-IP
```

Exemplo redigido:

```text
WORKSPACE-VM-N.N.N.N
```

## Override por VM

Cada ambiente define uma zona padrao, mas uma VM pode sobrescrever a zona quando uma segunda zona existir:

```hcl
vm = {
  vm1 = {
    name         = "VM1"
    zone         = "primary-zone"
    network      = "<rede-logica>"
    ipv4_address = "<ipv4-estatico>"
  }
}
```

Se `zone` nao for informado na VM, o OpenTofu usa `default_zone`.

## Provider vSphere

O provider vSphere usa o `vsphere_server` da `default_zone`. Hoje existe um unico provider por execucao, entao todas as zonas declaradas em um mesmo ambiente devem apontar para o mesmo vCenter.

Se uma futura zona precisar de outro vCenter, o projeto ja tem o campo de zona para declarar isso, mas suporte real a multiplos vCenters no mesmo apply exigira refatoracao para provider aliases e/ou modulos.

## Folders por Faixa de IP

O folder vSphere e derivado automaticamente a partir do IP da VM. O campo `folder` pode continuar nos `tfvars` por compatibilidade, mas, quando informado, deve bater com a faixa do IP.

| CIDR | Folder |
| --- | --- |
| `192.0.2.0/24` | `DEVELOPMENT` |
| `198.51.100.0/24` | `STAGING` |
| `203.0.113.0/24` | `PRODUCTION` |

O plano falha se uma VM usar IP fora dessas faixas, se o IP nao pertencer ao CIDR da network declarada, ou se o ambiente informado for incompativel com o folder derivado pelo IP.

Esses folders sao fixos no vSphere. Para liberar uma nova faixa de IP, atualize `local.vm_folder_by_cidr` em `variables.tf`, replique a tabela no README e neste documento, e rode `./scripts/check_folder_mapping_docs.sh` junto de `./scripts/check_generated_docs.sh`. O CI falha se a documentacao divergir do mapeamento usado pelo OpenTofu.

## Migracao de Redes Antigas

O contrato atual nao usa o atributo `interface` nas redes. Ao migrar `tfvars` antigos, remova esse atributo e mantenha somente `name`, `gateway`, `netmask`, `dns_server_list` e `domain_name`.
