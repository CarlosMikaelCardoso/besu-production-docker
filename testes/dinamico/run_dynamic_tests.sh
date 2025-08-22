#!/bin/bash

# --- CONFIGURAÇÕES GLOBAIS ---
BASE_DIR=$(pwd)
JMX_DIR="$BASE_DIR/jmeter"
CALIPER_DIR="$BASE_DIR/caliper"
RESULTS_BASE_DIR="$BASE_DIR/results"

# --- CONFIGURAÇÕES A AJUSTAR ---
# IP da VM onde a API está a correr (para testes JMeter)
API_HOST=$(hostname -I | awk '{print $1}')

# Caminho para o ficheiro de configuração da rede Caliper
CALIPER_NETWORKCONFIG="$BASE_DIR/../../meu-contrato/networkconfig.json"

# Caminho para a pasta de benchmarks do Caliper (onde o 'npx caliper' deve ser executado)
CALIPER_BENCHMARKS_DIR="$BASE_DIR/../../caliper-benchmarks"

# --- DEPENDÊNCIAS RECOMENDADAS ---
sudo snap install yq
sudo apt-get install xmlstarlet

# --- FUNÇÕES AUXILIARES ---

check_dependencies() {
    YQ_CMD=$(command -v yq)
    XMLSTARLET_CMD=$(command -v xmlstarlet)

    if [ -z "$YQ_CMD" ]; then
        echo "Aviso: 'yq' não encontrado. A usar 'sed' para modificar o config.yaml (menos seguro)."
    fi
    if [ -z "$XMLSTARLET_CMD" ]; then
        echo "Aviso: 'xmlstarlet' não encontrado. A usar 'sed' para modificar os ficheiros .jmx (menos seguro)."
    fi
}

get_user_input() {
    echo "-------------------------------------"
    read -p "Quantos utilizadores/workers concorrentes? [Padrão: 5]: " NUM_USERS
    NUM_USERS=${NUM_USERS:-5}

    read -p "Qual a taxa de transações por segundo (TPS)? [Padrão: 50]: " TPS_RATE
    TPS_RATE=${TPS_RATE:-50}

    read -p "Quantas vezes repetir o ciclo de testes completo? [Padrão: 1]: " NUM_REPETITIONS
    NUM_REPETITIONS=${NUM_REPETITIONS:-1}
    echo "-------------------------------------"
}

update_caliper_config() {
    local users=$1
    local tps=$2
    local temp_config_file=$3

    echo "A atualizar o config.yaml temporário com: $users workers, $tps TPS..."

    cp "$CALIPER_DIR/config.yaml" "$temp_config_file"

    if [ -n "$YQ_CMD" ]; then
        yq e ".test.workers.number = $users" -i "$temp_config_file"
        yq e ".test.rounds[].rateControl.opts.tps = $tps" -i "$temp_config_file"
    else
        sed -i "s/number: [0-9]\+/number: $users/" "$temp_config_file"
        sed -i "s/tps: [0-9]\+/tps: $tps/" "$temp_config_file"
    fi
}

