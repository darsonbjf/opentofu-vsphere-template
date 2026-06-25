#!/usr/bin/env bash
set -e

echo "Detectando sistema operacional..."
OS_TYPE=$(uname -s)

# Alterado: verificação genérica para macOS usando regex
if [[ "$OS_TYPE" =~ Darwin ]]; then
    echo "Sistema: macOS"
    if ! command -v brew &> /dev/null; then
        echo "Homebrew não encontrado. Instale o Homebrew em: https://brew.sh/"
        exit 1
    fi
    echo "Atualizando Homebrew..."
    brew update
    echo "Instalando dependências..."
    brew install git curl wget terraform opentofu || true

elif [[ "$OS_TYPE" == "Linux" ]]; then
    # Detecta se está em WSL2
    if grep -qi microsoft /proc/version; then
        echo "WSL2 detectado."
    else
        echo "Sistema Linux nativo detectado."
    fi

    if command -v apt-get &> /dev/null; then
        echo "Atualizando APT..."
        sudo apt-get update
        echo "Instalando dependências..."
        sudo apt-get install -y git curl wget terraform opentofu || true
    elif command -v dnf &> /dev/null; then
        echo "Atualizando DNF..."
        sudo dnf update -y
        echo "Instalando dependências..."
        sudo dnf install -y git curl wget terraform opentofu || true
    else
        echo "Gerenciador de pacotes não suportado neste Linux."
        exit 1
    fi

else
    echo "Sistema operacional não suportado."
    exit 1
fi

echo "Ambiente configurado com sucesso!"
