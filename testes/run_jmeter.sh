#!/bin/bash

# --- CONFIGURAÇÕES ---
JMETER_VERSION="5.6.3"
JMETER_DIR="apache-jmeter-${JMETER_VERSION}"
JMETER_URL="https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz"
CONTRACT_ADDRESS_FILE="contract_address.txt"
# MODIFICAÇÃO: Corrigida a versão do JAVA_HOME para alinhar com a branch 'smart-contract'.
export JAVA_HOME=../jdk-21.0.7
# Caminhos para os planos de teste
JMX_OPEN="test_round1_open.jmx"
JMX_QUERY="test_round2_query.jmx"
JMX_TRANSFER="test_round3_transfer.jmx"

# === NOVA CONFIGURAÇÃO PARA EXECUÇÕES MÚLTIPLAS ===
# Número de repetições. Padrão para 1 se nenhum argumento for fornecido.
NUM_REPETITIONS=${1:-1}
# Diretório para logs individuais de cada execução
TESTE_DIR="$(pwd)"
JMETER_RUNS_DIR="$TESTE_DIR/jmeter_runs"
# Arquivo para o sumário consolidado de recursos de todas as execuções
JMETER_CONSOLIDATED_RESOURCE_SUMMARY_FILE="$TESTE_DIR/jmeter_consolidated_resource_summary.log"

# Limpa o diretório de execuções anteriores e cria um novo
rm -rf "$JMETER_RUNS_DIR"
mkdir -p "$JMETER_RUNS_DIR"

# Inicializa arrays para armazenar as métricas de cada execução
declare -a max_rss_values
declare -a cpu_percent_values
declare -a user_time_values
declare -a sys_time_values

echo "Iniciando a execução do JMeter por $NUM_REPETITIONS vezes."
echo "Resultados detalhados de cada execução serão salvos em: $JMETER_RUNS_DIR"
echo "Sumário de recursos consolidado em: $JMETER_CONSOLIDATED_RESOURCE_SUMMARY_FILE"

# Prepara o cabeçalho para o arquivo de sumário de recursos consolidado
echo "Run,Max_RSS_KB,CPU_Percent,User_Time_Sec,Sys_Time_Sec" > "$JMETER_CONSOLIDATED_RESOURCE_SUMMARY_FILE"


# Array para armazenar os resultados formatados de cada round
declare -a ROUND_RESULTS

