#!/usr/bin/env bash
set -o errexit   # Aborta a execução se um comando falhar
set -o nounset   # Aborta a execução se uma variável não definida for usada
set -o pipefail  # Aborta se algum comando em um pipeline falhar
# set -x           # Modo de depuração: imprime cada comando antes de executá-lo

# --- Variáveis de Configuração ---
# O diretório base do projeto (onde este script e outros arquivos estão)
BASE_DIR="$(pwd)" 
BESU_VERSION="24.7.0"
JAVA_VERSION="jdk-21.0.7" # Nome do diretório que o JDK será extraído
JAVA_TAR_GZ="jdk-21.0.7_linux-x64_bin.tar.gz"
BESU_TAR_GZ="besu-${BESU_VERSION}.tar.gz"
EXTERNAL_DEPLOY_ACCOUNT="0xfe3b557e8fb62b89f4916b721be55ceb828dbd73" # Conta externa para implantação de contratos, do README.md
# --- Funções Auxiliares ---

# Função para limpar arquivos e contêineres de execuções anteriores
cleanup() {
    echo "--- Limpando arquivos e contêineres de uma execução anterior ---"
    # Derruba todos os contêineres definidos no docker-compose.yaml, ignorando erros se não estiverem rodando
    sudo docker-compose down || true 
    # Remove diretórios e arquivos gerados
    sudo rm -rf besu-* "${JAVA_VERSION}" networkFiles Permissioned-Network/ genesis.json
    echo "Limpeza concluída."
}

# Função para instalar o Besu e o Java
install_dependencies() {
    echo "--- Instalando Dependências: Hyperledger Besu ---"
    # Instala o Docker
    sudo snap install docker
    # Baixa o pacote do Besu
    wget "https://github.com/hyperledger/besu/releases/download/${BESU_VERSION}/${BESU_TAR_GZ}"
    # Extrai o arquivo tar.gz
    tar -xvf "${BESU_TAR_GZ}"
    # Remove o arquivo tar.gz após a extração
    rm "${BESU_TAR_GZ}"
    # Adiciona o diretório de executáveis do Besu ao PATH
    export PATH="${BASE_DIR}/besu-${BESU_VERSION}/bin:$PATH"
    echo "Hyperledger Besu v${BESU_VERSION} instalado e PATH configurado."

    echo "--- Instalando Dependências: JAVA ---"
    # Baixa o pacote do JDK
    wget "https://download.oracle.com/java/21/archive/${JAVA_TAR_GZ}"
    # Extrai o arquivo tar.gz
    tar -xvf "${JAVA_TAR_GZ}"
    # Remove o arquivo tar.gz após a extração
    rm "${JAVA_TAR_GZ}"
    # Define a variável de ambiente JAVA_HOME
    export JAVA_HOME="${BASE_DIR}/${JAVA_VERSION}"
    echo "JAVA ${JAVA_VERSION} instalado e JAVA_HOME configurado."

    # Verifica a versão do Besu para confirmar a instalação
    echo "--- Verificando a versão do Besu ---"
    besu --version
}

# Função para gerar chaves e arquivos de configuração da rede
generate_keys_and_configs() {
    echo "--- Etapa 1: Geração de Chaves e Ficheiros de Configuração ---"

    # 1. Torna o script generate-nodes-config.sh executável
    # O generate-nodes-config.sh fornecido já define o IP como 127.0.0.1.
    # Apenas garantimos que o script seja executável.
    chmod +x generate-nodes-config.sh
    echo "Script generate-nodes-config.sh configurado com IP da maquina (verifique o conteúdo do script)."

    # 2. Gera os arquivos da blockchain e as chaves privadas
    echo "Gerando arquivos da blockchain e chaves privadas em networkFiles/..."
    besu operator generate-blockchain-config \
        --config-file=genesis_QBFT.json \
        --to=networkFiles \
        --private-key-file-name=key
    echo "Arquivos da blockchain e chaves gerados."

    # 3. Copia o arquivo genesis.json para o diretório raiz do projeto
    echo "Copiando genesis.json para a raiz do projeto..."
    cp networkFiles/genesis.json ./
    echo "genesis.json copiado."

    # 4. Gera o arquivo permissions_config.toml e copia chaves para os nós
    echo "Executando generate-nodes-config.sh para criar permissions_config.toml e copiar chaves..."
    ./generate-nodes-config.sh
    echo "permissions_config.toml gerado e chaves copiadas para os nós."

    # Adiciona a conta externa ao accounts-allowlist no permissions_config.toml
    # O permissions_config.toml é gerado em BASE_DIR/Permissioned-Network/
    PERMISSIONS_CONFIG_PATH="${BASE_DIR}/Permissioned-Network/permissions_config.toml"
    if [ -f "$PERMISSIONS_CONFIG_PATH" ]; then
        echo "Adicionando conta externa (${EXTERNAL_DEPLOY_ACCOUNT}) ao permissions_config.toml..."
        # Substitui o último ']' na linha accounts-allowlist por ', "NOVA_CONTA"]'
        # Isso permite adicionar a conta mantendo a formatação correta
        sed -i "s/\(accounts-allowlist=\[[^]]*\)\]/\1, \"$EXTERNAL_DEPLOY_ACCOUNT\"]/" "$PERMISSIONS_CONFIG_PATH"
        echo "Conteúdo de accounts-allowlist após a modificação:"
        grep "accounts-allowlist" "$PERMISSIONS_CONFIG_PATH"

        # Re-copia o permissions_config.toml atualizado para todos os nós
        echo "Re-copiando o permissions_config.toml atualizado para todos os diretórios dos nós..."
        for i in $(seq 1 6); do
            cp "$PERMISSIONS_CONFIG_PATH" "${BASE_DIR}/Permissioned-Network/Node-$i/data/"
        done
        echo "permissions_config.toml atualizado e copiado para todos os nós."
    else
        echo "Erro: permissions_config.toml não encontrado em ${PERMISSIONS_CONFIG_PATH}. Não foi possível adicionar a conta externa."
        exit 1
    fi
}

