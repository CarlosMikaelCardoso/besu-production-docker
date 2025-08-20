#!/bin/bash

# --- CONFIGURAÇÕES ---
JMETER_VERSION="5.6.3"
JMETER_DIR="apache-jmeter-${JMETER_VERSION}"
JMETER_URL="https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz"
CONTRACT_ADDRESS_FILE="contract_address.txt"
API_HOST="10.126.1.249" # <--- MUDE PARA O IP DA SUA VM ONDE A API ESTÁ A CORRER

# === NOVA CONFIGURAÇÃO PARA EXECUÇÕES MÚLTIPLAS E SELEÇÃO DE USUÁRIOS ===
# Número de usuários para o teste (5, 10, 25, 50). Padrão para 5 se nenhum argumento for fornecido.
NUM_USERS=${1:-5}
# Número de repetições. Padrão para 1 se nenhum segundo argumento for fornecido.
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

# MODIFICAÇÃO: O número de contas e transações agora é calculado dinamicamente
BASE_ACCOUNTS=1000
BASE_TRANSFER_TX=50
NUMBER_OF_ACCOUNTS=$((BASE_ACCOUNTS * NUM_REPETITIONS))
TRANSFER_TX_NUMBER=$((BASE_TRANSFER_TX * NUM_REPETITIONS))

# Configurações para o Java
JAVA_DIR_NAME="jdk-21.0.7"
JAVA_TAR_GZ="jdk-21.0.7_linux-x64_bin.tar.gz"
JAVA_URL="https://download.oracle.com/java/21/archive/${JAVA_TAR_GZ}"
export JAVA_HOME="$(pwd)/../${JAVA_DIR_NAME}"

# Caminhos para os planos de teste (JMX) - Agora dinâmicos
JMX_DIR="${NUM_USERS}_Users/Jmeter"
JMX_OPEN="${JMX_DIR}/test_round1_open.jmx"
JMX_QUERY="${JMX_DIR}/test_round2_query.jmx"
JMX_TRANSFER="${JMX_DIR}/test_round3_transfer.jmx"

# Diretório para os resultados do JMeter - Agora dinâmico
TESTE_DIR="$(pwd)"
JMETER_RUNS_DIR="$TESTE_DIR/jmeter_runs_${NUM_USERS}_users"

rm -rf "$JMETER_RUNS_DIR"
mkdir -p "$JMETER_RUNS_DIR"

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

# MODIFICAÇÃO: A função foi ajustada para calcular o TPS de forma mais robusta,
# usando o tempo de conclusão da última transação para garantir que a duração nunca seja zero.
parse_jtl_for_html() {
    local jtl_file=$1
    if [ ! -f "$jtl_file" ]; then echo "0 0 N/A N/A N/A N/A N/A"; return; fi
    awk 'BEGIN { FS=","; min_lat=999999999; max_lat=0; total_lat=0; count_s=0; count_f=0; first_ts=0; last_ts=0; total_req=0; last_el=0; }
    NR > 1 {
        ts=$1; el=$2; sc=$8;
        if(first_ts==0){first_ts=ts}
        last_ts=ts;
        last_el=el; # Guarda o tempo da última transação
        total_req++;
        if(sc=="true"){
            count_s++;
            total_lat+=el;
            if(el<min_lat){min_lat=el}
            if(el>max_lat){max_lat=el}
        } else { count_f++ }
    } END {
        if(count_s>0){
            avg_lat_s=sprintf("%.2f", (total_lat/count_s)/1000);
            min_lat_s=sprintf("%.2f", min_lat/1000);
            max_lat_s=sprintf("%.2f", max_lat/1000);
        } else {avg_lat_s="N/A";min_lat_s="N/A";max_lat_s="N/A"}

        dur_s="0.00"; s_rate="N/A"; tps="N/A";
        # Calcula a duração desde o início da primeira transação até ao fim da última
        dur_ms = (last_ts + last_el) - first_ts;

        if(dur_ms <= 0 && count_s > 0){
            dur_ms = 1; # Evita divisão por zero, assume duração mínima de 1ms
        }

        if(dur_ms > 0){
            dur_s=sprintf("%.2f", dur_ms/1000);
            s_rate=sprintf("%.2f", total_req/dur_s);
            if(count_s>0){tps=sprintf("%.2f", count_s/dur_s)}else{tps="0.00"}
        }
        printf "%d %d %s %s %s %s %s", count_s, count_f, s_rate, max_lat_s, min_lat_s, avg_lat_s, tps;
    }' "$jtl_file"
}

