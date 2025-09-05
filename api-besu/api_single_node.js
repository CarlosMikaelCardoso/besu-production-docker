// Exporta as variáveis de ambiente necessárias para a configuração do Besu.
// export BESU_RPC_URL="http://localhost:8545"
// export DEPLOYER_PRIVATE_KEY="0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63"
// export CONTRACT_ADDRESS="0x65276fE40CdA3B0A0b466e3e61ea6d822b5aEC0f"

const express = require('express');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const Docker = require('dockerode');
const docker = new Docker();
const { ethers } = require('ethers');

// --- MODIFICAÇÃO: Importar as classes de workload refatoradas ---
const OpenWorkload = require('./workloads/open.js');
const QueryWorkload = require('./workloads/query.js');
const TransferWorkload = require('./workloads/transfer.js');
// ----------------------------------------------------------------

const app = express();
const port = 3000;
app.use(express.json());

// --- Configuração das Variáveis de Ambiente ---
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS;
const BESU_RPC_URL = process.env.BESU_RPC_URL || "http://localhost:8545";

if (!DEPLOYER_PRIVATE_KEY || !CONTRACT_ADDRESS) {
    console.error("Erro Crítico: As variáveis de ambiente DEPLOYER_PRIVATE_KEY e CONTRACT_ADDRESS são obrigatórias.");
    process.exit(1);
}

// --- MODIFICAÇÃO: Instanciar as classes de workload com as configurações ---
const openWorkload = new OpenWorkload(BESU_RPC_URL, DEPLOYER_PRIVATE_KEY, CONTRACT_ADDRESS);
const queryWorkload = new QueryWorkload(BESU_RPC_URL, DEPLOYER_PRIVATE_KEY, CONTRACT_ADDRESS);
const transferWorkload = new TransferWorkload(BESU_RPC_URL, DEPLOYER_PRIVATE_KEY, CONTRACT_ADDRESS);
// -------------------------------------------------------------------------
// --- Lógica de Monitoramento do Docker (sem alterações) ---
const monitoringProcesses = {};
const DOCKER_CONTAINERS_TO_MONITOR = ["node1", "node2", "node3", "node4", "node5", "node6"];
const LOG_DIR = path.join(os.tmpdir(), 'jmeter_docker_logs');
if (!fs.existsSync(LOG_DIR)) {
    fs.mkdirSync(LOG_DIR, { recursive: true });
}

let noncePromise;
let signerAddress; // Variável para guardar o endereço

try {
    const provider = new ethers.JsonRpcProvider(BESU_RPC_URL);
    const signer = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);
    signerAddress = signer.address; // Guardamos o endereço do signer

    // A forma correta em ethers.js v6: chama-se getTransactionCount no provider, passando o endereço.
    noncePromise = provider.getTransactionCount(signerAddress, "pending");

    console.log(`Nonce inicial obtido com sucesso para o endereço ${signerAddress}.`);
} catch (e) {
    console.error("Falha ao inicializar o gestor de nonce:", e);
    process.exit(1);
}

const getNextNonce = async () => {
    const nonce = await noncePromise;
    noncePromise = Promise.resolve(nonce + 1);
    return nonce;
};

app.post('/monitor/start', (req, res) => {
    const { roundName, runNumber } = req.body;
    const runId = `${roundName}_run_${runNumber}`;
    const logPath = path.join(LOG_DIR, `docker_stats_${runId}.log`);

    if (monitoringProcesses[runId]) {
        return res.status(409).json({ message: `O monitoramento para ${runId} já está em execução.` });
    }

    console.log(`Iniciando monitoramento (método Caliper) para: ${runId}. A gravar em: ${logPath}`);
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
                        Object.values(stats.networks).forEach(net => {
                            netRx += net.rx_bytes;
                            netTx += net.tx_bytes;
                        });
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
// ----------------------------------------------------------

// --- MODIFICAÇÃO: Endpoints agora usam os módulos de workload ---

// --- Endpoint Assíncrono para 'open' ---
app.post('/open-async', async (req, res) => {
    const { accountId, amount } = req.body;
    if (!accountId || amount === undefined) {
        return res.status(400).json({ error: "Campos 'accountId' e 'amount' são obrigatórios." });
    }
    try {
        const nonce = await getNextNonce(); // Obtém o próximo nonce
        const txResponse = await openWorkload.submitTransaction(accountId, amount, nonce);
        console.log(`(Async) Transação 'open' para a conta ${accountId} submetida. Hash: ${txResponse.hash}, Nonce: ${nonce}`);
        res.status(202).json({ message: `Transação 'open' aceite para processamento.`, transactionHash: txResponse.hash });
    } catch (error) {
        console.error(`(Async) Erro ao submeter transação 'open' para ${accountId}:`, error);
        res.status(500).json({ error: "Falha ao submeter a transação 'open'.", details: error.message });
    }
});

// --- Endpoint Assíncrono para 'transfer' ---
app.post('/transfer-async', async (req, res) => {
    const { from, to, amount } = req.body;
    if (!from || !to || amount === undefined) {
        return res.status(400).json({ error: "Os campos 'from', 'to' e 'amount' são obrigatórios." });
    }
    try {
        const nonce = await getNextNonce(); // Obtém o próximo nonce
        const txResponse = await transferWorkload.submitTransaction(from, to, amount, nonce);
        console.log(`(Async) Transação 'transfer' de ${from} para ${to} submetida. Hash: ${txResponse.hash}, Nonce: ${nonce}`);
        res.status(202).json({ message: "Transação 'transfer' aceite para processamento.", transactionHash: txResponse.hash });
    } catch (error) {
        console.error(`(Async) Erro ao submeter transação 'transfer' de ${from} para ${to}:`, error);
        res.status(500).json({ error: "Falha ao submeter a transação 'transfer'.", details: error.message });
    }
});

// --- Endpoint Síncrono para 'query' ---
app.get('/query/:accountId', async (req, res) => {
    const { accountId } = req.params;
    if (!accountId) {
        return res.status(400).json({ error: "O campo 'accountId' é obrigatório." });
    }
    try {
        const balance = await queryWorkload.submitTransaction(accountId);
        console.log(`Consulta para conta: ${accountId}, Saldo encontrado: ${balance.toString()}`);
        res.status(200).json({ accountId: accountId, balance: balance.toString() });
    } catch (error) {
        console.error(`Falha ao executar 'query' para a conta ${accountId}:`, error);
        res.status(500).json({ error: "Falha ao executar a função 'query'.", details: error.message });
    }
});

// -------------------------------------------------------------

// --- Iniciar o Servidor ---
app.listen(port, () => {
    console.log(`Servidor da API (Nó Único) a correr em http://localhost:${port}`);
    console.log(`A API está a enviar todos os pedidos para: ${BESU_RPC_URL}`);
    console.log(`Usando contrato no endereço: ${CONTRACT_ADDRESS}`);
});