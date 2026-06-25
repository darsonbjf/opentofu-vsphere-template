#!/bin/bash

# Script para gerenciar workspaces do OpenTofu
# Uso: ./workspace.sh [list|new|select|delete] [nome_do_workspace]

# Verifica se o OpenTofu está instalado
if ! command -v tofu &> /dev/null; then
    echo "❌ OpenTofu não está instalado ou não está no PATH."
    echo "📝 Instale o OpenTofu antes de continuar."
    exit 1
fi

# Cores para melhor visualização
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para mostrar a ajuda
show_help() {
    echo -e "${BLUE}Gerenciador de Workspaces do OpenTofu${NC}"
    echo
    echo -e "Uso: ${GREEN}TOFU_BACKEND_CONFIG=backend/<ambiente>.s3.tfbackend $0 COMANDO${NC} [ARGUMENTOS]"
    echo -e "     Se o diretório já estiver inicializado em .terraform, TOFU_BACKEND_CONFIG é opcional."
    echo
    echo -e "Comandos disponíveis:"
    echo -e "  ${GREEN}list${NC}           Lista todos os workspaces existentes"
    echo -e "  ${GREEN}new${NC} NOME       Cria um novo workspace com o nome especificado"
    echo -e "  ${GREEN}select${NC} NOME    Seleciona um workspace existente"
    echo -e "  ${GREEN}delete${NC} NOME    Deleta um workspace existente (não pode ser o atual)"
    echo -e "  ${GREEN}help${NC}           Exibe esta ajuda"
    echo
    echo -e "Exemplo: TOFU_BACKEND_CONFIG=backend/dev.s3.tfbackend $0 ${GREEN}new${NC} DEVELOP"
}

# Função para listar workspaces
list_workspaces() {
    echo -e "${BLUE}Workspaces disponíveis:${NC}"
    tofu workspace list
}

# Função para criar um novo workspace
new_workspace() {
    if [ -z "$1" ]; then
        echo -e "${RED}Erro: Nome do workspace não especificado${NC}"
        echo -e "Use: $0 new NOME"
        return 1
    fi
    
    echo -e "${YELLOW}Criando workspace:${NC} $1"
    if tofu workspace new "$1"; then
        echo -e "${GREEN}✓ Workspace '$1' criado com sucesso!${NC}"
        return 0
    else
        echo -e "${RED}❌ Erro ao criar o workspace '$1'.${NC}"
        return 1
    fi
}

# Função para selecionar um workspace
select_workspace() {
    if [ -z "$1" ]; then
        echo -e "${RED}Erro: Nome do workspace não especificado${NC}"
        echo -e "Use: $0 select NOME"
        return 1
    fi
    
    echo -e "${YELLOW}Selecionando workspace:${NC} $1"
    if tofu workspace select "$1"; then
        echo -e "${GREEN}✓ Workspace '$1' selecionado!${NC}"
        return 0
    else
        echo -e "${RED}❌ Erro ao selecionar workspace '$1'.${NC}"
        echo -e "${YELLOW}O workspace existe? Verifique com: $0 list${NC}"
        return 1
    fi
}

# Função para deletar um workspace
delete_workspace() {
    if [ -z "$1" ]; then
        echo -e "${RED}Erro: Nome do workspace não especificado${NC}"
        echo -e "Use: $0 delete NOME"
        return 1
    fi
    
    # Verifica se o workspace a ser deletado é o atual
    CURRENT_WORKSPACE=$(tofu workspace show 2>/dev/null)
    if [ "$CURRENT_WORKSPACE" = "$1" ]; then
        echo -e "${RED}❌ Não é possível deletar o workspace atual.${NC}"
        echo -e "${YELLOW}Mude para outro workspace primeiro com: $0 select OUTRO_WORKSPACE${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Deletando workspace:${NC} $1"
    read -r -p "Tem certeza que deseja deletar o workspace '$1'? (s/N) " confirm
    if [[ $confirm == [sS] || $confirm == [sS][iI][mM] ]]; then
        if tofu workspace delete "$1"; then
            echo -e "${GREEN}✓ Workspace '$1' deletado com sucesso!${NC}"
            return 0
        else
            echo -e "${RED}❌ Erro ao deletar o workspace '$1'.${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}Operação cancelada.${NC}"
        return 0
    fi
}

# Verifica se o OpenTofu está inicializado
if [ ! -d ".terraform" ]; then
    echo -e "${YELLOW}⚠️ Parece que o OpenTofu não está inicializado neste diretório.${NC}"
    if [ -n "${TOFU_BACKEND_CONFIG:-}" ]; then
        echo -e "${BLUE}Inicializando OpenTofu com backend remoto:${NC} ${TOFU_BACKEND_CONFIG}"
        if ! tofu init -reconfigure -backend-config="$TOFU_BACKEND_CONFIG"; then
            echo -e "${RED}❌ Falha ao inicializar o OpenTofu.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ O OpenTofu precisa ser inicializado com um backend remoto para gerenciar workspaces.${NC}"
        echo -e "${YELLOW}Use ./apply.sh <ambiente> ou execute com TOFU_BACKEND_CONFIG=backend/<ambiente>.s3.tfbackend.${NC}"
        echo -e "${YELLOW}Exemplo: TOFU_BACKEND_CONFIG=backend/dev.s3.tfbackend $0 list${NC}"
        exit 1
    fi
fi

# Processa os comandos
case "$1" in
    list)
        list_workspaces
        ;;
    new)
        new_workspace "$2"
        ;;
    select)
        select_workspace "$2"
        ;;
    delete)
        delete_workspace "$2"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Comando não reconhecido: $1${NC}"
        show_help
        exit 1
        ;;
esac

exit $?
