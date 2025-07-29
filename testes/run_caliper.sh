#!/bin/bash

# --- CONFIGURAÇÕES ---
# Caminho para o arquivo de configuração do benchmark do Caliper
CALIPER_BENCHCONFIG="benchmarks/scenario/simple/config.yaml"
# Define o diretório base do projeto para caminhos absolutos
# Assume que o script está em `besu-production-docker/api-besu`
# e `meu-contrato` é um irmão de `besu-production-docker`
CALIPER_NETWORKCONFIG="$(pwd)/../meu-contrato/networkconfig.json"
# Workspace do Caliper (relativo ao diretório de execução do Caliper, que será caliper-benchmarks)
CALIPER_WORKSPACE="."
# Arquivo para salvar o endereço do contrato (consolidado para todas as execuções)
CONTRACT_ADDRESS_FILE="../besu-production-docker/testes/contract_address.txt"

# === NOVA CONFIGURAÇÃO PARA EXECUÇÕES MÚLTIPLAS ===
# Número de repetições. Padrão para 1 se nenhum argumento for fornecido.
NUM_REPETITIONS=${1:-1}
# Diretório para logs individuais de cada execução do Caliper
TESTE_DIR="$(pwd)"
CALIPER_RUNS_DIR="$TESTE_DIR/caliper_runs"
# Arquivo para o sumário consolidado de recursos de todas as execuções
CALIPER_CONSOLIDATED_RESOURCE_SUMMARY_FILE="$TESTE_DIR/caliper_consolidated_resource_summary.log"

# Limpa o diretório de execuções anteriores e cria um novo
rm -rf "$CALIPER_RUNS_DIR"
mkdir -p "$CALIPER_RUNS_DIR"

# Inicializa arrays para armazenar as métricas de cada execução
declare -a max_rss_values
declare -a cpu_percent_values
declare -a user_time_values
declare -a sys_time_values

echo "Iniciando a execução do Caliper por $NUM_REPETITIONS vezes."
echo "Resultados detalhados de cada execução serão salvos em: $CALIPER_RUNS_DIR"
echo "Sumário de recursos consolidado em: $CALIPER_CONSOLIDATED_RESOURCE_SUMMARY_FILE"

# Prepara o cabeçalho para o arquivo de sumário de recursos consolidado
echo "Run,Max_RSS_KB,CPU_Percent,User_Time_Sec,Sys_Time_Sec" > "$CALIPER_CONSOLIDATED_RESOURCE_SUMMARY_FILE"

