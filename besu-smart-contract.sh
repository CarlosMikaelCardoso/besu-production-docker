#!/usr/bin/env bash
set -o errexit   # Aborta a execução se um comando falhar
set -o nounset   # Aborta a execução se uma variável não definida for usada
set -o pipefail  # Aborta se algum comando em um pipeline falhar
# set -x           # Modo de depuração: imprime cada comando antes de executá-lo

# --- Variáveis de Configuração ---
# O diretório base do projeto (onde este script e a pasta 'meu-contrato' estão)
BASE_DIR="$(pwd)"
# O diretório onde está o projeto Hardhat do contrato
CONTRACT_DIR="${BASE_DIR}/meu-contrato"
INTERACT_SCRIPT="${CONTRACT_DIR}/scripts/interact.js"

# --- Função Principal ---
main() {
    echo "--- Iniciando a implantação do Smart Contract 'SimpleStorage' ---"
    
    # Verifica se o diretório do contrato existe
    if [ ! -d "$CONTRACT_DIR" ]; then
        echo "Erro: O diretório do contrato não foi encontrado em ${CONTRACT_DIR}"
        echo "Certifique-se de que a pasta 'meu-contrato' está localizada em: ${BASE_DIR}"
        exit 1
    fi

    # Navegar para o diretório do contrato
    echo "Navegando para o diretório: ${CONTRACT_DIR}"
    cd "${CONTRACT_DIR}"

    # 1. Instalar dependências do Node.js
    echo "Instalando dependências do Node.js (npm install)..."
    npm install
    echo "Dependências Node.js instaladas."

    # 2. Compilar o contrato
    echo "Compilando o contrato 'SimpleStorage'..."
    npx hardhat compile
    echo "Contrato compilado com sucesso."

    # 3. Implantar o contrato na rede Besu
    echo "Implantando o contrato 'SimpleStorage' na rede Besu..."
    echo "Certifique-se de que a rede Besu esteja em execução e acessível em http://127.0.0.1:8545 antes de executar esta etapa."
    npx hardhat run scripts/deploy.js --network besu | tee deploy_output.txt
    echo "Comando de implantação Hardhat executado."

    # Extrair o endereço do contrato implantado da saída
    CONTRACT_ADDRESS=$(grep "Contrato SimpleStorage implantado no endereço:" deploy_output.txt | awk '{print $NF}')
    # Remove o arquivo de saída temporário
    rm deploy_output.txt 

    if [ -n "$CONTRACT_ADDRESS" ]; then
        echo "Endereço do Contrato 'SimpleStorage' Implantado: $CONTRACT_ADDRESS"
        echo "--- Atualizando scripts/interact.js com o endereço do contrato ---"
        
        # Verifica se o arquivo interact.js existe antes de tentar modificá-lo
        if [ -f "$INTERACT_SCRIPT" ]; then
            # Usa sed para substituir o endereço hardcoded pelo endereço do contrato implantado.
            # O '#' é usado como delimitador para o 'sed' para evitar conflitos com barras '/' caso o endereço contenha.
            sed -i "s#const CONTRACT_ADDRESS = \".*\"#const CONTRACT_ADDRESS = \"${CONTRACT_ADDRESS}\"#g" "$INTERACT_SCRIPT"
            echo "scripts/interact.js atualizado com o novo endereço do contrato: ${CONTRACT_ADDRESS}"
        else
            echo "Aviso: O arquivo ${INTERACT_SCRIPT} não foi encontrado."
            echo "Não foi possível atualizar automaticamente a variável CONTRACT_ADDRESS."
            echo "Por favor, crie o arquivo e defina a variável manualmente."
        fi
    else
        echo "Aviso: Não foi possível extrair automaticamente o endereço do contrato da saída da implantação."
        echo "Por favor, verifique a saída acima para o endereço do contrato e atualize 'scripts/interact.js' manualmente."
    fi

    echo "--- Implantação do Smart Contract Concluída ---"
    echo ""
    echo "Próximos Passos para Interação:"
    echo "1. O arquivo 'scripts/interact.js' já foi atualizado com o endereço do contrato."
    echo "2. Para executar as interações (ler e escrever dados) definidas no script, execute o seguinte comando no terminal (ainda no diretório 'meu-contrato'):"
    echo "   npx hardhat run scripts/interact.js --network besu"
    echo ""

    # Retorna ao diretório original onde o script foi iniciado
    cd "${BASE_DIR}"
}

# Executa a função principal
main "$@"
