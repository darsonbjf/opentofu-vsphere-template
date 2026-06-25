#!/bin/bash
set -e

REQUIRED_PACKAGES=("git" "curl" "wget")

detect_linux_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    else
        echo "none"
    fi
}

install_or_update_package_linux() {
    local pkg=$1
    local pm=$2
    if [ "$pm" == "apt" ]; then
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            echo "$pkg já instalado. Atualizando..."
            sudo apt-get install --only-upgrade -y "$pkg"
        else
            echo "Instalando $pkg..."
            sudo apt-get install -y "$pkg"
        fi
    elif [ "$pm" == "yum" ]; then
        if rpm -q "$pkg" >/dev/null 2>&1; then
            echo "$pkg já instalado. Atualizando..."
            sudo yum update -y "$pkg"
        else
            echo "Instalando $pkg..."
            sudo yum install -y "$pkg"
        fi
    else
        echo "Gerenciador de pacotes não suportado no Linux."
        exit 1
    fi
}

install_or_update_package_macos() {
    local pkg=$1
    if brew list "$pkg" >/dev/null 2>&1; then
        echo "$pkg já instalado. Atualizando..."
        brew upgrade "$pkg"
    else
        echo "Instalando $pkg..."
        brew install "$pkg"
    fi
}

install_or_update_opentofu() {
    local os=$1
    local pm=$2
    
    if command -v tofu >/dev/null 2>&1; then
        echo "OpenTofu já está instalado. Versão atual:"
        tofu version
    else
        echo "Instalando OpenTofu..."
        
        if [ "$os" == "Linux" ]; then
            if [ "$pm" == "apt" ]; then
                # Para sistemas baseados em Debian/Ubuntu
                wget -O- https://get.opentofu.org/gpg-key.asc | sudo gpg --dearmor -o /usr/share/keyrings/opentofu-archive-keyring.gpg
                echo "deb [signed-by=/usr/share/keyrings/opentofu-archive-keyring.gpg] https://get.opentofu.org/apt stable main" | sudo tee /etc/apt/sources.list.d/opentofu.list
                sudo apt-get update
                sudo apt-get install -y opentofu
            elif [ "$pm" == "yum" ]; then
                # Para sistemas baseados em RHEL/CentOS
                sudo yum install -y yum-utils
                sudo yum-config-manager --add-repo https://get.opentofu.org/yum/tofu.repo
                sudo yum install -y opentofu
            else
                # Instalação genérica para outros sistemas Linux
                curl -L https://get.opentofu.org/install-opentofu.sh | sudo bash
            fi
        elif [ "$os" == "Darwin" ]; then
            # Instalação via Homebrew para macOS
            brew install opentofu
        fi
        
        echo "OpenTofu instalado com sucesso. Versão:"
        tofu version
    fi
}

main() {
    OS=$(uname)
    echo "Detectando sistema operacional: $OS"
    if [ "$OS" == "Linux" ]; then
        PM=$(detect_linux_package_manager)
        if [ "$PM" == "none" ]; then
            echo "Nenhum gerenciador de pacotes suportado encontrado!"
            exit 1
        fi
        echo "Atualizando lista de pacotes..."
        if [ "$PM" == "apt" ]; then
            sudo apt-get update -y
        elif [ "$PM" == "yum" ]; then
            sudo yum check-update || true
        fi
        for pkg in "${REQUIRED_PACKAGES[@]}"; do
            install_or_update_package_linux "$pkg" "$PM"
        done
        
        # Instalar ou atualizar OpenTofu
        echo "Verificando OpenTofu..."
        install_or_update_opentofu "$OS" "$PM"
        
    elif [ "$OS" == "Darwin" ]; then
        if ! command -v brew >/dev/null 2>&1; then
            echo "Homebrew não encontrado. Instalando Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        echo "Atualizando Homebrew..."
        brew update
        for pkg in "${REQUIRED_PACKAGES[@]}"; do
            install_or_update_package_macos "$pkg"
        done
        
        # Instalar ou atualizar OpenTofu
        echo "Verificando OpenTofu..."
        install_or_update_opentofu "$OS" ""
        
    else
        echo "Sistema operacional não suportado."
        exit 1
    fi
    echo "Todos os requisitos foram verificados e atualizados se necessário."
}

main