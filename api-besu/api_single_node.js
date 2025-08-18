// Exporta as variáveis de ambiente necessárias para a configuração do Besu.
// export BESU_RPC_URL="http://localhost:8545"
// export DEPLOYER_PRIVATE_KEY="0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63"
// export CONTRACT_ADDRESS="0x7189F6Ca8e6f009BA77d3bf622C756f811034d26"

// --- Importações ---
const express = require('express');
const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
const os = require('os');
const Docker = require('dockerode');

// --- Configuração da Aplicação ---
const app = express();
const port = 3000;

app.use(express.json());
app.use((err, req, res, next) => {
    console.error("Ocorreu um erro não tratado:", err.stack);
    // Se a resposta ainda não foi enviada, envia uma resposta de erro JSON
    if (!res.headersSent) {
        res.status(500).json({
            error: "Erro interno do servidor.",
            details: err.message
        });
    }
});

// --- Configuração do Ethers e Variáveis de Ambiente ---
const { DEPLOYER_PRIVATE_KEY, CONTRACT_ADDRESS, BESU_RPC_URL } = process.env;

if (!DEPLOYER_PRIVATE_KEY || !CONTRACT_ADDRESS) {
    console.error("Erro Crítico: As variáveis de ambiente DEPLOYER_PRIVATE_KEY e CONTRACT_ADDRESS são obrigatórias.");
    process.exit(1);
}

const provider = new ethers.JsonRpcProvider(BESU_RPC_URL || "http://localhost:8545");
const signer = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

const CONTRACT_ABI = [
    { "constant": false, "inputs": [ { "internalType": "string", "name": "acc_from", "type": "string" }, { "internalType": "string", "name": "acc_to", "type": "string" }, { "internalType": "int256", "name": "amount", "type": "int256" } ], "name": "transfer", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
    { "constant": true, "inputs": [ { "internalType": "string", "name": "acc_id", "type": "string" } ], "name": "query", "outputs": [ { "internalType": "int256", "name": "amount", "type": "int256" } ], "stateMutability": "view", "type": "function" },
    { "constant": false, "inputs": [ { "internalType": "string", "name": "acc_id", "type": "string" }, { "internalType": "int256", "name": "amount", "type": "int256" } ], "name": "open", "outputs": [], "stateMutability": "nonpayable", "type": "function" }
];

// Conecta-se apenas a um nó Besu
const BESU_RPC_URL = process.env.BESU_RPC_URL || "http://localhost:8545";
const provider = new ethers.JsonRpcProvider(BESU_RPC_URL);
// const signer = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);
// const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);

const wallets = JSON.parse(fs.readFileSync(path.join(__dirname, 'wallets.json'), 'utf-8'));

class NonceManager {
    constructor(signer) {
        this.signer = signer;
        this.noncePromise = signer.getNonce("pending");
    }
    async send(transactionPromise) {
        const nonce = await this.noncePromise;
        this.noncePromise = Promise.resolve(nonce + 1);
        try {
            const tx = await transactionPromise({ nonce });
            return tx;
        } catch (error) {
            if (error.code === 'NONCE_EXPIRED' || error.code === 'REPLACEMENT_UNDERPRICED') {
                 console.error(`(Worker ${this.signer.address}) Nonce dessincronizado. A reiniciar contagem.`);
                 this.noncePromise = this.signer.getNonce("pending");
            }
            throw error;
        }
    }
}

// Cria um "worker" para cada carteira. Cada worker tem seu próprio signer e nonce manager.
const workerPool = wallets.map(walletInfo => {
    const signer = new ethers.Wallet(walletInfo.privateKey, provider);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);
    return {
        address: signer.address,
        signer: signer,
        contract: contract, // Cada signer precisa de sua própria instância de contrato
        nonceManager: new NonceManager(signer)
    };
});

let nextWorkerIndex = 0; // Usado para distribuir as requisições em round-robin
console.log(`✅ Pool de alta performance inicializado com ${workerPool.length} workers.`);

// Contadores de transações para logging
let openTxCount = 1;
let transferTxCount = 1;

// --- Lógica de Monitoramento do Docker ---
const monitoringProcesses = {};
const DOCKER_CONTAINERS_TO_MONITOR = ["node1", "node2", "node3", "node4", "node5", "node6"];
const LOG_DIR = path.join(os.tmpdir(), 'jmeter_docker_logs');
if (!fs.existsSync(LOG_DIR)) {
    fs.mkdirSync(LOG_DIR, { recursive: true });
}

