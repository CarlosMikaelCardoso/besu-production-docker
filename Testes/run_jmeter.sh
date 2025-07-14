#!/bin/bash

# --- CONFIGURAÇÕES ---
JMETER_VERSION="5.6.3"
JMETER_DIR="apache-jmeter-${JMETER_VERSION}"
JMETER_URL="https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz"
CONTRACT_ADDRESS_FILE="contract_address.txt"

# Caminhos para os planos de teste
JMX_OPEN="test_round1_open.jmx"
JMX_QUERY="test_round2_query.jmx"
JMX_TRANSFER="test_round3_transfer.jmx"


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


echo -e "\nTodos os testes do JMeter foram concluídos com sucesso!"