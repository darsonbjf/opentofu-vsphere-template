# Changelog

Todas as alterações notáveis neste projeto serão documentadas neste arquivo.
O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/),
e este projeto adere ao [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
## [Não Publicado]
### Adicionado
- feat: melhorar tipos de variáveis (bool em vez de string para thin_provisioned e efi_secure_boot_enabled)
- feat: adicionar verificação de instalação do OpenTofu nos scripts apply.sh e destroy.sh
- feat: criar arquivo .opentofu-version para especificar versão do OpenTofu
- feat: expandir README com seções de troubleshooting e extensibilidade
- feat: melhorar comentários no código main.tf
- feat: atualizar .gitignore para ignorar diretório .terraform/
- feat: **SEGURANÇA CRÍTICA** - implementar proteção total contra destruição de ambientes de produção no destroy.sh
- feat: adicionar detecção inteligente de produção baseada em redes, gateways e folders configurados
- feat: abortar imediatamente execução se ambiente de produção for detectado, com mensagem visual clara
- feat: adicionar script para atualização automática do changelog e melhorar a documentação dos ambientes
- feat: atualizar documentação de ambientes e melhorar a configuração de tags no Terraform
- feat: adicionar especificações detalhadas dos ambientes e simplificar a configuração de tags no Terraform
- feat: melhorar a compatibilidade de scripts, atualizar documentação de ambientes e adicionar validações de variáveis
- feat: adicionar suporte a chaves SSH, atualizar scripts e documentação de ambientes
- feat: adicionar suporte a chaves SSH e atualizar detalhes da configuração das VMs
- feat: atualizar detalhes das VMs e remover script de atualização de changelog
- feat: atualizar CHANGELOG com novas entradas e melhorias na configuração de VMs
- feat: adicionar documentação detalhada das VMs e aprimorar script de implantação com geração automática de relatórios
- feat: remover arquivo de configuração cloud-init e aprimorar script de implantação com resumo detalhado das VMs
- feat: adicionar saídas e variáveis para configuração de VMs e script de remoção
- feat: adicionar script para instalação automática do terraform-docs e atualizar README e CHANGELOG
- feat: adicionar e atualizar o CHANGELOG e script de atualização
- feat: Update VM template and increase disk size for improved performance
- feat: Update VM configuration with new IP and name for testing
- feat: Refactor network configuration to support multiple VMs and dynamic gateway lookup
- feat: Adicionar configuração de cloud-init e atualizar provedores no Terraform
- feat: Atualizar configuração de máquinas virtuais e adicionar suporte a fuso horário
- feat: Update disk size handling in virtual machine configuration
- feat: Update variables (memory and cpus) and main configuration for virtual machines.
### Modificado
- refactor: atualizar provedores e melhorar validações de variáveis
- refactor: Refatorar configuração de máquinas virtuais para suporte a múltiplas redes e discos dinâmicos
### Corrigido
- fix: corrigir mensagem de erro para validações de memória e disco na variável vm
- fix: ajustar validações de memória e tamanho de disco para a variável vm
- fix: atualizar configuração do provedor cloudinit e ajustar interface de rede para 'ens192'
- fix: atualizar interface de rede para 'ens33' no arquivo variables.tf
- fix: atualizar template da máquina virtual para Ubuntu 22.04
### Infraestrutura
- chore: commit pending changes before merge