# --- EXECUÇÃO EM LOOP ---
cd "../../caliper-benchmarks"
for (( i=1; i<=$NUM_REPETITIONS; i++ ))
do
    echo -e "\n--- Execução do Caliper #$i de $NUM_REPETITIONS ---"

    # Define os arquivos de log e métricas para a execução atual
    CURRENT_CALIPER_LOG="$CALIPER_RUNS_DIR/caliper_log_run_${i}.txt"
    CURRENT_CALIPER_RESOURCE_METRICS_FILE="$CALIPER_RUNS_DIR/caliper_resource_metrics_run_${i}.txt"
    # Muda para o diretório `caliper-benchmarks` para executar o Caliper

    # Instalação e bind do Caliper (pode ser movido para fora do loop se já estiver instalado)
    npm install --only=prod @hyperledger/caliper-cli
    npx caliper bind --caliper-bind-sut besu:latest

    echo "Executando Caliper..."
    # Executa o Caliper e captura o uso de recursos usando /usr/bin/time -v.
    # A saída padrão do Caliper vai para CURRENT_CALIPER_LOG.
    # A saída de erro do time (que contém as métricas) vai para CURRENT_CALIPER_RESOURCE_METRICS_FILE.
    /usr/bin/time -v sudo npx caliper launch manager \
        --caliper-benchconfig "$CALIPER_BENCHCONFIG" \
        --caliper-networkconfig "$CALIPER_NETWORKCONFIG" \
        --caliper-workspace "$CALIPER_WORKSPACE" > "$CURRENT_CALIPER_LOG" 2> "$CURRENT_CALIPER_RESOURCE_METRICS_FILE"

    CALIPER_EXIT_STATUS=$?

    # Anexa o sumário de uso de recursos ao log individual desta execução
    echo -e "\n--- Caliper Resource Usage Summary for Run #$i ---" >> "$CURRENT_CALIPER_LOG"
    cat "$CURRENT_CALIPER_RESOURCE_METRICS_FILE" >> "$CURRENT_CALIPER_LOG"

    if [ "$CALIPER_EXIT_STATUS" -ne 0 ]; then
        echo "Erro: A execução do Caliper #$i falhou. Verifique $CURRENT_CALIPER_LOG para detalhes."
        # Continua para a próxima iteração, não sai do script.
    elif [ ! -s "$CURRENT_CALIPER_LOG" ]; then
        echo "Erro: A execução do Caliper #$i não gerou log válido. Verifique $CURRENT_CALIPER_LOG."
    else
        echo "Caliper Run #$i finalizado. Log salvo em $CURRENT_CALIPER_LOG."

        # Extrai as métricas específicas do output do time -v
        max_rss=$(grep "Maximum resident set size (kbytes):" "$CURRENT_CALIPER_RESOURCE_METRICS_FILE" | awk '{print $NF}')
        cpu_percent=$(grep "Percent of CPU this job got:" "$CURRENT_CALIPER_RESOURCE_METRICS_FILE" | awk '{print $NF}' | sed 's/%.*//') # Remove o '%'
        user_time=$(grep "User time (seconds):" "$CURRENT_CALIPER_RESOURCE_METRICS_FILE" | awk '{print $NF}')
        sys_time=$(grep "System time (seconds):" "$CURRENT_CALIPER_RESOURCE_METRICS_FILE" | awk '{print $NF}')

        # Armazena as métricas em arrays
        max_rss_values+=("$max_rss")
        cpu_percent_values+=("$cpu_percent")
        user_time_values+=("$user_time")
        sys_time_values+=("$sys_time")

        # Anexa as métricas ao arquivo de sumário de recursos consolidado
        echo "$i,$max_rss,$cpu_percent,$user_time,$sys_time" >> "$CALIPER_CONSOLIDATED_RESOURCE_SUMMARY_FILE"

        # Extração e armazenamento do endereço do contrato APENAS NA PRIMEIRA EXECUÇÃO BEM-SUCEDIDA
        # Isso garante que o CONTRACT_ADDRESS_FILE contenha o endereço do contrato implantado.
        if [ "$i" -eq 1 ]; then
            grep -o -E "0x[a-fA-F0-9]{40}" "$CURRENT_CALIPER_LOG" | head -n 1 > "$CONTRACT_ADDRESS_FILE"
            if [ ! -s "$CONTRACT_ADDRESS_FILE" ]; then
                echo "Erro: Não foi possível encontrar e salvar o endereço do contrato a partir do log da primeira execução."
                echo "Verifique o arquivo $CURRENT_CALIPER_LOG para garantir que o contrato foi implantado."
            else
                SAVED_ADDRESS=$(<"$CONTRACT_ADDRESS_FILE")
                echo "Endereço do contrato ($SAVED_ADDRESS) salvo em $CONTRACT_ADDRESS_FILE (da primeira execução)."
            fi
        fi
    fi
    # Retorna ao diretório original antes da próxima iteração
    cd "$ORIGINAL_DIR"
done

# --- SUMÁRIO CONSOLIDADO DE USO DE RECURSOS ---
echo -e "\n--- Sumário Consolidado de Uso de Recursos do Caliper (todas as execuções) ---"
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
echo "- Logs por execução: $CALIPER_RUNS_DIR/"
echo "- Sumário de recursos consolidado: $CALIPER_CONSOLIDATED_RESOURCE_SUMMARY_FILE"

echo -e "\nExecução do Caliper concluída!"