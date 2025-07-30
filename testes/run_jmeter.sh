#!/bin/bash

# --- CONFIGURAÇÕES ---
JMETER_VERSION="5.6.3"
JMETER_DIR="apache-jmeter-${JMETER_VERSION}"
JMETER_URL="https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz"
CONTRACT_ADDRESS_FILE="contract_address.txt"
export JAVA_HOME=../jdk-21.0.7

# Caminhos para os planos de teste
JMX_OPEN="test_round1_open.jmx"
JMX_QUERY="test_round2_query.jmx"
JMX_TRANSFER="test_round3_transfer.jmx"

# Lista de contentores a serem monitorizados
DOCKER_CONTAINERS=("node1" "node2" "node3" "node4" "node5" "node6")

# === NOVA CONFIGURAÇÃO PARA EXECUÇÕES MÚLTIPLAS ===
NUM_REPETITIONS=${1:-1}
TESTE_DIR="$(pwd)"
JMETER_RUNS_DIR="$TESTE_DIR/jmeter_runs"

# Limpa o diretório de execuções anteriores e cria um novo
rm -rf "$JMETER_RUNS_DIR"
mkdir -p "$JMETER_RUNS_DIR"

# Função para gerar endereços Ethereum
generate_eth_accounts_csv() {
    echo "Gerando endereços Ethereum..."
    local temp_dir="temp_eth_gen"
    local accounts_file="ethereum_accounts.csv"
    local num_accounts=1000

    mkdir -p "$temp_dir"
    pushd "$temp_dir" > /dev/null
    if ! command -v npm &> /dev/null; then echo "Erro: 'npm' não está instalado."; exit 1; fi
    npm init -y > /dev/null 2>&1
    npm install ethers@^6.0.0 > /dev/null 2>&1
    if [ $? -ne 0 ]; then echo "Erro: Falha ao instalar 'ethers'."; popd > /dev/null; rm -rf "$temp_dir"; exit 1; fi
    cat <<EOF > generate_accounts.js
const { Wallet } = require('ethers');
const fs = require('fs');
const numAccounts = ${num_accounts};
const outputFileName = '${accounts_file}';
let csvContent = 'accountId\\n';
for (let i = 0; i < numAccounts; i++) {
    const wallet = Wallet.createRandom();
    csvContent += \`\${wallet.address}\\n\`;
}
fs.writeFileSync(outputFileName, csvContent);
console.log(\`\${numAccounts} endereços Ethereum gerados e salvos em \${outputFileName}\`);
EOF
    node generate_accounts.js
    if [ $? -ne 0 ]; then echo "Erro: Falha ao executar script Node.js."; popd > /dev/null; rm -rf "$temp_dir"; exit 1; fi
    cp "$accounts_file" ../
    popd > /dev/null
    rm -rf "$temp_dir"
    echo "Endereços gerados em ./$accounts_file"
}

# Função para processar o JTL e retornar dados formatados
parse_jtl_for_html() {
    local jtl_file=$1
    if [ ! -f "$jtl_file" ]; then echo "0 0 N/A N/A N/A N/A N/A"; return; fi
    
    awk 'BEGIN { FS=","; min_lat=999999999; max_lat=0; total_lat=0; count_s=0; count_f=0; first_ts=0; last_ts=0; total_req=0; }
    NR > 1 {
        ts=$1; el=$2; sc=$8;
        if(first_ts==0){first_ts=ts}
        last_ts=ts;
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
        dur_s="N/A";
        if(first_ts>0 && last_ts>0){ dur_ms=last_ts-first_ts; if(dur_ms>0){dur_s=sprintf("%.2f", dur_ms/1000)}else{dur_s="0.00"} }
        s_rate="N/A"; tps="N/A";
        if(dur_s!="N/A" && dur_s > 0){
            s_rate=sprintf("%.2f", total_req/dur_s);
            if(count_s>0){tps=sprintf("%.2f", count_s/dur_s)}else{tps="0.00"}
        }
        printf "%d %d %s %s %s %s %s", count_s, count_f, s_rate, max_lat_s, min_lat_s, avg_lat_s, tps;
    }' "$jtl_file"
}

# --- FUNÇÃO PARA GERAR O RELATÓRIO HTML ---
generate_html_report() {
    local run_dir=$1
    local report_file="$run_dir/jmeter_docker_report.html"
    local rounds=("Open" "Query" "Transfer")

    # Inicia o ficheiro HTML com o cabeçalho e estilos
    cat > "$report_file" <<EOF
<!doctype html>
<html>
<head>
    <title>JMeter & Docker Report</title>
    <meta charset="UTF-8"/>
    <style type="text/css">
        body { font-family: IBM Plex Sans; font-weight: 200; }
        .left-column { position: fixed; width:20%; }
        .left-column ul { display: block; padding: 0; list-style: none; border-bottom: 1px solid #d9d9d9; font-size: 14px; }
        .left-column h2 { font-size: 24px; font-weight: 400; margin-block-end: 0.5em; }
        .left-column h3 { font-size: 18px; font-weight: 400; margin-block-end: 0.5em; }
        .left-column li { margin-left: 10px; margin-bottom: 5px; color: #5e6b73; }
        .right-column { margin-left: 22%; width:60%; }
        .right-column table { font-size:11px; color:#333333; border-width: 1px; border-color: #666666; border-collapse: collapse; margin-bottom: 10px; }
        .right-column h2, .right-column h3, .right-column h4 { font-weight: 400; }
        .right-column h4 { margin-block-end: 0; }
        .right-column th { border-width: 1px; font-size: small; padding: 8px; border-style: solid; border-color: #666666; background-color: #f2f2f2; }
        .right-column td { border-width: 1px; font-size: small; padding: 8px; border-style: solid; border-color: #666666; background-color: #ffffff; font-weight: 400; }
        .tag { margin-bottom: 10px; padding: 5px 10px; }
    </style>
</head>
<body>
    <main>
        <div class="left-column">
            <img src="https://hyperledger.github.io/caliper/assets/img/hyperledger_caliper_logo_color.png" style="width:95%;" alt="">
            <ul>
                <h3>&nbspBasic information</h3>
                <li>Tool: &nbsp<span style="font-weight: 500;">JMeter & Docker</span></li>
                <li>Benchmark Rounds: &nbsp<span style="font-weight: 500;">3</span></li>
            </ul>
            <ul>
                <h3>&nbspBenchmark results</h3>
                <li><a href="#benchmarksummary">Summary</a></li>
EOF
    for round_name in "${rounds[@]}"; do
        echo "<li><a href=\"#${round_name,,}\">${round_name}</a></li>" >> "$report_file"
    done
    echo "</ul></div><div class=\"right-column\"><h1 style=\"padding-top: 3em; font-weight: 500;\">JMeter Report</h1>" >> "$report_file"
    
    # Tabela de Sumário de Performance
    echo "<div style=\"border-bottom: 1px solid #d9d9d9; margin-bottom: 10px;\" id=\"benchmarksummary\"><h3>Summary of performance metrics</h3><table style=\"min-width: 100%;\"><tr><th>Name</th><th>Succ</th><th>Fail</th><th>Send Rate (TPS)</th><th>Max Latency (s)</th><th>Min Latency (s)</th><th>Avg Latency (s)</th><th>Throughput (TPS)</th></tr>" >> "$report_file"
    for round_name in "${rounds[@]}"; do
        jtl_file="$run_dir/results_${round_name,,}.jtl"
        perf_data=($(parse_jtl_for_html "$jtl_file"))
        echo "<tr><td>${round_name}</td><td>${perf_data[0]}</td><td>${perf_data[1]}</td><td>${perf_data[2]}</td><td>${perf_data[3]}</td><td>${perf_data[4]}</td><td>${perf_data[5]}</td><td>${perf_data[6]}</td></tr>" >> "$report_file"
    done
    echo "</table></div>" >> "$report_file"

    # Secções detalhadas para cada Round
    for round_name in "${rounds[@]}"; do
        jtl_file="$run_dir/results_${round_name,,}.jtl"
        docker_stats_log="$run_dir/docker_stats_${round_name,,}.log"
        perf_data=($(parse_jtl_for_html "$jtl_file"))

        echo "<div style=\"border-bottom: 1px solid #d9d9d9; padding-bottom: 10px;\" id=\"${round_name,,}\"><h2>Benchmark round: ${round_name}</h2><h3>Performance metrics for ${round_name}</h3><table style=\"min-width: 100%;\"><tr><th>Name</th><th>Succ</th><th>Fail</th><th>Send Rate (TPS)</th><th>Max Latency (s)</th><th>Min Latency (s)</th><th>Avg Latency (s)</th><th>Throughput (TPS)</th></tr><tr><td>${round_name}</td><td>${perf_data[0]}</td><td>${perf_data[1]}</td><td>${perf_data[2]}</td><td>${perf_data[3]}</td><td>${perf_data[4]}</td><td>${perf_data[5]}</td><td>${perf_data[6]}</td></tr></table>" >> "$report_file"
        echo "<h3>Resource utilization for ${round_name}</h3><h4>Resource monitor: docker</h4><table style=\"min-width: 100%;\"><tr><th>Name</th><th>CPU%(max)</th><th>CPU%(avg)</th><th>Memory(max) [MB]</th><th>Memory(avg) [MB]</th></tr>" >> "$report_file"
        
        for container in "${DOCKER_CONTAINERS[@]}"; do
            if [ ! -f "$docker_stats_log" ]; then continue; fi
            CPU_DATA=$(grep "$container" "$docker_stats_log" | awk -F, '{print $2}' | sed 's/%//')
            MEM_DATA=$(grep "$container" "$docker_stats_log" | awk -F, '{print $3}' | sed -e 's/MiB.*//' -e 's/GiB.*/ \* 1024/' | bc)
            
            if [ -n "$CPU_DATA" ]; then
                MAX_CPU=$(echo "$CPU_DATA" | sort -nr | head -n 1)
                AVG_CPU=$(echo "$CPU_DATA" | awk '{ total += $1 } END { if (NR > 0) printf "%.2f", total/NR; else print "0.00" }')
                MAX_MEM=$(echo "$MEM_DATA" | sort -nr | head -n 1)
                AVG_MEM=$(echo "$MEM_DATA" | awk '{ total += $1 } END { if (NR > 0) printf "%.2f", total/NR; else print "0.00" }')
                
                LC_NUMERIC=C echo "<tr><td>/${container}</td><td>${MAX_CPU}</td><td>${AVG_CPU}</td><td>${MAX_MEM}</td><td>${AVG_MEM}</td></tr>" >> "$report_file"
            fi
        done
        echo "</table></div>" >> "$report_file"
    done

    # Fecha o ficheiro HTML
    echo "</div></main></body></html>" >> "$report_file"
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


# --- LÓGICA PRINCIPAL ---
if [ ! -s "$CONTRACT_ADDRESS_FILE" ]; then
    echo "Erro: Arquivo '$CONTRACT_ADDRESS_FILE' não encontrado ou vazio. Execute 'run_caliper.sh' primeiro."
    exit 1
fi
CONTRACT_ADDRESS=$(<"$CONTRACT_ADDRESS_FILE")
generate_eth_accounts_csv
ACCOUNT_CSV_FILE="$(pwd)/ethereum_accounts.csv"


# --- EXECUÇÃO EM LOOP ---
for (( i=1; i<=$NUM_REPETITIONS; i++ ))
do
    echo -e "\n--- Iniciando Execução JMeter #$i de $NUM_REPETITIONS ---"
    CURRENT_JMETER_RUN_DIR="$JMETER_RUNS_DIR/run_$i"
    mkdir -p "$CURRENT_JMETER_RUN_DIR"

    # Função para executar um round e monitorizá-lo
    run_test_and_monitor() {
        local JMX_FILE=$1
        local ROUND_NAME=$2
        local JTL_FILE="$CURRENT_JMETER_RUN_DIR/results_${ROUND_NAME,,}.jtl"
        local DOCKER_STATS_LOG="$CURRENT_JMETER_RUN_DIR/docker_stats_${ROUND_NAME,,}.log"

        echo -e "\n--- Executando Round: $ROUND_NAME ---"
        rm -f "$DOCKER_STATS_LOG"
        touch "$DOCKER_STATS_LOG"

        # Inicia o monitoramento
        MONITOR_PID=
        (
            while true; do
                docker stats --no-stream --format "{{.Name}},{{.CPUPerc}},{{.MemUsage}}" "${DOCKER_CONTAINERS[@]}" >> "$DOCKER_STATS_LOG"
                sleep 1
            done
        ) & MONITOR_PID=$!
        
        # Executa o teste JMeter
        "$JMETER_HOME/jmeter" -n -t "$JMX_FILE" -l "$JTL_FILE" -JcontractAddress="$CONTRACT_ADDRESS" -JaccountCsvPath="$ACCOUNT_CSV_FILE"
        
        # Para o monitoramento
        kill "$MONITOR_PID"
    }

    # Executa cada round separadamente
    run_test_and_monitor "$JMX_OPEN" "Open"
    run_test_and_monitor "$JMX_QUERY" "Query"
    run_test_and_monitor "$JMX_TRANSFER" "Transfer"

    # Gera o relatório HTML no final da execução
    generate_html_report "$CURRENT_JMETER_RUN_DIR"

done

echo -e "\nExecução do JMeter concluída!"