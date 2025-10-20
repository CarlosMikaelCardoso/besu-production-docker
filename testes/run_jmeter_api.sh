#!/bin/bash

# --- CONFIGURAÇÕES ---
JMETER_VERSION="5.6.3"
JMETER_DIR="apache-jmeter-${JMETER_VERSION}"
JMETER_URL="https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz"
CONTRACT_ADDRESS_FILE="./contract_address.txt"
API_HOST=$(hostname -I | awk '{print $1}') # IP da VM onde a API está a correr

# Parâmetros de execução
NUM_USERS=${1:-5}
NUM_REPETITIONS=${2:-1}

# Validação do número de usuários
case $NUM_USERS in
    5|10|25|50)
        echo "Número de usuários selecionado: $NUM_USERS"
        ;;
    *)
        echo "Erro: Número de usuários inválido. Escolha entre 5, 10, 25, ou 50."
        exit 1
        ;;
esac

# Cálculo dinâmico de transações
BASE_ACCOUNTS=1000
BASE_TRANSFER_TX=50
# MODIFICAÇÃO: Ajustado para refletir o número de loops no JMX, não repetições do script.
# O número total de amostras será (num_threads * loops)
if [ "$NUM_USERS" -eq 5 ]; then
    OPEN_LOOPS=200; QUERY_LOOPS=200; TRANSFER_LOOPS=10;
elif [ "$NUM_USERS" -eq 10 ]; then
    OPEN_LOOPS=100; QUERY_LOOPS=100; TRANSFER_LOOPS=5;
elif [ "$NUM_USERS" -eq 25 ]; then
    OPEN_LOOPS=40; QUERY_LOOPS=40; TRANSFER_LOOPS=2;
elif [ "$NUM_USERS" -eq 50 ]; then
    OPEN_LOOPS=20; QUERY_LOOPS=20; TRANSFER_LOOPS=1;
fi
NUMBER_OF_ACCOUNTS=$((NUM_USERS * OPEN_LOOPS))
TRANSFER_TX_NUMBER=$((NUM_USERS * TRANSFER_LOOPS))

# Configurações do Java
JAVA_DIR_NAME="jdk-21.0.7"
JAVA_TAR_GZ="jdk-21.0.7_linux-x64_bin.tar.gz"
JAVA_URL="https://download.oracle.com/java/21/archive/${JAVA_TAR_GZ}"
export JAVA_HOME="$(pwd)/../${JAVA_DIR_NAME}"

# Caminhos para os planos de teste (JMX)
JMX_DIR="${NUM_USERS}_Users/Jmeter"
JMX_OPEN="${JMX_DIR}/test_round1_open.jmx"
JMX_QUERY="${JMX_DIR}/test_round2_query.jmx"
JMX_TRANSFER="${JMX_DIR}/test_round3_transfer.jmx"

# Diretório de resultados
TESTE_DIR="$(pwd)"
JMETER_RUNS_DIR="$TESTE_DIR/jmeter_runs_${NUM_USERS}_users"

# --- FUNÇÕES AUXILIARES ---

check_and_install_java() {
    echo "--- Verificando instalação do Java ---"
    if [ ! -d "$JAVA_HOME" ] || [ ! -f "${JAVA_HOME}/bin/java" ]; then
        echo "Java não encontrado. Baixando e instalando JDK ${JAVA_DIR_NAME}..."
        if ! command -v wget &> /dev/null; then echo "Erro: 'wget' não está instalado."; exit 1; fi
        wget -q --show-progress -O "${JAVA_TAR_GZ}" "${JAVA_URL}"
        if [ $? -ne 0 ]; then echo "Erro: Falha ao baixar o Java."; exit 1; fi
        tar -xzf "${JAVA_TAR_GZ}" -C "$(dirname "$JAVA_HOME")"
        rm "${JAVA_TAR_GZ}"
        echo "Java ${JAVA_DIR_NAME} instalado com sucesso."
    else
        echo "Java já está instalado em ${JAVA_HOME}"
    fi
    export PATH="${JAVA_HOME}/bin:$PATH"
}

