#!/bin/bash

# --- CONFIGURAÇÕES ---
JMETER_VERSION="5.6.3"
JMETER_DIR="apache-jmeter-${JMETER_VERSION}"
JMETER_URL="https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz"
CONTRACT_ADDRESS_FILE="contract_address.txt"
API_HOST="10.126.1.232" # IP da VM onde a API está a correr

# --- CONFIGURAÇÃO DA EXECUÇÃO ---
# Argumento 1: Número de usuários (5, 10, 25, 50). Padrão: 5.
NUM_USERS=${1:-5}
# Argumento 2: Número de repetições do teste. Padrão: 1.
NUM_REPETITIONS=${2:-1} # Corrigido para usar o segundo argumento

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

# MODIFICAÇÃO: Usamos valores fixos para as transações, idênticos ao Caliper.
# O script de geração de gráficos agora calcula a média, então não precisamos mais multiplicar.
NUMBER_OF_ACCOUNTS=1000 # Fixo, igual ao txNumber do Caliper para open/query
TRANSFER_TX_NUMBER=50  # Fixo, igual ao txNumber do Caliper para transfer

# Configurações para o Java
JAVA_DIR_NAME="jdk-21.0.7"
JAVA_TAR_GZ="jdk-21.0.7_linux-x64_bin.tar.gz"
JAVA_URL="https://download.oracle.com/java/21/archive/${JAVA_TAR_GZ}"
export JAVA_HOME="$(pwd)/../${JAVA_DIR_NAME}"

# Caminhos para os planos de teste (JMX)
JMX_DIR="${NUM_USERS}_Users/Jmeter"
JMX_OPEN="${JMX_DIR}/test_round1_open.jmx"
JMX_QUERY="${JMX_DIR}/test_round2_query.jmx"
JMX_TRANSFER="${JMX_DIR}/test_round3_transfer.jmx"

# Diretório para os resultados
TESTE_DIR="$(pwd)"
JMETER_RUNS_DIR="$TESTE_DIR/jmeter_runs_${NUM_USERS}_users"

# Limpa execuções anteriores
rm -rf "$JMETER_RUNS_DIR"
mkdir -p "$JMETER_RUNS_DIR"

# (As funções check_and_install_java, generate_caliper_style_accounts_csv, parse_jtl_for_html, e generate_html_report permanecem as mesmas da sua versão anterior)
# ... (código das funções omitido por brevidade) ...

# --- INSTALAÇÃO AUTOMÁTICA DO JMETER ---
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

# --- LÓGICA PRINCIPAL ---
if [ ! -s "$CONTRACT_ADDRESS_FILE" ]; then
    echo "Erro: Arquivo '$CONTRACT_ADDRESS_FILE' não encontrado ou vazio."
    exit 1
fi
CONTRACT_ADDRESS=$(<"$CONTRACT_ADDRESS_FILE")

generate_caliper_style_accounts_csv

# --- EXECUÇÃO EM LOOP ---
for (( i=1; i<=$NUM_REPETITIONS; i++ ))
do
    echo -e "\n--- Iniciando Execução JMeter #$i de $NUM_REPETITIONS ---"

    # MODIFICAÇÃO: A função agora passa a propriedade '-Jaction' para o JMeter
    run_test_and_monitor() {
        local JMX_FILE=$1
        local ROUND_NAME=$2
        local ACTION_NAME=$3 # Novo parâmetro para a ação (open, transfer)
        local RUN_NUMBER=$4
        local CSV_FILE_PATH=$5
        local EXPECTED_SAMPLES=$6

        local JTL_FILE="$JMETER_RUNS_DIR/results_${ROUND_NAME,,}_run_${RUN_NUMBER}.jtl"
        local DOCKER_STATS_LOG_PATH="$JMETER_RUNS_DIR/docker_stats_${ROUND_NAME,,}_run_${RUN_NUMBER}.log"

        echo -e "\n--- Executando Round: $ROUND_NAME (Ação: $ACTION_NAME, Execução #${RUN_NUMBER}) ---"

        # Inicia o monitoramento
        curl -s -X POST -H "Content-Type: application/json" \
            -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": \"${RUN_NUMBER}\"}" \
            "http://${API_HOST}:3000/monitor/start"

        echo "Usando arquivo de dados: $CSV_FILE_PATH"
        
        # Comando JMeter atualizado para incluir -Jaction
        "$JMETER_HOME/jmeter" -n -t "$JMX_FILE" -l "$JTL_FILE" \
            -JcontractAddress="$CONTRACT_ADDRESS" \
            -JcsvDataFile="$CSV_FILE_PATH" \
            -JapiHost="$API_HOST" \
            -Jaction="$ACTION_NAME" # Passa a ação para o script Groovy

        # (O restante da lógica de espera e parada do monitoramento permanece o mesmo)
        # ...
        
        echo "Parando monitoramento remoto na API..."
        curl -s -X POST -H "Content-Type: application/json" \
            -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": \"${RUN_NUMBER}\"}" \
            "http://${API_HOST}:3000/monitor/stop"

        echo "A descarregar o ficheiro de log de monitoramento..."
        curl -s -o "$DOCKER_STATS_LOG_PATH" "http://${API_HOST}:3000/monitor/logs/${ROUND_NAME}/${RUN_NUMBER}"
    }

    # MODIFICAÇÃO: As chamadas agora passam o nome da ação e usam os totais fixos.
    run_test_and_monitor "$JMX_OPEN" "Open" "open" "$i" "$JMETER_RUNS_DIR/open_accounts.csv" "$NUMBER_OF_ACCOUNTS"
    run_test_and_monitor "$JMX_QUERY" "Query" "query" "$i" "$JMETER_RUNS_DIR/open_accounts.csv" "$NUMBER_OF_ACCOUNTS"
    run_test_and_monitor "$JMX_TRANSFER" "Transfer" "transfer" "$i" "$JMETER_RUNS_DIR/transfer_accounts.csv" "$TRANSFER_TX_NUMBER"

    generate_html_report "$i"
done

python3 generateGraphs.py "$JMETER_RUNS_DIR"

echo -e "\nExecução do JMeter concluída!"