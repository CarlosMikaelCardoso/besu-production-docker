// Exporta as variáveis de ambiente necessárias para a configuração do Besu.
// export BESU_RPC_URL="http://localhost:8545"
// export DEPLOYER_PRIVATE_KEY="0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63"
// export CONTRACT_ADDRESS="0x42699A7612A82f1d9C36148af9C77354759b210b"

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

const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);

// --- Gerenciamento de Nonce ---
let noncePromise = provider.getTransactionCount(signer.getAddress(), "pending");
const resetNonce = () => {
    console.error("Nonce dessincronizado. A reiniciar a contagem de nonce.");
    noncePromise = provider.getTransactionCount(signer.getAddress(), "pending");
};

// --- Middleware para Gerenciamento de Nonce ---
app.use(['/open-async', '/transfer-async'], async (req, res, next) => {
    try {
        const nonce = await noncePromise;
        req.nonce = nonce;
        noncePromise = Promise.resolve(nonce + 1);
        next();
    } catch (error) {
        console.error("Erro ao obter o nonce:", error);
        res.status(500).json({ error: "Falha ao obter o nonce da transação.", details: error.message });
    }
});

// --- ROTAS DE TRANSAÇÃO ---

// Rota Assíncrona para 'open'
app.post('/open-async', async (req, res) => {
    const { accountId, amount } = req.body;
    if (!accountId || amount === undefined) {
        return res.status(400).json({ error: "Campos 'accountId' e 'amount' são obrigatórios." });
    }
    try {
        const txResponse = await contract.open(accountId, amount, { nonce: req.nonce });
        console.log(`(Async) Transação 'open' para a conta ${accountId} submetida. Hash: ${txResponse.hash}`);
        res.status(202).json({ message: "Transação 'open' aceite para processamento.", transactionHash: txResponse.hash });
    } catch (error) {
        console.error(`(Async) Erro ao submeter transação 'open' para ${accountId}:`, error);
        if (error.code === 'NONCE_EXPIRED') resetNonce();
        res.status(500).json({ error: "Falha ao submeter a transação 'open'.", details: error.message });
    }
});

// Rota Assíncrona para 'transfer'
app.post('/transfer-async', async (req, res) => {
    const { from, to, amount } = req.body;
    if (!from || !to || amount === undefined) {
        return res.status(400).json({ error: "Os campos 'from', 'to' e 'amount' são obrigatórios." });
    }
    try {
        const txResponse = await contract.transfer(from, to, amount, { nonce: req.nonce });
        console.log(`(Async) Transação 'transfer' de ${from} para ${to} submetida. Hash: ${txResponse.hash}`);
        res.status(202).json({ message: "Transação 'transfer' aceite para processamento.", transactionHash: txResponse.hash });
    } catch (error) {
        console.error(`(Async) Erro ao submeter transação 'transfer' de ${from} para ${to}:`, error);
        if (error.code === 'NONCE_EXPIRED') resetNonce();
        res.status(500).json({ error: "Falha ao submeter a transação 'transfer'.", details: error.message });
    }
});

// Rota Síncrona para 'query'
app.get('/query/:accountId', async (req, res) => {
    try {
        const { accountId } = req.params;
        const balance = await contract.query(accountId);
        res.status(200).json({ accountId, balance: balance.toString() });
    } catch (error) {
        console.error(`Falha ao executar 'query' para a conta ${req.params.accountId}:`, error);
        res.status(500).json({ error: "Falha ao executar a função 'query'.", details: error.message });
    }
});

// Rota para verificar Recibo da Transação
app.get('/receipt/:txHash', async (req, res) => {
    try {
        const { txHash } = req.params;
        const receipt = await provider.getTransactionReceipt(txHash);
        if (receipt) {
            res.status(200).json({ status: 'confirmed', receipt });
        } else {
            res.status(202).json({ status: 'pending' });
        }
    } catch (error) {
        console.error(`Falha ao buscar recibo para o hash ${req.params.txHash}:`, error);
        res.status(500).json({ error: "Falha ao buscar o recibo da transação.", details: error.message });
    }
});

// --- LÓGICA DE MONITORAMENTO DO DOCKER ---
const docker = new Docker();
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
                    const logLine = `${stats.name.substring(1)},${cpuPercent.toFixed(2)}%,${memUsage}MiB,${(netRx / 1024).toFixed(2)}KB,${(netTx / 1024).toFixed(2)}KB,${(diskRead / 1024).toFixed(2)}KB,${(diskWrite / 1024).toFixed(2)}KB\n`;
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


// --- Inicialização do Servidor ---
app.listen(port, () => {
    console.log(`Servidor da API a correr em http://localhost:${port}`);
    console.log(`A API está a enviar todos os pedidos para: ${BESU_RPC_URL || "http://localhost:8545"}`);
    console.log(`Usando contrato no endereço: ${CONTRACT_ADDRESS}`);
});