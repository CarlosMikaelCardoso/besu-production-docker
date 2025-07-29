#!/bin/bash

# --- CONFIGURAÇÕES ---
# Caminho para o arquivo de configuração do benchmark do Caliper
CALIPER_BENCHCONFIG="benchmarks/scenario/simple/config.yaml"
# Caminho para o arquivo de configuração de rede do Caliper
CALIPER_NETWORKCONFIG="$(pwd)/../meu-contrato/networkconfig.json"
# Workspace do Caliper
CALIPER_WORKSPACE="."
# Arquivo de log do Caliper
CALIPER_LOG="../besu-production-docker/testes/caliper_log.txt"
# Arquivo para salvar o endereço do contrato
CONTRACT_ADDRESS_FILE="../besu-production-docker/testes/contract_address.txt"

# --- EXECUÇÃO ---

echo "Passo 1: Executando o Caliper para deploy do contrato e testes..."
cd ../../caliper-benchmarks
npm install --only=prod @hyperledger/caliper-cli
npx caliper bind --caliper-bind-sut besu:latest

# Cria um arquivo temporário para as métricas de uso de recursos do Caliper
CALIPER_RESOURCE_METRICS_FILE="caliper_resource_metrics.txt"

# Executa o Caliper e captura o uso de recursos usando /usr/bin/time -v.
# A saída padrão do Caliper vai para CALIPER_LOG.
# A saída de erro do time (que contém as métricas) vai para CALIPER_RESOURCE_METRICS_FILE.
/usr/bin/time -v sudo npx caliper launch manager \
  --caliper-benchconfig "$CALIPER_BENCHCONFIG" \
  --caliper-networkconfig "$CALIPER_NETWORKCONFIG" \
  --caliper-workspace "$CALIPER_WORKSPACE" > "$CALIPER_LOG" 2> "$CALIPER_RESOURCE_METRICS_FILE"

# Verifica se a execução do Caliper foi bem-sucedida (baseado no código de saída)
if [ $? -ne 0 ]; then
    echo "Erro: A execução do Caliper falhou. Verifique o arquivo $CALIPER_LOG para detalhes."
    # Anexa as métricas de recursos mesmo em caso de falha para depuração
    echo -e "\n--- Caliper Resource Usage Summary (on error) ---" >> "$CALIPER_LOG"
    cat "$CALIPER_RESOURCE_METRICS_FILE" >> "$CALIPER_LOG"
    rm "$CALIPER_RESOURCE_METRICS_FILE" # Limpa o arquivo temporário
    exit 1
fi

# Verifica se o arquivo de log do Caliper tem conteúdo após a execução bem-sucedida
if [ ! -s "$CALIPER_LOG" ]; then
    echo "Erro: A execução do Caliper não gerou log válido. Verifique o arquivo $CALIPER_LOG."
    # Anexa as métricas de recursos de qualquer forma
    echo -e "\n--- Caliper Resource Usage Summary (log empty) ---" >> "$CALIPER_LOG"
    cat "$CALIPER_RESOURCE_METRICS_FILE" >> "$CALIPER_LOG"
    rm "$CALIPER_RESOURCE_METRICS_FILE" # Limpa o arquivo temporário
    exit 1
fi

echo "Caliper finalizado. Log salvo em $CALIPER_LOG."

# Anexa o sumário de uso de recursos ao log principal do Caliper para o relatório
echo -e "\n--- Caliper Resource Usage Summary ---" >> "$CALIPER_LOG"
cat "$CALIPER_RESOURCE_METRICS_FILE" >> "$CALIPER_LOG"
rm "$CALIPER_RESOURCE_METRICS_FILE" # Limpa o arquivo temporário

# --- EXTRAÇÃO E ARMAZENAMENTO DO ENDEREÇO DO CONTRATO ---

echo "Passo 2: Extraindo e salvando o endereço do contrato..."
# Procura por uma string hexadecimal de 42 caracteres (endereço Ethereum) e salva no arquivo
grep -o -E "0x[a-fA-F0-9]{40}" "$CALIPER_LOG" | head -n 1 > "$CONTRACT_ADDRESS_FILE"

# Verifica se o arquivo com o endereço foi criado e não está vazio
if [ ! -s "$CONTRACT_ADDRESS_FILE" ]; then
    echo "Erro: Não foi possível encontrar e salvar o endereço do contrato a partir do log."
    echo "Verifique o arquivo $CALIPER_LOG para garantir que o contrato foi implantado."
    exit 1
fi

# Lê o endereço do arquivo para exibir no console
SAVED_ADDRESS=$(<"$CONTRACT_ADDRESS_FILE")
echo "Endereço do contrato ($SAVED_ADDRESS) salvo em $CONTRACT_ADDRESS_FILE."
echo "Execução do Caliper concluída com sucesso!"