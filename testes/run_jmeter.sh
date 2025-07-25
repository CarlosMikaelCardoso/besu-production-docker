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

# Função para processar o arquivo .jtl e formatar a saída como o Caliper
# Esta função usará dados hipotéticos para métricas de desempenho, pois os logs fornecidos mostram apenas falhas de conexão.
# Para um cálculo real, seria necessário um JTL com sucessos e mais complexidade na análise.
# Modificação na função process_jtl_to_caliper_format para calcular corretamente as métricas dos arquivos .jtl
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
    # Usar AWK para processar o arquivo JTL e extrair todas as métricas em uma única passagem
    # Colunas: 1=timeStamp, 2=elapsed, 8=success
    read -r success_count fail_count min_latency max_latency avg_latency send_rate throughput <<< \
    $(awk 'BEGIN {
        FS = ",";
        min_lat_ms = 999999999; # Usar um valor muito alto para min_lat_ms inicial
        max_lat_ms = 0;
        total_lat_ms = 0;
        count_success = 0;
        count_fail = 0;
        total_requests = 0;
        first_ts = 0;
        last_ts = 0;
    }
    NR > 1 { # Ignorar o cabeçalho
        timestamp = $1;
        elapsed = $2;
        success = $8;

        if (first_ts == 0) {
            first_ts = timestamp;
        }
        last_ts = timestamp; # last_ts será sempre o timestamp da última requisição processada

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
            # Converter milissegundos para segundos
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
                duration_s = "0.00"; # Se for muito rápido, pode ser 0
            }
        }
        
        send_rate = "N/A";
        throughput = "N/A";

        if (duration_s != "N/A" && duration_s > 0) {
            send_rate = sprintf("%.2f", total_requests / duration_s); # Total de requests (sucesso + falha) / duração
            if (count_success > 0) {
                throughput = sprintf("%.2f", count_success / duration_s); # Apenas requests de sucesso / duração
            } else {
                throughput = "0.00"; # Se não houver sucessos, throughput é 0
            }
        } else if (total_requests > 0) {
             # Caso a duração seja 0 ou N/A mas houve requisições, pode ser um teste muito curto.
             # Para Send Rate, podemos estimar com base em um tempo mínimo se não houver duração calculável.
             # Para throughput, se count_success for > 0, usar 0.00 para evitar divisão por zero se duration_s for 0.
             send_rate = "N/A"; # Não é possível calcular send_rate se duration_s for 0 ou N/A
             throughput = "N/A"; # Não é possível calcular throughput se duration_s for 0 ou N/A
        }


        printf "%d %d %s %s %s %s %s\n", count_success, count_fail, min_lat_s, max_lat_s, avg_lat_s, send_rate, throughput;
    }' "$jtl_file")
  fi
    
  printf "| %-8s | %-4s | %-4s | %-15s | %-15s | %-15s | %-15s | %-16s |\n" \
    "$round_name" "$success_count" "$fail_count" "$send_rate" "$max_latency" "$min_latency" "$avg_latency" "$throughput"
}

# --- INSTALAÇÃO AUTOMÁTICA DO JMETER ---
# Adicionei esta seção para verificar se o diretório do JMeter já existe.
# Se não existir, o script fará o download e a extração automática dos arquivos.
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


# --- EXECUÇÃO DOS TESTES JMETER EM SEQUÊNCIA ---
echo -e "\n--- Iniciando Testes JMeter ---"

# Executa Round 1: Open
echo -e "\nPasso 2.1: Executando Round 1: Open..."
"$JMETER_HOME/jmeter" -n -t "$JMX_OPEN" -l "results_open.jtl" -JcontractAddress="$CONTRACT_ADDRESS"
echo "Round 1 finalizado. Resultados em results_open.jtl"

# Executa Round 2: Query
echo -e "\nPasso 2.2: Executando Round 2: Query..."
"$JMETER_HOME/jmeter" -n -t "$JMX_QUERY" -l "results_query.jtl" -JcontractAddress="$CONTRACT_ADDRESS"
echo "Round 2 finalizado. Resultados em results_query.jtl"

# Executa Round 3: Transfer
echo -e "\nPasso 2.3: Executando Round 3: Transfer..."
"$JMETER_HOME/jmeter" -n -t "$JMX_TRANSFER" -l "results_transfer.jtl" -JcontractAddress="$CONTRACT_ADDRESS"
echo "Round 3 finalizado. Resultados em results_transfer.jtl"

echo -e "\n--- Sumário de todos os testes JMeter (Formato Caliper) ---"
echo "+----------+------+------+-----------------+-----------------+-----------------+-----------------+------------------+"
echo "| Name     | Succ | Fail | Send Rate (TPS) | Max Latency (s) | Min Latency (s) | Avg Latency (s) | Throughput (TPS) |"
echo "+----------+------+------+-----------------+-----------------+-----------------+-----------------+------------------+"
process_jtl_to_caliper_format "results_open.jtl" "open"
process_jtl_to_caliper_format "results_query.jtl" "query"
process_jtl_to_caliper_format "results_transfer.jtl" "transfer"
echo "+----------+------+------+-----------------+-----------------+-----------------+-----------------+------------------+"

echo -e "\nTodos os testes do JMeter foram concluídos com sucesso!"