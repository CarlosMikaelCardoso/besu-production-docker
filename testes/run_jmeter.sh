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
JMETER_HOME="$(pwd)/${JMETER_DIR}/bin"


# --- VERIFICAÇÃO DO ENDEREÇO DO CONTRATO ---
echo "Passo 1: Lendo o endereço do contrato..."
if [ ! -s "$CONTRACT_ADDRESS_FILE" ]; then
    echo "Erro: Arquivo '$CONTRACT_ADDRESS_FILE' não encontrado ou vazio. Execute 'run_caliper.sh' primeiro."
    exit 1
fi
CONTRACT_ADDRESS=$(<"$CONTRACT_ADDRESS_FILE")
echo "Endereço do contrato a ser utilizado: $CONTRACT_ADDRESS"

# --- GERAR NOVAS CONTAS ETHEREUM E PREPARAR PROPRIEDADES PARA O JMETER ---
generate_eth_accounts_csv
ACCOUNT_PROPERTIES=""
ACCOUNT_INDEX=1
while IFS= read -r account_id || [[ -n "$account_id" ]]; do
  # Ignora a linha do cabeçalho
  if [ "$ACCOUNT_INDEX" -eq 1 ]; then
    ACCOUNT_INDEX=$((ACCOUNT_INDEX + 1))
    continue
  fi
  ACCOUNT_PROPERTIES+=" -Jaccount_${ACCOUNT_INDEX}=${account_id}"
  ACCOUNT_INDEX=$((ACCOUNT_INDEX + 1))
done < ethereum_accounts.csv

# Função para executar o JMeter e coletar métricas de uso de recursos
run_jmeter_with_metrics() {
    local jmx_file="$1"
    local output_jtl="$2"
    local round_name="$3"
    local contract_address="$4"
    local account_properties="$5"
    # Cria um arquivo temporário para as métricas de recursos deste round
    local resource_metrics_file="jmeter_resource_metrics_${round_name}.txt"

    echo "Executing JMeter for $round_name..."
    # Executa o JMeter e captura o uso de recursos usando /usr/bin/time -v.
    # A saída de erro do time (que contém as métricas) vai para resource_metrics_file.
    /usr/bin/time -v "$JMETER_HOME/jmeter" -n -t "$jmx_file" -l "$output_jtl" \
        -JcontractAddress="$contract_address" $account_properties 2> "$resource_metrics_file"

    if [ $? -ne 0 ]; then
        echo "Erro: JMeter '$round_name' falhou."
        echo "Detalhes do erro e uso de recurso em $resource_metrics_file"
    else
        echo "Round $round_name finalizado. Resultados em $output_jtl"
        # Anexa o sumário de uso de recursos a uma seção dedicada no relatório final combinado
        echo -e "\n--- JMeter Round: $round_name Resource Usage ---" >> jmeter_full_report.txt
        cat "$resource_metrics_file" >> jmeter_full_report.txt
    fi
    rm "$resource_metrics_file" # Limpa o arquivo temporário
}

# --- EXECUÇÃO DOS TESTES JMETER EM SEQUÊNCIA ---
echo -e "\n--- Iniciando Testes JMeter ---"
# Inicializa um novo arquivo de relatório combinado.
echo "--- JMeter Full Test Report ---" > jmeter_full_report.txt

# Arquivo temporário para as métricas de recursos consolidadas de todos os rounds do JMeter.
JMETER_RESOURCE_SUMMARY_FILE="jmeter_resource_summary_temp.log"

# Exporta as variáveis necessárias para o subshell do bash -c
export JMETER_HOME
export JMX_OPEN JMX_QUERY JMX_TRANSFER
export CONTRACT_ADDRESS ACCOUNT_PROPERTIES