generate_caliper_style_accounts_csv() {
    echo "Gerando arquivos CSV de contas (um por thread)..."
    local accounts_file="$JMETER_RUNS_DIR/all_accounts.txt"
    local open_csv_prefix="$JMETER_RUNS_DIR/open_accounts_thread_"
    local open_csv="$JMETER_RUNS_DIR/open_accounts.csv"
    local transfer_csv="$JMETER_RUNS_DIR/transfer_accounts.csv"
    
    # Apaga contas antigas para garantir que não haja lixo de execuções anteriores
    rm -f "${open_csv_prefix}"*
    rm -f "$accounts_file"

    local accounts_per_thread=$((NUMBER_OF_ACCOUNTS / NUM_USERS))

    node -e "
        const DICTIONARY = 'abcdefghijklmnopqrstuvwxyz';
        function get26Num(n) { let result = ''; while(n >= 0) { result = DICTIONARY.charAt(n % DICTIONARY.length) + result; n = Math.floor(n / DICTIONARY.length) - 1; } return result; }
        const fs = require('fs');
        
        let total_accounts = [];
        let account_index = 0;

        for (let threadNum = 1; threadNum <= ${NUM_USERS}; threadNum++) {
            const thread_accounts = [];
            for (let i = 0; i < ${accounts_per_thread}; i++) {
                const accountName = 'userJmeter' + get26Num(account_index++);
                thread_accounts.push(accountName);
                total_accounts.push(accountName);
            }
            // Gera um CSV para cada thread
            fs.writeFileSync(\`${open_csv_prefix}\${threadNum}.csv\`, 'accountId\n' + thread_accounts.join('\n'));
        }

                // Mantém um arquivo com todas as contas para a lógica de transferência
        fs.writeFileSync('${accounts_file}', total_accounts.join('\n'));
        console.log('${NUMBER_OF_ACCOUNTS} contas geradas e divididas em ${NUM_USERS} arquivos.');

        const accounts = [];
        for (let i = 0; i < ${NUMBER_OF_ACCOUNTS}; i++) { accounts.push('userJmeter' + get26Num(i)); }
        fs.writeFileSync('${open_csv}', 'accountId\n' + accounts.join('\n'));
        fs.writeFileSync('${accounts_file}', accounts.join('\n'));
        console.log('${NUMBER_OF_ACCOUNTS} contas geradas para os testes open');
    "
    if [ $? -ne 0 ]; then echo "Erro: Falha ao gerar contas com Node.js."; exit 1; fi

    echo "source_account,target_account" > "$transfer_csv"
    for ((i=0; i<$TRANSFER_TX_NUMBER; i++)); do
        source_acc=$(shuf -n 1 "$accounts_file")
        target_acc=$(shuf -n 1 "$accounts_file")
        while [[ "$source_acc" == "$target_acc" ]]; do
            target_acc=$(shuf -n 1 "$accounts_file")
        done
        echo "$source_acc,$target_acc" >> "$transfer_csv"
    done
    echo "${TRANSFER_TX_NUMBER} pares de transferência gerados."
}

wait_for_queue_and_check_errors() {
    local round_name=$1
    local run_number=$2
    local error_log_file="$JMETER_RUNS_DIR/backend_errors.log"

    echo "--- Sincronizando: Aguardando a finalização do processamento da API para a rodada '$round_name' ---"
    
    while true; do
        # Tenta obter o status da API. O '-f' falha silenciosamente em erros de HTTP (ex: 404, 500)
        status_output=$(curl -s -f http://${API_HOST}:3000/queue/status)
        
        # Verifica se o curl teve sucesso e se a resposta é um JSON válido
        if [ $? -eq 0 ] && echo "$status_output" | jq -e . > /dev/null 2>&1; then
            if echo "$status_output" | jq -e '.isIdle == true'; then
                echo "API finalizou o processamento da fila."
                break
            fi
        fi
        
        echo -n "."
        sleep 2
    done

    echo "Verificando se ocorreram erros assíncronos no servidor..."
    errors_output=$(curl -s http://${API_HOST}:3000/errors/get)
    
    # Verifica se a resposta de erros é um JSON válido antes de tentar processar
    if echo "$errors_output" | jq -e . > /dev/null 2>&1; then
        error_count=$(echo "$errors_output" | jq '.errors | length')
        
        if [ "$error_count" -gt 0 ]; then
            echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            echo "AVISO: Foram detectados $error_count erros de processamento no back-end!"
            echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            # Grava a contagem de erros para o script de gráficos usar
            echo "$round_name,$run_number,$error_count,$(echo "$errors_output" | jq -c .)" >> "$error_log_file"
        else
            echo "Nenhum erro de processamento assíncrono encontrado."
        fi
    else
        echo "Aviso: Não foi possível obter uma resposta JSON válida do endpoint de erros."
    fi

    # Limpa sempre os erros na API para a próxima rodada
    curl -s -X POST http://${API_HOST}:3000/errors/clear > /dev/null
}

run_test_and_monitor() {
    local JMX_FILE=$1
    local ROUND_NAME=$2
    local RUN_NUMBER=$3
    local CSV_FILE_PATH=$4
    local IS_WRITE_OPERATION=$5 # Novo parâmetro para saber se é 'open' ou 'transfer'

    local JTL_FILE="$JMETER_RUNS_DIR/results_${ROUND_NAME,,}_run_${RUN_NUMBER}.jtl"
    local DOCKER_STATS_LOG_PATH="$JMETER_RUNS_DIR/docker_stats_${ROUND_NAME,,}_run_${RUN_NUMBER}.log"

    echo -e "\n--- Executando Round: $ROUND_NAME (Execução #${RUN_NUMBER}) ---"

    echo "Iniciando monitoramento remoto na API..."
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": \"${RUN_NUMBER}\"}" \
        http://${API_HOST}:3000/monitor/start

    echo "Usando arquivo de dados: $CSV_FILE_PATH"
    "$JMETER_HOME/jmeter" -n -t "$JMX_FILE" -l "$JTL_FILE" \
        -JcsvDataFile="$CSV_FILE_PATH" \
        -JapiHost="$API_HOST"

    echo "Parando monitoramento remoto na API..."
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": \"${RUN_NUMBER}\"}" \
        http://${API_HOST}:3000/monitor/stop

    # *** AQUI ESTÁ A LÓGICA DE SINCRONIZAÇÃO ***
    if [ "$IS_WRITE_OPERATION" = true ]; then
        wait_for_queue_and_check_errors "$ROUND_NAME" "$RUN_NUMBER"
    fi

    echo "A descarregar o ficheiro de log de monitoramento..."
    curl -s -o "$DOCKER_STATS_LOG_PATH" "http://${API_HOST}:3000/monitor/logs/${ROUND_NAME}/${RUN_NUMBER}"
}

# --- LÓGICA PRINCIPAL ---

echo "Limpando execuções anteriores e criando diretório de resultados..."
rm -rf "$JMETER_RUNS_DIR"
mkdir -p "$JMETER_RUNS_DIR"

# Instalação do JMeter
if [ ! -d "$JMETER_DIR" ]; then
    echo "Baixando e instalando o JMeter ${JMETER_VERSION}..."
    if ! command -v wget &> /dev/null; then echo "Erro: 'wget' não está instalado."; exit 1; fi
    wget -q --show-progress "$JMETER_URL"
    tar -xzf "apache-jmeter-${JMETER_VERSION}.tgz"
    rm "apache-jmeter-${JMETER_VERSION}.tgz"
else
    echo "JMeter já está instalado."
fi
export JMETER_HOME="$(pwd)/${JMETER_DIR}/bin"

check_and_install_java

if [ ! -s "$CONTRACT_ADDRESS_FILE" ]; then
    echo "Erro: Arquivo '$CONTRACT_ADDRESS_FILE' não encontrado ou vazio. Execute o deploy do contrato primeiro."
    exit 1
fi
CONTRACT_ADDRESS=$(<"$CONTRACT_ADDRESS_FILE")

generate_caliper_style_accounts_csv

# Limpa qualquer erro antigo na API antes de começar
curl -s -X POST http://${API_HOST}:3000/errors/clear > /dev/null

# Execução em Loop
for (( i=1; i<=$NUM_REPETITIONS; i++ ))
do
    echo -e "\n--- Iniciando Execução JMeter #$i de $NUM_REPETITIONS ---"
    
    # run_test_and_monitor <jmx_file> <round_name> <run_number> <csv_file> <is_write_operation>
    run_test_and_monitor "$JMX_OPEN" "Open" "$i" "$JMETER_RUNS_DIR/open_accounts.csv" true
    run_test_and_monitor "$JMX_QUERY" "Query" "$i" "$JMETER_RUNS_DIR/open_accounts_thread_" false
    run_test_and_monitor "$JMX_TRANSFER" "Transfer" "$i" "$JMETER_RUNS_DIR/transfer_accounts.csv" true

done

echo -e "\n--- Gerando gráficos e relatórios consolidados de todas as execuções... ---"
python3 generateGraphs.py "$JMETER_RUNS_DIR"

echo -e "\nExecução do JMeter concluída!"
echo "Verifique os relatórios e gráficos gerados no diretório: $JMETER_RUNS_DIR/"