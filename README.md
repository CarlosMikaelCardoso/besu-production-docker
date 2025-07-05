# Hyperledger Besu - Rede QBFT Permissionada para Produção (Versão Corrigida)

Este guia descreve a configuração de uma rede permissionada utilizando o mecanismo de consenso QBFT (QBFT Consensus Protocol) do Hyperledger Besu. Esta versão foi corrigida e atualizada para garantir que a rede funcione corretamente em um ambiente de máquina única, resolvendo problemas comuns de conexão e permissão.

## Pré-requisitos
Certifique-se de ter as seguintes ferramentas instaladas:

* Java
* Besu v24.7.0
* cURL, wget, tar
* Docker e Docker-Compose
* Node.js e npm (para implantar contratos)

## Instalação das Dependências

### Besu
> [!IMPORTANT]
> <sup>Estamos utilizando a versão 24.7.0 do Besu. Para utilizar outra versão, altere a URL de download e atualize as variáveis de ambiente conforme necessário.</sup>

```bash
wget https://github.com/hyperledger/besu/releases/download/24.7.0/besu-24.7.0.tar.gz || https://github.com/hyperledger/besu/releases/download/24.7.0/besu-24.7.0.tar.gz
tar -xvf besu-24.7.0.tar.gz 
rm besu-24.7.0.tar.gz 
export PATH=$(pwd)/besu-24.7.0/bin:$PATH
```

### JAVA
> [!IMPORTANT]
> <sup>Certifique-se de que o diretório `jdk-21.0.7/` foi extraído corretamente na raiz do projeto.</sup>

```bash
wget https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.tar.gz || https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.tar.gz
tar -xvf jdk-21_linux-x64_bin.tar.gz
rm jdk-21_linux-x64_bin.tar.gz
export JAVA_HOME=$(pwd)/jdk-21.0.7
```

Para verificar a versão instalada:
```bash
besu --version
```

## Etapa 1: Geração de Chaves e Ficheiros de Configuração

### 1. Corrija o Script de Geração de Configuração
Antes de tudo, é **crucial** que o IP no script de geração corresponda ao ambiente onde os nós serão executados. Para uma configuração local, use `127.0.0.1`.

* **Edite o ficheiro `generate-nodes-config.sh`**:
    ```sh
    # No ficheiro generate-nodes-config.sh
    IP="127.0.0.1" # <<<<<<<< GARANTA QUE ESTE IP ESTÁ CORRETO
    ```

### 2. Gere os Ficheiros da Blockchain e Chaves
```bash
besu operator generate-blockchain-config \
  --config-file=genesis_QBFT.json \
  --to=networkFiles \
  --private-key-file-name=key
```

### 3. Copie o Ficheiro `genesis.json`
```bash
cp networkFiles/genesis.json ./
```

### 4. Gere e Corrija o Ficheiro de Permissões
Execute o script agora corrigido:
```bash
chmod +x generate-nodes-config.sh
./generate-nodes-config.sh
```

## Etapa 2: Execução da Rede

### 1. Construa a Imagem Docker
```bash
docker build --no-cache -f Dockerfile -t besu-image-local:1.0 .
```

### 2. Configure os Bootnodes no `docker-compose.yaml`
Este é o passo mais crítico para a rede funcionar. Você precisa dizer aos nós como se encontrarem.

* **Primeiro, inicie a rede temporariamente para obter os `enodes`**:
    ```bash
    sudo docker-compose up -d
    ```
* **Edite o `docker-compose.yaml`**:
    python3 update_docker_compose.py
    Use os `enodes` do `Node-1` e `Node-3` que você obteve e coloque-os na opção `--bootnodes` para os nós **2, 3, 4, 5 e 6**.
* **Derrube a rede temporária**:
    ```bash
    sudo docker-compose down
    ```

### 3. Inicialize a Rede Corretamente
Com o `docker-compose.yaml` corrigido, suba a rede:
```bash
sudo docker-compose up -d
```

## Etapa 3: Validação do Estado da Rede
Use os comandos abaixo para validar se a rede está saudável.

* **Verifique a contagem de pares (o mais importante!)**:
    ```bash
    curl -X POST --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' http://127.0.0.1:8545 | jq
    ```
    *O resultado deve ser `"0x5"` (5 pares).*

* **Verifique se os blocos estão a ser produzidos**:
    ```bash
    curl -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://127.0.0.1:8545 http://127.0.0.1:8545 | jq
    ```
    *Execute algumas vezes; o número do bloco deve aumentar.*

## Etapa 4: Implantando um Smart Contract (Exemplo com Hardhat)

1.  **Crie um projeto Hardhat**:
    ```bash
    npm init -y && npm install --save-dev hardhat && npx hardhat
    ```
2.  **Instale as ferramentas**:
    ```bash
    npm install --save-dev @nomicfoundation/hardhat-toolbox
    ```
3.  **Crie seu contrato** em `contracts/MyContract.sol`.
4.  **Configure a rede** no `hardhat.config.js`:
    ```javascript
    require("@nomicfoundation/hardhat-toolbox");

    /** @type import('hardhat/config').HardhatUserConfig */
    module.exports = {
      solidity: "0.8.28",
      networks: {
        besu: {
          url: "http://127.0.0.1:8545",
          accounts: ['SUA_CHAVE_PRIVADA_AQUI'] // Use a chave privada da conta em genesis_QBFT.json
        }
      }
    };
    ```
5.  **Crie um script de implantação** em `scripts/deploy.js`.
6.  **Execute a implantação**:
    ```bash
    npx hardhat run scripts/deploy.js --network besu

> [!IMPORTANT]
> **Adicione Contas Externas**
> O script acima só adiciona as contas dos validadores à lista de permissões. Para implantar contratos, você precisa adicionar a sua conta de implantação.
>
> 1.  **Edite o ficheiro `./Permissioned-Network/permissions_config.toml`**:
>     ```toml
>     accounts-allowlist=[
>       "0x<account-id-node-1>",
>       ...
>       "0x<account-id-node-6>", 
>       "0xfe3b557e8fb62b89f4916b721be55ceb828dbd73" # Adicione sua conta externa aqui
>     ]
>     ```
> 2.  **Copie o ficheiro atualizado para todos os nós**:
>     ```bash
>     for i in $(seq 1 6); do
>         cp ./Permissioned-Network/permissions_config.toml ./Permissioned-Network/Node-$i/data/
>     done
>     ```