app.post('/monitor/start', (req, res) => {
    const { roundName, runNumber } = req.body;
    const runId = `${roundName}_run_${runNumber}`;
    const logPath = path.join(LOG_DIR, `docker_stats_${runId}.log`);

    if (monitoringProcesses[runId]) {
        return res.status(409).json({ message: `O monitoramento para ${runId} já está em execução.` });
    }

    console.log(`Iniciando monitoramento para: ${runId}. A gravar em: ${logPath}`);
    const logStream = fs.createWriteStream(logPath, { flags: 'w' });

    const streams = DOCKER_CONTAINERS_TO_MONITOR.map(containerName => {
        const container = docker.getContainer(containerName);
        return new Promise((resolve, reject) => {
            container.stats({ stream: true }, (err, stream) => {
                if (err) return reject(err);

                stream.on('data', (chunk) => {
                    const stats = JSON.parse(chunk.toString());
                    const cpuDelta = stats.cpu_stats.cpu_usage.total_usage - stats.precpu_stats.cpu_usage.total_usage;
                    const systemDelta = stats.cpu_stats.system_cpu_usage - stats.precpu_stats.system_cpu_usage;
                    const cpuCount = stats.cpu_stats.online_cpus || stats.cpu_stats.cpu_usage.percpu_usage.length;
                    let cpuPercent = 0.0;
                    if (systemDelta > 0.0 && cpuDelta > 0.0) {
                        cpuPercent = (cpuDelta / systemDelta) * cpuCount * 100.0;
                    }
                    const memUsage = (stats.memory_stats.usage / (1024 * 1024)).toFixed(2);
                    let netRx = 0, netTx = 0, diskRead = 0, diskWrite = 0;
                    if (stats.networks) {
                        Object.values(stats.networks).forEach(net => { netRx += net.rx_bytes; netTx += net.tx_bytes; });
                    }
                    if (stats.blkio_stats && stats.blkio_stats.io_service_bytes_recursive) {
                        stats.blkio_stats.io_service_bytes_recursive.forEach(io => {
                            if (io.op === 'Read') diskRead += io.value;
                            if (io.op === 'Write') diskWrite += io.value;
                        });
                    }
                    const netRxKB = (netRx / 1024).toFixed(2);
                    const netTxKB = (netTx / 1024).toFixed(2);
                    const diskReadKB = (diskRead / 1024).toFixed(2);
                    const diskWriteKB = (diskWrite / 1024).toFixed(2);
                    const logLine = `${stats.name.substring(1)},${cpuPercent.toFixed(2)}%,${memUsage}MiB,${netRxKB}KB,${netTxKB}KB,${diskReadKB}KB,${diskWriteKB}KB\n`;
                    logStream.write(logLine);
                });

                stream.on('end', resolve);
                stream.on('error', reject);

                monitoringProcesses[runId] = monitoringProcesses[runId] || {};
                monitoringProcesses[runId][containerName] = stream;
            });
        });
    });

    Promise.all(streams).catch(err => console.error(`Erro ao iniciar stream de stats: ${err}`));
    res.status(202).json({ message: `Monitoramento para ${runId} iniciado.` });
});

app.post('/monitor/stop', (req, res) => {
    const { roundName, runNumber } = req.body;
    const runId = `${roundName}_run_${runNumber}`;
    const processInfo = monitoringProcesses[runId];
    if (processInfo) {
        console.log(`Parando monitoramento para: ${runId}`);
        for (const containerName in processInfo) {
            if (processInfo[containerName] && typeof processInfo[containerName].destroy === 'function') {
                processInfo[containerName].destroy();
            }
        }
        delete monitoringProcesses[runId];
        res.status(200).json({ message: `Monitoramento para ${runId} parado.` });
    } else {
        res.status(404).json({ message: `Nenhum processo de monitoramento encontrado para ${runId}.` });
    }
});

app.get('/monitor/logs/:roundName/:runNumber', (req, res) => {
    const { roundName, runNumber } = req.params;
    const runId = `${roundName}_run_${runNumber}`;
    const logPath = path.join(LOG_DIR, `docker_stats_${runId}.log`);
    if (fs.existsSync(logPath)) res.sendFile(logPath);
    else res.status(404).send('Ficheiro de log não encontrado.');
});

// --- Endpoints de Transação Síncronos ---

// MODIFICAÇÃO: Atualizado para usar o worker pool
app.post('/open', async (req, res) => {
    const worker = workerPool[nextWorkerIndex];
    nextWorkerIndex = (nextWorkerIndex + 1) % workerPool.length;
    const { nonceManager, contract } = worker;

    const { accountId, amount } = req.body;
    if (!accountId || amount === undefined) {
        return res.status(400).json({ error: "Campos 'accountId' e 'amount' são obrigatórios." });
    }
    try {
        const tx = await nonceManager.send(options => contract.open(accountId, amount, options));
        const receipt = await tx.wait();
        console.log(`(Worker ${worker.address.substring(0,10)}) Transação 'open' #${openTxCount} confirmada! Hash: ${receipt.hash}`);
        openTxCount++;
        res.status(200).json({ transactionHash: receipt.hash });
    } catch (error) {
        console.error(`(Worker ${worker.address}) Erro 'open' para conta ${accountId}:`, error);
        res.status(500).json({ error: "Falha ao confirmar a transação 'open'.", details: error.message });
    }
});