# Função para executar a rede Besu via Docker
execute_network() {
    echo "--- Etapa 2: Execução da Rede ---"

    # 1. Constrói a Imagem Docker do Besu
    echo "Construindo a imagem Docker personalizada do Besu..."
    # Usa o Dockerfile no diretório atual
    sudo docker build --no-cache -f Dockerfile -t besu-image-local:1.0 .
    echo "Imagem Docker 'besu-image-local:1.0' construída."

    # 2. Configura os Bootnodes no docker-compose.yaml
    echo "Iniciando a rede temporariamente para obter os enodes do Node-1 e Node-3..."
    sudo docker-compose up -d
    sleep 30 # Aguarda um tempo para os nós iniciarem e gerarem seus enodes
    echo "Rede temporária iniciada. Coletando enodes..."

    echo "Executando update_docker_compose.py para configurar bootnodes no docker-compose.yaml..."
    # Executa o script Python para atualizar o docker-compose.yaml
    python3 update_docker_compose.py
    echo "docker-compose.yaml atualizado com os bootnodes."

    echo "Derrubando a rede temporária para aplicar as novas configurações de bootnodes..."
    sudo docker-compose down
    echo "Rede temporária derrubada."

    # 3. Inicializa a Rede Corretamente com os bootnodes configurados
    echo "Inicializando a rede Besu corretamente com os bootnodes..."
    sudo docker-compose up -d
    sleep 60 # Aguarda a rede subir completamente e os nós se conectarem
    echo "Rede Besu inicializada com sucesso."
}

# Função para validar o estado da rede
validate_network() {
    echo "--- Etapa 3: Validação do Estado da Rede ---"

    echo "Verificando a contagem de pares (o resultado esperado é \"0x5\" para 5 pares conectados ao Node-1):"
    # net_peerCount retorna o número de peers conectados
    curl -X POST --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' http://127.0.0.1:8545 | jq

    echo "Verificando se os blocos estão sendo produzidos (o número do bloco deve aumentar a cada execução):"
    # eth_blockNumber retorna o número do bloco atual
    curl -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://127.0.0.1:8545 | jq
    sleep 5 # Espera um pouco para verificar novamente
    curl -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://127.0.0.1:8545 | jq
}

# --- Função Principal ---
main() {
    cleanup               # Inicia limpando qualquer configuração anterior
    install_dependencies  # Instala e configura Besu e Java
    generate_keys_and_configs # Gera chaves e arquivos de permissão
    execute_network       # Inicia a rede Docker e configura bootnodes
    validate_network      # Valida se a rede está funcional

    echo ""
    echo "----------------------------------------------------------------------"
    echo "Configuração e Execução da Rede Besu Permissionada Concluídas com Sucesso!"
    echo "----------------------------------------------------------------------"
    echo "Lembre-se que a conta de implantação externa: ${EXTERNAL_DEPLOY_ACCOUNT} já foi adicionada à lista de permissões."
    echo "Você pode interagir com a rede Besu via RPC HTTP em http://127.0.0.1:8545 (para o Node-1) ou outras portas (8546-8550 para os outros nós)."
    echo ""
}

# Executa a função principal
main "$@"