update_jmeter_config() {
    local users=$1
    local tps=$2
    local results_dir=$3
    
    local throughput_per_minute=$(($tps * 60))
    local tx_open=1000
    local tx_query=1000
    local tx_transfer=50

    echo "A atualizar os ficheiros .jmx temporários com: $users utilizadores, $tps TPS ($throughput_per_minute/min)..."

    for jmx_file in "$JMX_DIR"/*.jmx; do
        local filename=$(basename "$jmx_file")
        local temp_jmx_file="$results_dir/temp_$filename"
        cp "$jmx_file" "$temp_jmx_file"
        
        local total_tx=0
        if [[ "$filename" == *"open"* ]]; then total_tx=$tx_open;
        elif [[ "$filename" == *"query"* ]]; then total_tx=$tx_query;
        elif [[ "$filename" == *"transfer"* ]]; then total_tx=$tx_transfer;
        fi

        local loops_per_user=$((total_tx / users))
        if [ $loops_per_user -eq 0 ]; then loops_per_user=1; fi

        echo "  -> A configurar $filename: Loops por utilizador: $loops_per_user"

        if [ -n "$XMLSTARLET_CMD" ]; then
            xmlstarlet ed -L \
                -u "//ThreadGroup/intProp[@name='ThreadGroup.num_threads']" -v "$users" \
                -u "//LoopController/stringProp[@name='LoopController.loops']" -v "$loops_per_user" \
                -u "//ConstantThroughputTimer/doubleProp/value" -v "$throughput_per_minute.0" \
                "$temp_jmx_file"
        else
            sed -i "s|<intProp name=\"ThreadGroup.num_threads\">[0-9]\+</intProp>|<intProp name=\"ThreadGroup.num_threads\">$users</intProp>|" "$temp_jmx_file"
            sed -i "s|<stringProp name=\"LoopController.loops\">[0-9]\+</stringProp>|<stringProp name=\"LoopController.loops\">$loops_per_user</stringProp>|" "$temp_jmx_file"
            sed -i "s|<value>[0-9]\+\.0</value>|<value>$throughput_per_minute.0</value>|" "$temp_jmx_file"
        fi
    done
}

run_caliper_tests() {
    local run_number=$1
    local results_dir=$2
    local temp_config_file="$results_dir/temp_caliper_config.yaml"

    echo "A iniciar teste do Caliper..."
    update_caliper_config "$NUM_USERS" "$TPS_RATE" "$temp_config_file"
    
    # --- LÓGICA DE EXECUÇÃO DO CALIPER (ADAPTADA) ---
    echo "A executar Caliper a partir de: $CALIPER_BENCHMARKS_DIR"
    (
      cd "$CALIPER_BENCHMARKS_DIR" || exit 1
      npx caliper launch manager \
        --caliper-benchconfig "$temp_config_file" \
        --caliper-networkconfig "$CALIPER_NETWORKCONFIG" \
        --caliper-workspace "$CALIPER_DIR" \
        --caliper-report-path "$results_dir/caliper_report.html"
    )
    # --- FIM DA LÓGICA ---

    echo "Teste do Caliper concluído. Relatório em: $results_dir/caliper_report.html"
}

run_jmeter_tests() {
    local run_number=$1
    local results_dir=$2

    echo "A iniciar teste do JMeter..."
    update_jmeter_config "$NUM_USERS" "$TPS_RATE" "$results_dir"

    # --- LÓGICA DE EXECUÇÃO DO JMETER (ADAPTADA) ---
    local jmeter_executable="$HOME/apache-jmeter-5.6.3/bin/jmeter" # Ajuste o caminho para o seu JMeter

    # Preparar dados de teste (CSV)
    local open_csv="$results_dir/open_accounts.csv"
    local transfer_csv="$results_dir/transfer_accounts.csv"
    node -e "
        const DICTIONARY = 'abcdefghijklmnopqrstuvwxyz';
        function get26Num(n) { let result = ''; while(n >= 0) { result = DICTIONARY.charAt(n % DICTIONARY.length) + result; n = Math.floor(n / DICTIONARY.length) - 1; } return result; }
        const fs = require('fs');
        const accounts = [];
        for (let i = 0; i < 1000; i++) { accounts.push('userDinamico' + get26Num(i)); }
        fs.writeFileSync('${open_csv}', 'accountId\n' + accounts.join('\n'));
        const transferPairs = [];
        for (let i = 0; i < 50; i++) {
            let source = accounts[Math.floor(Math.random() * accounts.length)];
            let target = accounts[Math.floor(Math.random() * accounts.length)];
            while (source === target) { target = accounts[Math.floor(Math.random() * accounts.length)]; }
            transferPairs.push(source + ',' + target);
        }
        fs.writeFileSync('${transfer_csv}', 'source_account,target_account\n' + transferPairs.join('\n'));
    "

    # Executar as rondas
    local rounds=("open" "query" "transfer")
    for round in "${rounds[@]}"; do
        echo -e "\n-- A executar ronda JMeter: $round --"
        local temp_jmx="$results_dir/temp_round${round_number}_${round}.jmx"
        local jtl_file="$results_dir/jmeter_${round}_result.jtl"
        local csv_file="$open_csv"
        if [ "$round" == "transfer" ]; then csv_file="$transfer_csv"; fi

        # A sua API deve estar a correr para isto funcionar
        curl -s -X POST -H "Content-Type: application/json" -d "{\"roundName\": \"${round}\", \"runNumber\": \"${run_number}\"}" http://${API_HOST}:3000/monitor/start

        "$jmeter_executable" -n -t "$temp_jmx" -l "$jtl_file" \
            -JcsvDataFile="$csv_file" \
            -JapiHost="$API_HOST"

        curl -s -X POST -H "Content-Type: application/json" -d "{\"roundName\": \"${round}\", \"runNumber\": \"${run_number}\"}" http://${API_HOST}:3000/monitor/stop
    done
    # --- FIM DA LÓGICA ---

    echo "Teste do JMeter concluído. Resultados em: $results_dir"
}


# --- LÓGICA PRINCIPAL DO MENU ---

check_dependencies

while true; do
    echo ""
    echo "========================================"
    echo "   MENU DE TESTES DINÂMICOS - BESU"
    echo "========================================"
    echo "1. Executar testes com Hyperledger Caliper"
    echo "2. Executar testes com Apache JMeter"
    echo "3. Sair"
    echo "----------------------------------------"
    read -p "Escolha uma opção: " choice

    case $choice in
        1)
            get_user_input
            for (( i=1; i<=$NUM_REPETITIONS; i++ )); do
                echo -e "\n--- A iniciar execução CALIPER #${i} de ${NUM_REPETITIONS} ---"
                run_results_dir="$RESULTS_BASE_DIR/caliper_users${NUM_USERS}_tps${TPS_RATE}_run${i}"
                mkdir -p "$run_results_dir"
                run_caliper_tests $i "$run_results_dir"
            done
            ;;
        2)
            get_user_input
            for (( i=1; i<=$NUM_REPETITIONS; i++ )); do
                echo -e "\n--- A iniciar execução JMETER #${i} de ${NUM_REPETITIONS} ---"
                run_results_dir="$RESULTS_BASE_DIR/jmeter_users${NUM_USERS}_tps${TPS_RATE}_run${i}"
                mkdir -p "$run_results_dir"
                run_jmeter_tests $i "$run_results_dir"
            done
            ;;
        3)
            echo "A sair."
            exit 0
            ;;
        *)
            echo "Opção inválida. Por favor, tente novamente."
            ;;
    esac
done