// MODIFICAÇÃO: Atualizado para usar o worker pool
app.post('/transfer', async (req, res) => {
    const worker = workerPool[nextWorkerIndex];
    nextWorkerIndex = (nextWorkerIndex + 1) % workerPool.length;
    const { nonceManager, contract } = worker;

    const { from, to, amount } = req.body;
    if (!from || !to || amount === undefined) {
        return res.status(400).json({ error: "Os campos 'from', 'to' e 'amount' são obrigatórios." });
    }
    try {
        const tx = await nonceManager.send(options => contract.transfer(from, to, amount, options));
        const receipt = await tx.wait();
        console.log(`(Worker ${worker.address.substring(0,10)}) Transação 'transfer' #${transferTxCount} confirmada! Hash: ${receipt.hash}`);
        transferTxCount++;
        res.status(200).json({ transactionHash: receipt.hash });
    } catch (error) {
        console.error(`(Worker ${worker.address}) Erro 'transfer' de ${from} para ${to}:`, error);
        res.status(500).json({ error: "Falha ao confirmar a transação 'transfer'.", details: error.message });
    }
});

app.get('/query/:accountId', async (req, res) => {
    try {
        const accountId = req.params.accountId;
        const balance = await contract.query(accountId);
        console.log(`Consulta para conta: ${accountId}, Saldo encontrado: ${balance.toString()}`);
        res.status(200).json({ accountId: accountId, balance: balance.toString() });
    } catch (error) {
        console.error(`Falha ao executar 'query' para a conta ${req.params.accountId}:`, error);
        res.status(500).json({ error: "Falha ao executar a função 'query'.", details: error.message });
    }
});

// --- Endpoint de Recibo de Transação ---

app.get('/receipt/:txHash', async (req, res) => {
    try {
        const { txHash } = req.params;
        if (!txHash || !/^0x([A-Fa-f0-9]{64})$/.test(txHash)) {
            return res.status(400).json({ status: 'error', message: 'Formato de hash de transação inválido.' });
        }

        const receipt = await provider.getTransactionReceipt(txHash);

        if (receipt) {
            res.status(200).json({ 
                status: 'confirmed', 
                receipt: {
                    transactionHash: receipt.transactionHash,
                    blockNumber: receipt.blockNumber.toString(),
                    gasUsed: receipt.gasUsed.toString(),
                    status: receipt.status
                }
            });
        } else {
            res.status(202).json({ status: 'pending' });
        }
    } catch (error) {
        console.error(`Erro ao obter o recibo para ${req.params.txHash}:`, error);
        res.status(500).json({ status: 'error', message: 'Erro interno ao buscar recibo da transação.' });
    }
});

// --- Endpoints de Transação Assíncronos ---

app.post('/open-async', async (req, res) => {
    // 1. Pega o próximo worker do pool (distribuição round-robin)
    const worker = workerPool[nextWorkerIndex];
    nextWorkerIndex = (nextWorkerIndex + 1) % workerPool.length;

    // 2. Extrai o nonceManager e o contrato específicos deste worker
    const { nonceManager, contract } = worker;

    const { accountId, amount } = req.body;
    if (!accountId || amount === undefined) {
        return res.status(400).json({ error: "Campos 'accountId' e 'amount' são obrigatórios." });
    }
    try {
        // 3. Usa o nonceManager do worker para enviar a transação
        const txResponse = await nonceManager.send(options => contract.open(accountId, amount, options));
        console.log(`(Worker ${worker.address.substring(0, 10)}...) Transação 'open' submetida. Hash: ${txResponse.hash}`);
        res.status(202).json({ message: `Transação 'open' aceite para processamento.`, transactionHash: txResponse.hash });
    } catch (error) {
        console.error(`(Worker ${worker.address}) Erro ao submeter transação 'open' para ${accountId}:`, error);
        res.status(500).json({ error: "Falha ao submeter a transação 'open'.", details: error.message });
    }
});

// MODIFICAÇÃO: Adicionada a extração das variáveis do req.body
app.post('/transfer-async', async (req, res) => {
    const worker = workerPool[nextWorkerIndex];
    nextWorkerIndex = (nextWorkerIndex + 1) % workerPool.length;
    const { nonceManager, contract } = worker;

    // A linha abaixo estava em falta
    const { from, to, amount } = req.body; 

    if (!from || !to || amount === undefined) {
        return res.status(400).json({ error: "Os campos 'from', 'to' e 'amount' são obrigatórios." });
    }
    try {
        const txResponse = await nonceManager.send(options => contract.transfer(from, to, amount, options));
        console.log(`(Worker ${worker.address.substring(0,10)}) Transação 'transfer-async' submetida. Hash: ${txResponse.hash}`);
        res.status(202).json({ message: "Transação 'transfer' aceite para processamento.", transactionHash: txResponse.hash });
    } catch (error) {
        console.error(`(Worker ${worker.address}) Erro 'transfer-async' de ${from} para ${to}:`, error);
        res.status(500).json({ error: "Falha ao submeter a transação 'transfer'.", details: error.message });
    }
});

// --- Iniciar o Servidor ---
app.listen(port, () => {
    console.log(`Servidor da API a correr em http://localhost:${port}`);
    console.log(`A API está a enviar todos os pedidos para: ${BESU_RPC_URL || "http://localhost:8545"}`);
    console.log(`Usando contrato no endereço: ${CONTRACT_ADDRESS}`);
});