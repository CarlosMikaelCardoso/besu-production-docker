#!/bin/bash

# --- CONFIGURAÇÕES ---
JMETER_VERSION="5.6.3"
JMETER_DIR="apache-jmeter-${JMETER_VERSION}"
JMETER_URL="https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz"
CONTRACT_ADDRESS_FILE="contract_address.txt"

# --- PARÂMETROS DE EXECUÇÃO ---
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

BASE_ACCOUNTS=1000
BASE_TRANSFER_TX=50
NUMBER_OF_ACCOUNTS=$((BASE_ACCOUNTS * NUM_REPETITIONS))
TRANSFER_TX_NUMBER=$((BASE_TRANSFER_TX * NUM_REPETITIONS))

# Configurações do Java e Caminhos
JAVA_DIR_NAME="jdk-21.0.7"
JAVA_TAR_GZ="jdk-21.0.7_linux-x64_bin.tar.gz"
JAVA_URL="https://download.oracle.com/java/21/archive/${JAVA_TAR_GZ}"
export JAVA_HOME="$(pwd)/../${JAVA_DIR_NAME}"

JMX_DIR="${NUM_USERS}_Users/Jmeter"
JMX_OPEN="${JMX_DIR}/test_round1_open.jmx"
JMX_QUERY="${JMX_DIR}/test_round2_query.jmx"
JMX_TRANSFER="${JMX_DIR}/test_round3_transfer.jmx"
SCRIPTS_DIR="$(pwd)/scripts"

TESTE_DIR="$(pwd)"
JMETER_RUNS_DIR="$TESTE_DIR/jmeter_runs_${NUM_USERS}_users"

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
    echo "Gerando arquivos CSV de contas no estilo Caliper..."
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

install_jmeter_js_engine() {
    echo "--- Verificando motor JavaScript para JMeter (GraalJS) ---"
    local JMETER_LIB_DIR="${JMETER_DIR}/lib"
    local JS_ENGINE_JAR="${JMETER_LIB_DIR}/js-22.3.1.jar"

    if [ ! -f "$JS_ENGINE_JAR" ]; then
        echo "Motor Graal.js não encontrado. Baixando dependências para ${JMETER_LIB_DIR}..."
        mkdir -p "$JMETER_LIB_DIR"

        local JARS=(
            "https://repo1.maven.org/maven2/org/graalvm/js/js/22.3.1/js-22.3.1.jar"
            "https://repo1.maven.org/maven2/org/graalvm/js/js-scriptengine/22.3.1/js-scriptengine-22.3.1.jar"
            "https://repo1.maven.org/maven2/org/graalvm/truffle/truffle-api/22.3.1/truffle-api-22.3.1.jar"
            "https://repo1.maven.org/maven2/org/graalvm/sdk/graal-sdk/22.3.1/graal-sdk-22.3.1.jar"
            "https://repo1.maven.org/maven2/com/ibm/icu/icu4j/72.1/icu4j-72.1.jar"
        )

        for jar_url in "${JARS[@]}"; do
            local jar_file_name=$(basename "$jar_url")
            echo "Baixando ${jar_file_name}..."
            wget -q --show-progress -O "${JMETER_LIB_DIR}/${jar_file_name}" "${jar_url}"
        done
        echo "Motor Graal.js e dependências instalados com sucesso."
    else
        echo "Motor Graal.js já está instalado."
    fi
}

run_direct_test() {
    local JMX_FILE=$1
    local ROUND_NAME=$2
    local RUN_NUMBER=$3
    local CSV_FILE_PATH=$4

    local JTL_FILE="$JMETER_RUNS_DIR/results_${ROUND_NAME,,}_run_${RUN_NUMBER}.jtl"
    echo -e "\n--- Executando Round Direto: $ROUND_NAME (Execução #${RUN_NUMBER}) ---"

    # MODIFICAÇÃO FINAL E DEFINITIVA:
    # Ativa o modo de compatibilidade com Node.js no GraalJS.
    # Isto ativa o 'require' e permite o acesso ao sistema de ficheiros necessário.
    export JVM_ARGS="-Dpolyglot.js.nodejs-compat=true"
    
    "$JMETER_HOME/jmeter" -n -t "$JMX_FILE" -l "$JTL_FILE" \
        -JcsvDataFile="$CSV_FILE_PATH" \
        -JSCRIPTS_DIR="$SCRIPTS_DIR" \
        -JDEPLOYER_PRIVATE_KEY="8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63" \
        -JCONTRACT_ADDRESS="$CONTRACT_ADDRESS" \
        -JBESU_RPC_URL="http://10.126.1.249:8545"
}


# --- LÓGICA PRINCIPAL ---

echo "Limpando execuções anteriores e criando diretório de resultados..."
rm -rf "$JMETER_RUNS_DIR"
mkdir -p "$JMETER_RUNS_DIR"

if [ ! -d "$JMETER_DIR" ]; then
    echo "Baixando e instalando o JMeter ${JMETER_VERSION}..."
    wget -q --show-progress "$JMETER_URL"
    tar -xzf "apache-jmeter-${JMETER_VERSION}.tgz"
    rm "apache-jmeter-${JMETER_VERSION}.tgz"
else
    echo "JMeter já está instalado."
fi
export JMETER_HOME="$(pwd)/${JMETER_DIR}/bin"

install_jmeter_js_engine
check_and_install_java

if [ ! -s "$CONTRACT_ADDRESS_FILE" ]; then
    echo "Erro: Arquivo '$CONTRACT_ADDRESS_FILE' não encontrado ou vazio. Execute o deploy do contrato primeiro."
    exit 1
fi
CONTRACT_ADDRESS=$(<"$CONTRACT_ADDRESS_FILE")

generate_caliper_style_accounts_csv

for (( i=1; i<=$NUM_REPETITIONS; i++ ))
do
    echo -e "\n--- Iniciando Execução JMeter Direta #${i} de ${NUM_REPETITIONS} ---"
    run_direct_test "$JMX_OPEN" "Open" "$i" "$JMETER_RUNS_DIR/open_accounts.csv"
    run_direct_test "$JMX_QUERY" "Query" "$i" "$JMETER_RUNS_DIR/open_accounts.csv"
    run_direct_test "$JMX_TRANSFER" "Transfer" "$i" "$JMETER_RUNS_DIR/transfer_accounts.csv"
done

echo -e "\n--- Gerando gráficos consolidados dos resultados do JMeter... ---"
python3 generateGraphs.py "$JMETER_RUNS_DIR"

echo -e "\nExecução do JMeter concluída com sucesso!"
echo "Verifique os relatórios e gráficos gerados no diretório: $JMETER_RUNS_DIR/"