#!/bin/bash

# --- CONFIGURAÇÕES ---
# Caminho para o arquivo de configuração do benchmark do Caliper
CALIPER_BENCHCONFIG="benchmarks/scenario/simple/config.yaml"
# Caminho para o arquivo de configuração de rede do Caliper
CALIPER_NETWORKCONFIG="networks/besu/1node-clique/networkconfig.json"
# Workspace do Caliper
CALIPER_WORKSPACE="."
# Arquivo de log do Caliper
CALIPER_LOG="caliper_log.txt"
# Arquivo para salvar o endereço do contrato
CONTRACT_ADDRESS_FILE="contract_address.txt"

# --- EXECUÇÃO ---

echo "Passo 1: Executando o Caliper para deploy do contrato e testes..."
cd ../caliper-benchmarks
npm  install  --only=prod  @hyperledger/caliper-cli
npx caliper bind --caliper-bind-sut besu:latest
# Executa o Caliper e redireciona a saída para o arquivo de log
sudo npx caliper launch manager \
  --caliper-benchconfig "$CALIPER_BENCHCONFIG" \
  --caliper-networkconfig "$CALIPER_NETWORKCONFIG" \
  --caliper-workspace "$CALIPER_WORKSPACE" > "$CALIPER_LOG"

# Verifica se o Caliper foi executado com sucesso
if [ ! -s "$CALIPER_LOG" ]; then
    echo "Erro: A execução do Caliper falhou ou não gerou log. Verifique o arquivo $CALIPER_LOG."
    exit 1
fi

echo "Caliper finalizado. Log salvo em $CALIPER_LOG."

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