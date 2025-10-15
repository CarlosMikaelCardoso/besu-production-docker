#!/bin/bash

# --- CONFIGURAÇÕES ---
NUM_USERS=${1:-5}
NUM_REPETITIONS=${2:-1}

# --- Adicione o IP da sua VM do Besu aqui ---
export DOCKER_HOST="tcp://"$(hostname -I | awk '{print $1}')":2375"

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

CALIPER_BENCHCONFIG="$(pwd)/${NUM_USERS}_Users/caliper/simple/config.yaml"
CALIPER_NETWORKCONFIG="$(pwd)/networkconfig.json"
CALIPER_WORKSPACE="."
CONTRACT_ADDRESS_FILE="$(pwd)/contract_address.txt"
TESTE_DIR="$(pwd)"
CALIPER_RUNS_DIR="$TESTE_DIR/caliper_runs_${NUM_USERS}_users"

rm -rf "$CALIPER_RUNS_DIR"
mkdir -p "$CALIPER_RUNS_DIR"

echo "Iniciando a execução do Caliper com $NUM_USERS usuários por $NUM_REPETITIONS vez(es)."
echo "Resultados detalhados de cada execução serão salvos em: $CALIPER_RUNS_DIR"

# --- FUNÇÃO DE VERIFICAÇÃO ---
wait_for_besu_nodes() {
    echo "A aguardar que a porta WebSocket do Besu (8645) fique disponível..."
    local node_host=$(hostname -I | awk '{print $1}') # Use o IP da VM do Besu aqui
    local ws_port="8645"
    local timeout=120
    local start_time=$(date +%s)

    if ! command -v nc &> /dev/null; then
        echo "Erro: O comando 'nc' (netcat) não foi encontrado. Por favor, instale-o."
        exit 1
    fi

    while true; do
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))

        if [ $elapsed_time -ge $timeout ]; then
            echo "Erro: Timeout à espera da porta WebSocket do Besu."
            exit 1
        fi

        if nc -z "$node_host" "$ws_port"; then
            echo "Porta WebSocket do Besu está ativa. A continuar em 5 segundos..."
            sleep 5
            break
        fi
        
        echo -n "."
        sleep 2
    done
}

# --- EXECUÇÃO ---
ORIGINAL_DIR=$(pwd)

cd "../../caliper-benchmarks"
echo "Instalando dependências do Caliper e fazendo o bind do SUT..."
npm install --only=prod @hyperledger/caliper-cli > /dev/null 2>&1
npx caliper bind --caliper-bind-sut besu:latest > /dev/null 2>&1
cd "$ORIGINAL_DIR"

wait_for_besu_nodes

cd "../../caliper-benchmarks"
for (( i=1; i<=$NUM_REPETITIONS; i++ ))
do
    echo -e "\n--- Execução do Caliper #$i de $NUM_REPETITIONS ---"
    CURRENT_CALIPER_LOG="$CALIPER_RUNS_DIR/caliper_log_run_${i}.txt"

    echo "Executando Caliper..."
    # O sudo não é mais necessário aqui, pois o DOCKER_HOST cuida da conexão
    npx caliper launch manager \
        --caliper-benchconfig "$CALIPER_BENCHCONFIG" \
        --caliper-networkconfig "$CALIPER_NETWORKCONFIG" \
        --caliper-workspace "$CALIPER_WORKSPACE" \
        --caliper-report-path "$CALIPER_RUNS_DIR/report_run_${i}.html" > "$CURRENT_CALIPER_LOG" 2>&1

    CALIPER_EXIT_STATUS=$?

    if [ "$CALIPER_EXIT_STATUS" -ne 0 ]; then
        echo "Erro: A execução do Caliper #$i falhou. Verifique $CURRENT_CALIPER_LOG para detalhes."
    else
        echo "Caliper Run #$i finalizado. Log salvo em $CURRENT_CALIPER_LOG."
        echo "Relatório de performance salvo em $CALIPER_RUNS_DIR/report_run_${i}.html"

        if [ "$i" -eq 1 ]; then
            grep -o -E "0x[a-fA-F0-9]{40}" "$CURRENT_CALIPER_LOG" | head -n 1 > "$CONTRACT_ADDRESS_FILE"
            if [ -s "$CONTRACT_ADDRESS_FILE" ]; then
                SAVED_ADDRESS=$(<"$CONTRACT_ADDRESS_FILE")
                echo "Endereço do contrato ($SAVED_ADDRESS) salvo em $CONTRACT_ADDRESS_FILE."
            else
                echo "Erro: Não foi possível extrair o endereço do contrato do log."
            fi
        fi
    fi
done

cd "$ORIGINAL_DIR"
python3 generateGraphsCaliper.py "$CALIPER_RUNS_DIR" "$NUM_REPETITIONS"

echo -e "\nExecução do Caliper concluída!"
echo "Verifique os relatórios HTML gerados no diretório: $CALIPER_RUNS_DIR/"