# MODIFICAÇÃO: run_jmeter.sh
# A função foi atualizada para ler as novas métricas (Rede e Disco) do log
# e adicioná-las à tabela de utilização de recursos no relatório HTML.
generate_html_report() {
    local run_number=$1
    local report_file="$JMETER_RUNS_DIR/jmeter_docker_report_run_${run_number}.html"
    local rounds=("Open" "Query" "Transfer")
    cat > "$report_file" <<EOF
<!doctype html>
<html>
<head><title>JMeter & Docker Report (Run ${run_number})</title><meta charset="UTF-8"/><style type="text/css">body{font-family:IBM Plex Sans;font-weight:200;}.left-column{position:fixed;width:20%;}.left-column ul{display:block;padding:0;list-style:none;border-bottom:1px solid #d9d9d9;font-size:14px;}.left-column h3{font-size:18px;font-weight:400;margin-block-end:.5em;}.left-column li{margin-left:10px;margin-bottom:5px;color:#5e6b73;}.right-column{margin-left:22%;width:60%;}.right-column table{font-size:11px;color:#333;border-width:1px;border-color:#666;border-collapse:collapse;margin-bottom:10px;}.right-column h1,.right-column h2,.right-column h3,.right-column h4{font-weight:400;}.right-column h4{margin-block-end:0;}.right-column th{border-width:1px;font-size:small;padding:8px;border-style:solid;border-color:#666;background-color:#f2f2f2;}.right-column td{border-width:1px;font-size:small;padding:8px;border-style:solid;border-color:#666;background-color:#fff;font-weight:400;}</style></head>
<body><main><div class="left-column"><img src="https://hyperledger.github.io/caliper/assets/img/hyperledger_caliper_logo_color.png" style="width:95%;" alt=""><ul><h3>&nbspBasic information</h3><li>Tool: &nbsp<span style="font-weight: 500;">JMeter & Docker</span></li><li>Execution: &nbsp<span style="font-weight: 500;">Run ${run_number}</span></li></ul><ul><h3>&nbspBenchmark results</h3><li><a href="#benchmarksummary">Summary</a></li>
EOF
    for round_name in "${rounds[@]}"; do echo "<li><a href=\"#${round_name,,}\">${round_name}</a></li>" >> "$report_file"; done
    echo "</ul></div><div class=\"right-column\"><h1 style=\"padding-top: 3em; font-weight: 500;\">JMeter Report</h1>" >> "$report_file"
    echo "<div style=\"border-bottom: 1px solid #d9d9d9; margin-bottom: 10px;\" id=\"benchmarksummary\"><h3>Summary of performance metrics</h3><table style=\"min-width: 100%;\"><tr><th>Name</th><th>Succ</th><th>Fail</th><th>Send Rate (TPS)</th><th>Max Latency (s)</th><th>Min Latency (s)</th><th>Avg Latency (s)</th><th>Throughput (TPS)</th></tr>" >> "$report_file"
    for round_name in "${rounds[@]}"; do
        jtl_file="$JMETER_RUNS_DIR/results_${round_name,,}_run_${run_number}.jtl"
        perf_data=($(parse_jtl_for_html "$jtl_file"))
        echo "<tr><td>${round_name}</td><td>${perf_data[0]}</td><td>${perf_data[1]}</td><td>${perf_data[2]}</td><td>${perf_data[3]}</td><td>${perf_data[4]}</td><td>${perf_data[5]}</td><td>${perf_data[6]}</td></tr>" >> "$report_file"
    done; echo "</table></div>" >> "$report_file"
    for round_name in "${rounds[@]}"; do
        jtl_file="$JMETER_RUNS_DIR/results_${round_name,,}_run_${run_number}.jtl"; docker_stats_log="$JMETER_RUNS_DIR/docker_stats_${round_name,,}_run_${run_number}.log"; perf_data=($(parse_jtl_for_html "$jtl_file"))
        echo "<div style=\"border-bottom: 1px solid #d9d9d9; padding-bottom: 10px;\" id=\"${round_name,,}\"><h2>Benchmark round: ${round_name}</h2><h3>Performance metrics for ${round_name}</h3><table style=\"min-width: 100%;\"><tr><th>Name</th><th>Succ</th><th>Fail</th><th>Send Rate (TPS)</th><th>Max Latency (s)</th><th>Min Latency (s)</th><th>Avg Latency (s)</th><th>Throughput (TPS)</th></tr><tr><td>${round_name}</td><td>${perf_data[0]}</td><td>${perf_data[1]}</td><td>${perf_data[2]}</td><td>${perf_data[3]}</td><td>${perf_data[4]}</td><td>${perf_data[5]}</td><td>${perf_data[6]}</td></tr></table>" >> "$report_file"
        echo "<h3>Resource utilization for ${round_name}</h3><h4>Resource monitor: docker</h4><table style=\"min-width: 100%;\"><tr><th>Name</th><th>CPU%(max)</th><th>CPU%(avg)</th><th>Memory(max) [MB]</th><th>Memory(avg) [MB]</th><th>Net I/O(max) [KB]</th><th>Net I/O(avg) [KB]</th><th>Disk I/O(max) [KB]</th><th>Disk I/O(avg) [KB]</th></tr>" >> "$report_file"
        for container in node1 node2 node3 node4 node5 node6; do
            if [ ! -f "$docker_stats_log" ]; then continue; fi
            
            # Extrai todas as métricas
            CPU_DATA=$(grep "$container" "$docker_stats_log" | awk -F, '{print $2}' | sed 's/%//')
            MEM_DATA=$(grep "$container" "$docker_stats_log" | awk -F, '{print $3}' | sed -e 's/MiB.*//' -e 's/GiB.*/ \* 1024/' | bc)
            NET_RX_DATA=$(grep "$container" "$docker_stats_log" | awk -F, '{print $4}' | sed 's/KB//')
            NET_TX_DATA=$(grep "$container" "$docker_stats_log" | awk -F, '{print $5}' | sed 's/KB//')
            DISK_R_DATA=$(grep "$container" "$docker_stats_log" | awk -F, '{print $6}' | sed 's/KB//')
            DISK_W_DATA=$(grep "$container" "$docker_stats_log" | awk -F, '{print $7}' | sed 's/KB//')

            if [ -n "$CPU_DATA" ]; then
                # Calcula Max e Avg para cada métrica
                MAX_CPU=$(echo "$CPU_DATA" | sort -nr | head -n 1)
                AVG_CPU=$(echo "$CPU_DATA" | awk '{ total += $1 } END { if (NR > 0) printf "%.2f", total/NR; else print "0.00" }')
                MAX_MEM=$(echo "$MEM_DATA" | sort -nr | head -n 1)
                AVG_MEM=$(echo "$MEM_DATA" | awk '{ total += $1 } END { if (NR > 0) printf "%.2f", total/NR; else print "0.00" }')
                
                # Combina dados de rede e disco para calcular totais
                MAX_NET=$(paste <(echo "$NET_RX_DATA") <(echo "$NET_TX_DATA") | awk '{print $1+$2}' | sort -nr | head -n 1)
                AVG_NET=$(paste <(echo "$NET_RX_DATA") <(echo "$NET_TX_DATA") | awk '{ total += ($1+$2) } END { if (NR > 0) printf "%.2f", total/NR; else print "0.00" }')
                MAX_DISK=$(paste <(echo "$DISK_R_DATA") <(echo "$DISK_W_DATA") | awk '{print $1+$2}' | sort -nr | head -n 1)
                AVG_DISK=$(paste <(echo "$DISK_R_DATA") <(echo "$DISK_W_DATA") | awk '{ total += ($1+$2) } END { if (NR > 0) printf "%.2f", total/NR; else print "0.00" }')
                
                LC_NUMERIC=C echo "<tr><td>/${container}</td><td>${MAX_CPU}</td><td>${AVG_CPU}</td><td>${MAX_MEM}</td><td>${AVG_MEM}</td><td>${MAX_NET}</td><td>${AVG_NET}</td><td>${MAX_DISK}</td><td>${AVG_DISK}</td></tr>" >> "$report_file"
            fi
        done; echo "</table></div>" >> "$report_file"
    done; echo "</div></main></body></html>" >> "$report_file"
    echo -e "\nRelatório HTML gerado em: $report_file"
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

check_and_install_java

run_direct_test() {
    local JMX_FILE=$1
    local ROUND_NAME=$2
    local RUN_NUMBER=$3
    local CSV_FILE_PATH=$4

    local JTL_FILE="$JMETER_RUNS_DIR/results_${ROUND_NAME,,}_run_${RUN_NUMBER}.jtl"

    echo -e "\n--- Executando Round Direto: $ROUND_NAME (Execução #${RUN_NUMBER}) ---"

    # MODIFICAÇÃO:
    # 1. Definimos NODE_PATH para que o motor Graal.js do JMeter encontre a pasta node_modules.
    # 2. Removemos a propriedade -JETHERS_PATH que não é mais necessária.
    export NODE_PATH="$(pwd)/node_modules"

    "$JMETER_HOME/jmeter" -n -t "$JMX_FILE" -l "$JTL_FILE" \
        -JcsvDataFile="$CSV_FILE_PATH" \
        -JSUT_ADAPTER_PATH="$SCRIPTS_DIR/sutAdapter.js" \
        -JDEPLOYER_PRIVATE_KEY="8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63" \
        -JCONTRACT_ADDRESS="$CONTRACT_ADDRESS" \
        -JBESU_RPC_URL="http://10.126.1.249:8545" # IP da VM do Besu
}

# --- LÓGICA PRINCIPAL ---
if [ ! -s "$CONTRACT_ADDRESS_FILE" ]; then
    echo "Erro: Arquivo '$CONTRACT_ADDRESS_FILE' não encontrado ou vazio. Execute o deploy do contrato primeiro."
    exit 1
fi
CONTRACT_ADDRESS=$(<"$CONTRACT_ADDRESS_FILE")

generate_caliper_style_accounts_csv

# --- EXECUÇÃO EM LOOP ---
for (( i=1; i<=$NUM_REPETITIONS; i++ ))
do
    echo -e "\n--- Iniciando Execução JMeter #$i de $NUM_REPETITIONS ---"

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
            -JcontractAddress="$CONTRACT_ADDRESS" \
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

    # MODIFICAÇÃO: As chamadas agora passam as variáveis com os totais corretos
    run_test_and_monitor "$JMX_OPEN" "Open" "$i" "$JMETER_RUNS_DIR/open_accounts.csv" "$NUMBER_OF_ACCOUNTS"
    run_test_and_monitor "$JMX_QUERY" "Query" "$i" "$JMETER_RUNS_DIR/open_accounts.csv" "$NUMBER_OF_ACCOUNTS"
    run_test_and_monitor "$JMX_TRANSFER" "Transfer" "$i" "$JMETER_RUNS_DIR/transfer_accounts.csv" "$TRANSFER_TX_NUMBER"

    generate_html_report "$i"
done
# MODIFICAÇÃO: A chamada ao script python agora passa o número da execução ($i)
python3 generateGraphs.py "$JMETER_RUNS_DIR"

echo -e "\nExecução do JMeter concluída!"