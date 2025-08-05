#!/bin/bash

# --- CONFIGURAÇÕES ---
# Caminho para o arquivo de configuração do benchmark do Caliper
CALIPER_BENCHCONFIG="$(pwd)5_Users/caliper/simple/config.yaml"
# Define o diretório base do projeto para caminhos absolutos
CALIPER_NETWORKCONFIG="$(pwd)/../meu-contrato/networkconfig.json"
# Workspace do Caliper
CALIPER_WORKSPACE="."
# Arquivo para salvar o endereço do contrato
CONTRACT_ADDRESS_FILE="../besu-production-docker/testes/contract_address.txt"

# === NOVA CONFIGURAÇÃO PARA EXECUÇÕES MÚLTIPLAS ===
# Número de repetições. Padrão para 1 se nenhum argumento for fornecido.
NUM_REPETITIONS=${1:-1}
# Diretório para logs individuais de cada execução do Caliper
TESTE_DIR="$(pwd)"
CALIPER_RUNS_DIR="$TESTE_DIR/caliper_runs"

# Limpa o diretório de execuções anteriores e cria um novo
rm -rf "$CALIPER_RUNS_DIR"
mkdir -p "$CALIPER_RUNS_DIR"

echo "Iniciando a execução do Caliper por $NUM_REPETITIONS vezes."
echo "Resultados detalhados de cada execução serão salvos em: $CALIPER_RUNS_DIR"
echo "As métricas de recursos (CPU, Memória) estarão no relatório HTML gerado pelo Caliper."

# --- EXECUÇÃO EM LOOP ---
# MODIFICAÇÃO: Armazena o diretório original para poder voltar a ele
ORIGINAL_DIR=$(pwd)
cd "../../caliper-benchmarks"

# Instalação e bind do Caliper (movido para fora do loop para ser executado apenas uma vez)
echo "Instalando dependências do Caliper e fazendo o bind do SUT..."
npm install --only=prod @hyperledger/caliper-cli
npx caliper bind --caliper-bind-sut besu:latest

for (( i=1; i<=$NUM_REPETITIONS; i++ ))
do
    echo -e "\n--- Execução do Caliper #$i de $NUM_REPETITIONS ---"

    # Define o arquivo de log para a execução atual
    CURRENT_CALIPER_LOG="$CALIPER_RUNS_DIR/caliper_log_run_${i}.txt"

    echo "Executando Caliper..."
    # MODIFICAÇÃO: Removido o /usr/bin/time -v. As métricas de recursos virão do monitor nativo do Caliper.
    # O log da execução será salvo no ficheiro de log. O relatório HTML terá os detalhes de performance.
    sudo npx caliper launch manager \
        --caliper-benchconfig "$CALIPER_BENCHCONFIG" \
        --caliper-networkconfig "$CALIPER_NETWORKCONFIG" \
        --caliper-workspace "$CALIPER_WORKSPACE" \
        --caliper-report-path "$CALIPER_RUNS_DIR/report_run_${i}.html" > "$CURRENT_CALIPER_LOG" 2>&1

    CALIPER_EXIT_STATUS=$?

    if [ "$CALIPER_EXIT_STATUS" -ne 0 ]; then
        echo "Erro: A execução do Caliper #$i falhou. Verifique $CURRENT_CALIPER_LOG para detalhes."
    else
        echo "Caliper Run #$i finalizado. Log salvo em $CURRENT_CALIPER_LOG."
        echo "Relatório de performance e recursos salvo em $CALIPER_RUNS_DIR/report_run_${i}.html"

        # Extração e armazenamento do endereço do contrato APENAS NA PRIMEIRA EXECUÇÃO BEM-SUCEDIDA
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
done

# Retorna ao diretório original
cd "$ORIGINAL_DIR"

echo -e "\nExecução do Caliper concluída!"
echo "Verifique os relatórios HTML gerados no diretório: $CALIPER_RUNS_DIR/"