# Executa todos os rounds do JMeter dentro de um único bloco /usr/bin/time -v.
# A saída de erro do /usr/bin/time (que contém as métricas de recursos) é redirecionada para JMETER_RESOURCE_SUMMARY_FILE.
/usr/bin/time -v bash -c '
    echo "Passo 2.1: Executando Round 1: Open..."
    "$JMETER_HOME/jmeter" -n -t "$JMX_OPEN" -l "results_open.jtl" -JcontractAddress="$CONTRACT_ADDRESS" $ACCOUNT_PROPERTIES
    # Verifica o status de saída de cada comando JMeter individualmente
    if [ $? -ne 0 ]; then echo "Erro: JMeter Round 1 (Open) falhou." >&2; exit 1; fi

    echo "Passo 2.2: Executando Round 2: Query..."
    "$JMETER_HOME/jmeter" -n -t "$JMX_QUERY" -l "results_query.jtl" -JcontractAddress="$CONTRACT_ADDRESS" $ACCOUNT_PROPERTIES
    if [ $? -ne 0 ]; then echo "Erro: JMeter Round 2 (Query) falhou." >&2; exit 1; fi

    echo "Passo 2.3: Executando Round 3: Transfer..."
    "$JMETER_HOME/jmeter" -n -t "$JMX_TRANSFER" -l "results_transfer.jtl" -JcontractAddress="$CONTRACT_ADDRESS" $ACCOUNT_PROPERTIES
    if [ $? -ne 0 ]; then echo "Erro: JMeter Round 3 (Transfer) falhou." >&2; exit 1; fi
' 2> "$JMETER_RESOURCE_SUMMARY_FILE" # Redireciona a saída de erro (métricas do time) do subshell para o arquivo de sumário

# Desexporta as variáveis para limpar o ambiente após a execução do bloco
unset JMETER_HOME JMX_OPEN JMX_QUERY JMX_TRANSFER CONTRACT_ADDRESS ACCOUNT_PROPERTIES

# Verifica o status de saída de todo o bloco de execução do JMeter
if [ $? -ne 0 ]; then
    echo "Erro: Um ou mais rounds do JMeter falharam. Verifique os arquivos .jtl e $JMETER_RESOURCE_SUMMARY_FILE para detalhes."
    # Anexa o sumário de recursos mesmo em caso de falha para depuração
    echo -e "\n--- JMeter Consolidated Resource Usage Summary (on error) ---" >> jmeter_full_report.txt
    cat "$JMETER_RESOURCE_SUMMARY_FILE" >> jmeter_full_report.txt
else
    echo -e "\nTodos os rounds do JMeter concluídos."
fi

# Anexa o sumário de uso de recursos consolidado ao relatório completo
echo -e "\n--- JMeter Consolidated Resource Usage Summary ---" >> jmeter_full_report.txt
cat "$JMETER_RESOURCE_SUMMARY_FILE" >> jmeter_full_report.txt

# Limpa o arquivo temporário de métricas de recursos
rm "$JMETER_RESOURCE_SUMMARY_FILE"

echo -e "\n--- Sumário de todos os testes JMeter (Formato Caliper) ---"
# Redireciona o sumário formatado para o novo relatório combinado
echo "+----------+------+------+-----------------+-----------------+-----------------+-----------------+------------------+" >> jmeter_full_report.txt
echo "| Name     | Succ | Fail | Send Rate (TPS) | Max Latency (s) | Min Latency (s) | Avg Latency (s) | Throughput (TPS) |" >> jmeter_full_report.txt
echo "+----------+------+------+-----------------+-----------------+-----------------+-----------------+------------------+" >> jmeter_full_report.txt
process_jtl_to_caliper_format "results_open.jtl" "Open" >> jmeter_full_report.txt
process_jtl_to_caliper_format "results_query.jtl" "Query" >> jmeter_full_report.txt
process_jtl_to_caliper_format "results_transfer.jtl" "Transfer" >> jmeter_full_report.txt
echo "+----------+------+------+-----------------+-----------------+-----------------+-----------------+------------------+" >> jmeter_full_report.txt

echo -e "\nTodos os testes do JMeter foram concluídos com sucesso! Veja o relatório completo em jmeter_full_report.txt"

# Mantém a saída para o console também, conforme o script original
echo -e "\n--- Sumário de todos os testes JMeter (Formato Caliper) ---"
echo "+----------+------+------+-----------------+-----------------+-----------------+-----------------+------------------+"
echo "| Name     | Succ | Fail | Send Rate (TPS) | Max Latency (s) | Min Latency (s) | Avg Latency (s) | Throughput (TPS) |"
echo "+----------+------+------+-----------------+-----------------+-----------------+-----------------+------------------+"
process_jtl_to_caliper_format "results_open.jtl" "open"
process_jtl_to_caliper_format "results_query.jtl" "query"
process_jtl_to_caliper_format "results_transfer.jtl" "transfer"
echo "+----------+------+------+-----------------+-----------------+-----------------+-----------------+------------------+"