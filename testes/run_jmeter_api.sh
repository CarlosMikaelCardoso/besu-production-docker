#!/bin/bash

# --- CONFIGURAÇÕES ---
JMETER_VERSION="5.6.3"
JMETER_DIR="apache-jmeter-${JMETER_VERSION}"
JMETER_URL="https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz"
CONTRACT_ADDRESS_FILE="contract_address.txt"
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
NUMBER_OF_ACCOUNTS=$((BASE_ACCOUNTS * NUM_REPETITIONS))
TRANSFER_TX_NUMBER=$((BASE_TRANSFER_TX * NUM_REPETITIONS))

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
    echo "Gerando arquivos CSV de contas..."
    local accounts_file="$JMETER_RUNS_DIR/all_accounts.txt"
    local open_csv="$JMETER_RUNS_DIR/open_accounts.csv"
    local transfer_csv="$JMETER_RUNS_DIR/transfer_accounts.csv"
    node -e "
        const DICTIONARY = 'abcdefghijklmnopqrstuvwxyz';
        function get26Num(n) { let result = ''; while(n >= 0) { result = DICTIONARY.charAt(n % DICTIONARY.length) + result; n = Math.floor(n / DICTIONARY.length) - 1; } return result; }
        const fs = require('fs');
        const accounts = [];
        for (let i = 0; i < ${NUMBER_OF_ACCOUNTS}; i++) { accounts.push('userJmeter' + get26Num(i)); }
        fs.writeFileSync('${open_csv}', 'accountId\n' + accounts.join('\n'));
        fs.writeFileSync('${accounts_file}', accounts.join('\n'));
        console.log('${NUMBER_OF_ACCOUNTS} contas geradas para os testes open e query.');
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

run_test_and_monitor() {
    local JMX_FILE=$1
    local ROUND_NAME=$2
    local RUN_NUMBER=$3
    local CSV_FILE_PATH=$4
    local EXPECTED_SAMPLES=$5

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

    echo "A aguardar a finalização da escrita dos logs do JMeter..."
    local start_time=$(date +%s)
    local expected_lines=$((EXPECTED_SAMPLES + 1))

    while true; do
        if [ -f "$JTL_FILE" ] && [ $(wc -l < "$JTL_FILE") -ge $expected_lines ]; then
            echo "Ficheiro JTL completo encontrado."
            break
        fi
        local current_time=$(date +%s)
        if [ $((current_time - start_time)) -gt 30 ]; then
            echo "Aviso: Timeout à espera do ficheiro JTL. O relatório pode estar incompleto."
            break
        fi
        sleep 1
    done

    echo "Parando monitoramento remoto na API..."
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": \"${RUN_NUMBER}\"}" \
        http://${API_HOST}:3000/monitor/stop

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

# Execução em Loop
for (( i=1; i<=$NUM_REPETITIONS; i++ ))
do
    echo -e "\n--- Iniciando Execução JMeter #$i de $NUM_REPETITIONS ---"
    
    run_test_and_monitor "$JMX_OPEN" "Open" "$i" "$JMETER_RUNS_DIR/open_accounts.csv" "$NUMBER_OF_ACCOUNTS"
    run_test_and_monitor "$JMX_QUERY" "Query" "$i" "$JMETER_RUNS_DIR/open_accounts.csv" "$NUMBER_OF_ACCOUNTS"
    run_test_and_monitor "$JMX_TRANSFER" "Transfer" "$i" "$JMETER_RUNS_DIR/transfer_accounts.csv" "$TRANSFER_TX_NUMBER"

    # A geração de relatórios HTML e gráficos foi movida para fora do loop
done

echo -e "\n--- Gerando gráficos e relatórios consolidados de todas as execuções... ---"
python3 generateGraphs.py "$JMETER_RUNS_DIR"
# Se ainda quiser relatórios HTML individuais por execução, pode chamar a função generate_html_report aqui dentro do loop.

echo -e "\nExecução do JMeter concluída!"
echo "Verifique os relatórios e gráficos gerados no diretório: $JMETER_RUNS_DIR/"