# Função para gerar endereços Ethereum e salvá-los em um CSV
generate_eth_accounts_csv() {
    echo "Gerando endereços Ethereum..."
    local temp_dir="temp_eth_gen"
    local accounts_file="ethereum_accounts.csv"
    local num_accounts=1000 # Defina quantas contas você quer gerar

    mkdir -p "$temp_dir"
    pushd "$temp_dir" > /dev/null # Entra no diretório temporário, silenciando a saída

    # Verifica se o npm está disponível
    if ! command -v npm &> /dev/null; then
        echo "Erro: 'npm' não está instalado. Por favor, instale o Node.js e o npm para gerar os endereços."
        exit 1
    fi

    # Inicializa projeto Node.js e instala ethers
    npm init -y > /dev/null 2>&1 # Silencia a saída
    npm install ethers@^6.0.0 > /dev/null 2>&1 # Instala ethers v6 ou superior, silencia a saída

    if [ $? -ne 0 ]; then
        echo "Erro: Falha ao instalar 'ethers'. Verifique sua conexão com a internet ou as permissões."
        popd > /dev/null
        rm -rf "$temp_dir"
        exit 1
    fi

    # Conteúdo do script Node.js para gerar as contas
    cat <<EOF > generate_accounts.js
const { Wallet } = require('ethers');
const fs = require('fs');

const numAccounts = ${num_accounts};
const outputFileName = '${accounts_file}';

let csvContent = 'accountId\\n'; // Cabeçalho do CSV

for (let i = 0; i < numAccounts; i++) {
    const wallet = Wallet.createRandom();
    csvContent += \`\${wallet.address}\\n\`;
}

fs.writeFileSync(outputFileName, csvContent);
console.log(\`\${numAccounts} endereços Ethereum gerados e salvos em \${outputFileName}\`);
EOF

    node generate_accounts.js
    
    if [ $? -ne 0 ]; then
        echo "Erro: Falha ao executar o script Node.js para gerar endereços."
        popd > /dev/null
        rm -rf "$temp_dir"
        exit 1
    fi

    cp "$accounts_file" ../ # Copia para o diretório pai (onde run_jmeter.sh está)
    popd > /dev/null # Sai do diretório temporário
    rm -rf "$temp_dir" # Limpa o diretório temporário
    echo "Endereços gerados em ./$accounts_file"
}

# Função para processar o arquivo .jtl e formatar a saída como o Caliper
process_jtl_to_caliper_format() {
    local jtl_file="$1"
    local round_name="$2"
    local success_count=0
    local fail_count=0
    local min_latency="N/A"
    local max_latency="N/A"
    local avg_latency="N/A"
    local send_rate="N/A"
    local throughput="N/A"

    if [ -f "$jtl_file" ]; then
        read -r success_count fail_count min_latency max_latency avg_latency send_rate throughput <<< \
        $(awk 'BEGIN {
            FS = ",";
            min_lat_ms = 999999999;
            max_lat_ms = 0;
            total_lat_ms = 0;
            count_success = 0;
            count_fail = 0;
            total_requests = 0;
            first_ts = 0;
            last_ts = 0;
        }
        NR > 1 {
            timestamp = $1;
            elapsed = $2;
            success = $8;

            if (first_ts == 0) {
                first_ts = timestamp;
            }
            last_ts = timestamp;

            total_requests++;

            if (success == "true") {
                count_success++;
                total_lat_ms += elapsed;
                if (elapsed < min_lat_ms) {
                    min_lat_ms = elapsed;
                }
                if (elapsed > max_lat_ms) {
                    max_lat_ms = elapsed;
                }
            } else {
                count_fail++;
            }
        }
        END {
            if (count_success > 0) {
                avg_lat_ms = total_lat_ms / count_success;
                min_lat_s = sprintf("%.2f", min_lat_ms / 1000);
                max_lat_s = sprintf("%.2f", max_lat_ms / 1000);
                avg_lat_s = sprintf("%.2f", avg_lat_ms / 1000);
            } else {
                min_lat_s = "N/A";
                max_lat_s = "N/A";
                avg_lat_s = "N/A";
            }

            duration_s = "N/A";
            if (first_ts != 0 && last_ts != 0) {
                duration_ms = last_ts - first_ts;
                if (duration_ms > 0) {
                    duration_s = sprintf("%.2f", duration_ms / 1000);
                } else {
                    duration_s = "0.00";
                }
            }
            
            send_rate = "N/A";
            throughput = "N/A";

            if (duration_s != "N/A" && duration_s > 0) {
                send_rate = sprintf("%.2f", total_requests / duration_s);
                if (count_success > 0) {
                    throughput = sprintf("%.2f", count_success / duration_s);
                } else {
                    throughput = "0.00";
                }
            }


            printf "%d %d %s %s %s %s %s\n", count_success, count_fail, min_lat_s, max_lat_s, avg_lat_s, send_rate, throughput;
        }' "$jtl_file")
    fi
        
    printf "| %-8s | %-4s | %-4s | %-15s | %-15s | %-15s | %-15s | %-16s |\n" \
    "$round_name" "$success_count" "$fail_count" "$send_rate" "$max_latency" "$min_latency" "$avg_latency" "$throughput"
}

# --- INSTALAÇÃO AUTOMÁTICA DO JMETER ---
if [ ! -d "$JMETER_DIR" ]; then
    echo "Diretório do JMeter não encontrado. Baixando e instalando o JMeter ${JMETER_VERSION}..."
    if ! command -v wget &> /dev/null; then
        echo "Erro: 'wget' não está instalado. Por favor, instale-o para continuar."
        exit 1
    fi
    wget -q --show-progress "$JMETER_URL"
    tar -xzf "apache-jmeter-${JMETER_VERSION}.tgz"
    rm "apache-jmeter-${JMETER_VERSION}.tgz"
    echo "JMeter instalado com sucesso em ./${JMETER_DIR}/"
else
    echo "JMeter já está instalado."
fi
export JMETER_HOME="$(pwd)/${JMETER_DIR}/bin"


# --- VERIFICAÇÃO DO ENDEREÇO DO CONTRATO ---
echo "Passo 1: Lendo o endereço do contrato..."
if [ ! -s "$CONTRACT_ADDRESS_FILE" ]; then
    echo "Erro: Arquivo '$CONTRACT_ADDRESS_FILE' não encontrado ou vazio. Execute 'run_caliper.sh' primeiro."
    exit 1
fi
CONTRACT_ADDRESS=$(<"$CONTRACT_ADDRESS_FILE")
echo "Endereço do contrato a ser utilizado: $CONTRACT_ADDRESS"

# --- GERAR NOVAS CONTAS ETHEREUM ---
generate_eth_accounts_csv
ACCOUNT_CSV_FILE="$(pwd)/ethereum_accounts.csv"


# --- EXECUÇÃO EM LOOP ---
for (( i=1; i<=$NUM_REPETITIONS; i++ ))
do
    echo -e "\n--- Execução do JMeter #$i de $NUM_REPETITIONS ---"

    CURRENT_JMETER_RUN_DIR="$JMETER_RUNS_DIR/run_$i"
    mkdir -p "$CURRENT_JMETER_RUN_DIR"
    CURRENT_JMETER_RESOURCE_METRICS_FILE="$CURRENT_JMETER_RUN_DIR/jmeter_resource_metrics.txt"
    
    # Exporta as variáveis de ambiente necessárias para o subshell
    export JMX_OPEN
    export JMX_QUERY
    export JMX_TRANSFER
    export CONTRACT_ADDRESS
    export ACCOUNT_CSV_FILE
    export CURRENT_JMETER_RUN_DIR

    # Executa todos os rounds do JMeter dentro de um único bloco /usr/bin/time -v para cada repetição.
    /usr/bin/time -v bash -c '
        echo "Passo 2.1: Executando Round 1: Open..."
        "$JMETER_HOME/jmeter" -n -t "$JMX_OPEN" -l "$CURRENT_JMETER_RUN_DIR/results_open.jtl" -JcontractAddress="$CONTRACT_ADDRESS" -JaccountCsvPath="$ACCOUNT_CSV_FILE"
        if [ $? -ne 0 ]; then echo "Erro: JMeter Round 1 (Open) falhou." >&2; exit 1; fi

        echo "Passo 2.2: Executando Round 2: Query..."
        "$JMETER_HOME/jmeter" -n -t "$JMX_QUERY" -l "$CURRENT_JMETER_RUN_DIR/results_query.jtl" -JcontractAddress="$CONTRACT_ADDRESS" -JaccountCsvPath="$ACCOUNT_CSV_FILE"
        if [ $? -ne 0 ]; then echo "Erro: JMeter Round 2 (Query) falhou." >&2; exit 1; fi

        echo "Passo 2.3: Executando Round 3: Transfer..."
        "$JMETER_HOME/jmeter" -n -t "$JMX_TRANSFER" -l "$CURRENT_JMETER_RUN_DIR/results_transfer.jtl" -JcontractAddress="$CONTRACT_ADDRESS" -JaccountCsvPath="$ACCOUNT_CSV_FILE"
        if [ $? -ne 0 ]; then echo "Erro: JMeter Round 3 (Transfer) falhou." >&2; exit 1; fi
    ' > "$CURRENT_JMETER_RUN_DIR/jmeter_log.txt" 2> "$CURRENT_JMETER_RESOURCE_METRICS_FILE"

    JMETER_EXIT_STATUS=$?
    
    # MODIFICAÇÃO: A linha "unset" foi removida para que as variáveis persistam entre as execuções do loop.
    
    if [ "$JMETER_EXIT_STATUS" -ne 0 ]; then
        echo "Erro: A execução do JMeter #$i falhou. Verifique os logs em $CURRENT_JMETER_RUN_DIR para detalhes."
    else
        echo "Execução do JMeter #$i finalizada. Resultados salvos em $CURRENT_JMETER_RUN_DIR."

        # Extrai as métricas específicas do output do time -v
        max_rss=$(grep "Maximum resident set size (kbytes):" "$CURRENT_JMETER_RESOURCE_METRICS_FILE" | awk '{print $NF}')
        cpu_percent=$(grep "Percent of CPU this job got:" "$CURRENT_JMETER_RESOURCE_METRICS_FILE" | awk '{print $NF}' | sed 's/%.*//')
        user_time=$(grep "User time (seconds):" "$CURRENT_JMETER_RESOURCE_METRICS_FILE" | awk '{print $NF}')
        sys_time=$(grep "System time (seconds):" "$CURRENT_JMETER_RESOURCE_METRICS_FILE" | awk '{print $NF}')

        # Armazena as métricas em arrays
        max_rss_values+=("$max_rss")
        cpu_percent_values+=("$cpu_percent")
        user_time_values+=("$user_time")
        sys_time_values+=("$sys_time")

        # Anexa as métricas ao arquivo de sumário de recursos consolidado
        echo "$i,$max_rss,$cpu_percent,$user_time,$sys_time" >> "$JMETER_CONSOLIDATED_RESOURCE_SUMMARY_FILE"
        
        # Gera o sumário para a execução atual
        echo -e "\n--- Sumário da Execução #$i (Formato Caliper) ---"
        echo "+----------+------+------+-----------------+-----------------+-----------------+-----------------+------------------+"
        echo "| Name     | Succ | Fail | Send Rate (TPS) | Max Latency (s) | Min Latency (s) | Avg Latency (s) | Throughput (TPS) |"
        echo "+----------+------+------+-----------------+-----------------+-----------------+-----------------+------------------+"
        process_jtl_to_caliper_format "$CURRENT_JMETER_RUN_DIR/results_open.jtl" "Open"
        process_jtl_to_caliper_format "$CURRENT_JMETER_RUN_DIR/results_query.jtl" "Query"
        process_jtl_to_caliper_format "$CURRENT_JMETER_RUN_DIR/results_transfer.jtl" "Transfer"
        echo "+----------+------+------+-----------------+-----------------+-----------------+-----------------+------------------+"
    fi
done


# --- SUMÁRIO CONSOLIDADO DE USO DE RECURSOS ---
echo -e "\n--- Sumário Consolidado de Uso de Recursos do JMeter (todas as execuções) ---"
if [ ${#max_rss_values[@]} -eq 0 ]; then
    echo "Nenhum dado de recurso coletado para consolidação."
else
    # Calcula as médias das métricas coletadas
    avg_max_rss=$(awk 'BEGIN {sum=0; count=0} {sum+=$1; count++} END {if (count > 0) printf "%.2f", sum/count; else print "N/A"}' <(printf "%s\n" "${max_rss_values[@]}"))
    avg_cpu_percent=$(awk 'BEGIN {sum=0; count=0} {sum+=$1; count++} END {if (count > 0) printf "%.2f", sum/count; else print "N/A"}' <(printf "%s\n" "${cpu_percent_values[@]}"))
    avg_user_time=$(awk 'BEGIN {sum=0; count=0} {sum+=$1; count++} END {if (count > 0) printf "%.2f", sum/count; else print "N/A"}' <(printf "%s\n" "${user_time_values[@]}"))
    avg_sys_time=$(awk 'BEGIN {sum=0; count=0} {sum+=$1; count++} END {if (count > 0) printf "%.2f", sum/count; else print "N/A"}' <(printf "%s\n" "${sys_time_values[@]}"))

    echo "Média Max RSS: ${avg_max_rss} KB"
    echo "Média %CPU: ${avg_cpu_percent}%"
    echo "Média Tempo de Usuário: ${avg_user_time} segundos"
    echo "Média Tempo de Sistema: ${avg_sys_time} segundos"
fi

echo -e "\nDetalhes de cada execução e sumário consolidado de recursos salvos em:"
echo "- Logs por execução: $JMETER_RUNS_DIR/"
echo "- Sumário de recursos consolidado: $JMETER_CONSOLIDATED_RESOURCE_SUMMARY_FILE"

echo -e "\nExecução do JMeter concluída!"