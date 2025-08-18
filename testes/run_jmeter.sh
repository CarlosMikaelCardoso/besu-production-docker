#!/bin/bash

# --- CONFIGURAÇÕES ---
JMETER_VERSION="5.6.3"
JMETER_DIR="apache-jmeter-${JMETER_VERSION}"
JMETER_URL="https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz"
API_HOST="10.126.1.249" # IP da VM onde a API está a correr

# --- CONFIGURAÇÃO DA EXECUÇÃO ---
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

# Configurações para o Java (assumindo que está na pasta anterior)
JAVA_DIR_NAME="jdk-21.0.7"
export JAVA_HOME="$(pwd)/../${JAVA_DIR_NAME}"

# Caminhos para os planos de teste (JMX)
JMX_DIR="test_plans" # MODIFICAÇÃO: Aponta para a pasta organizada
JMX_OPEN="${JMX_DIR}/test_round1_open.jmx"
JMX_QUERY="${JMX_DIR}/test_round2_query.jmx"
JMX_TRANSFER="${JMX_DIR}/test_round3_transfer.jmx"

# Diretório para os resultados e dados
TEST_DIR="$(pwd)"
REPORTS_DIR="$TEST_DIR/reports"
DATA_DIR="$TEST_DIR/data"
GENERATED_ACCOUNTS_FILE="$DATA_DIR/generated_accounts.csv"

# --- FUNÇÕES AUXILIARES ---

check_and_install_java() {
    # (Presumi que a sua função para instalar o Java está aqui e funciona)
    if [ ! -d "$JAVA_HOME" ]; then
        echo "Instalando Java..."
        # Adicione aqui a sua lógica de download e extração do Java
    fi
    export PATH=$JAVA_HOME/bin:$PATH
    echo "Java Home definido para: $JAVA_HOME"
}

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

# --- LÓGICA PRINCIPAL ---

check_and_install_java

# MODIFICAÇÃO: A função foi simplificada.
# Não precisa mais do caminho do CSV nem do número de amostras.
# Apenas o plano de teste, nome da ronda, ação (para query/transfer) e número da execução.
run_test_and_monitor() {
    local JMX_FILE=$1
    local ROUND_NAME=$2
    local ACTION_NAME=$3
    local RUN_NUMBER=$4

    # Define nomes de ficheiros de saída baseados nos parâmetros
    local JTL_FILE="$REPORTS_DIR/results_${ROUND_NAME,,}_run_${RUN_NUMBER}.jtl"
    local DOCKER_STATS_LOG_PATH="$REPORTS_DIR/docker_stats_${ROUND_NAME,,}_run_${RUN_NUMBER}.log"

    echo -e "\n--- Executando Round: $ROUND_NAME (Execução #${RUN_NUMBER}) ---"

    echo "A iniciar monitoramento remoto na API..."
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": \"${RUN_NUMBER}\"}" \
        "http://${API_HOST}:3000/monitor/start"

    echo "A executar plano de teste: $JMX_FILE"
    
    # Comando JMeter simplificado.
    # A flag -Jaction é crucial para os scripts Groovy.
    "$JMETER_HOME/jmeter" -n -t "$JMX_FILE" -l "$JTL_FILE" \
        -JapiHost="$API_HOST" \
        -Jaction="$ACTION_NAME"

    echo "A parar monitoramento remoto na API..."
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": \"${RUN_NUMBER}\"}" \
        "http://${API_HOST}:3000/monitor/stop"

    echo "A descarregar o ficheiro de log de monitoramento..."
    curl -s -o "$DOCKER_STATS_LOG_PATH" "http://${API_HOST}:3000/monitor/logs/${ROUND_NAME}/${RUN_NUMBER}"
    echo "Log de monitoramento salvo em: $DOCKER_STATS_LOG_PATH"
}


# --- EXECUÇÃO EM LOOP ---
for (( i=1; i<=$NUM_REPETITIONS; i++ ))
do
    echo -e "\n======================================================="
    echo "      INICIANDO EXECUÇÃO COMPLETA DO JMETER #${i} de ${NUM_REPETITIONS}"
    echo "======================================================="

    # ADIÇÃO: Limpa o ficheiro de contas geradas antes de cada execução completa.
    # Isto garante que cada teste comece do zero, como no Caliper.
    echo "A limpar ficheiro de contas da execução anterior..."
    rm -f "$GENERATED_ACCOUNTS_FILE"
    touch "$GENERATED_ACCOUNTS_FILE"

    # MODIFICAÇÃO: Chamadas de função simplificadas.
    # A ação "open" é passada, mas não é usada pelo script open_logic.groovy, o que não tem problema.
    run_test_and_monitor "$JMX_OPEN" "Open" "open" "$i"
    run_test_and_monitor "$JMX_QUERY" "Query" "query" "$i"
    run_test_and_monitor "$JMX_TRANSFER" "Transfer" "transfer" "$i"

done

# Gera os gráficos consolidados de todas as execuções no final.
echo -e "\n--- A gerar gráficos consolidados de todas as execuções ---"
python3 generateGraphs.py "$REPORTS_DIR"

echo -e "\nExecução do JMeter concluída!"
echo "Verifique os gráficos e JTLs no diretório: $REPORTS_DIR/"