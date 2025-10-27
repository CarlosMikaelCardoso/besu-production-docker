// Exporta as variáveis de ambiente necessárias para a configuração do Besu.
// export DEPLOYER_PRIVATE_KEY="0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63"
// export CONTRACT_ADDRESS="0x42699A7612A82f1d9C36148af9C77354759b210b"
// export API_WORKERS=5 (Define o número de workers concorrentes)

const express = require('express');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const Docker = require('dockerode');
const { ethers } = require('ethers');

const docker = new Docker();

// Importar as classes de workload refatoradas
const OpenWorkload = require('./workloads/open.js');
const QueryWorkload = require('./workloads/query.js');
const TransferWorkload = require('./workloads/transfer.js');

const app = express();
const port = 3000;
app.use(express.json());

// Configuração das Variáveis de Ambiente
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS;

if (!DEPLOYER_PRIVATE_KEY || !CONTRACT_ADDRESS) {
    console.error("Erro Crítico: As variáveis de ambiente DEPLOYER_PRIVATE_KEY e CONTRACT_ADDRESS são obrigatórias.");
    process.exit(1);
}

// --- MODIFICAÇÃO: Lógica de Nó Único ---
// Define o número de workers (instâncias/concorrência) com base na variável de ambiente
const NUM_WORKERS = parseInt(process.env.API_WORKERS || '5', 10);
// Define a URL estática para o node1
const BESU_RPC_URL = "http://localhost:8545"; // Apenas node1

// --- MODIFICAÇÃO: Criar um pool de workers (instâncias) que apontam TODOS para o Node1 ---
const workerInstances = [];
for (let i = 0; i < NUM_WORKERS; i++) {
    workerInstances.push({
        open: new OpenWorkload(BESU_RPC_URL, DEPLOYER_PRIVATE_KEY, CONTRACT_ADDRESS),
        query: new QueryWorkload(BESU_RPC_URL, DEPLOYER_PRIVATE_KEY, CONTRACT_ADDRESS),
        transfer: new TransferWorkload(BESU_RPC_URL, DEPLOYER_PRIVATE_KEY, CONTRACT_ADDRESS),
        nodeUrl: BESU_RPC_URL, // Para fins de log
        index: i
    });
}
console.log(`Instanciados ${workerInstances.length} pools de workload para ${BESU_RPC_URL}`);

let currentWorkerIndex = 0;

// --- MODIFICAÇÃO: Balanceador agora é um simples Round-Robin sobre as *instâncias* de worker ---
const getNextWorker = () => {
    const worker = workerInstances[currentWorkerIndex];
    currentWorkerIndex = (currentWorkerIndex + 1) % workerInstances.length;
    // console.log(`Encaminhando para worker instance: ${worker.index}`); // Descomente para debug
    return worker;
};

const getNextOpenWorkload = () => getNextWorker().open;
const getNextQueryWorkload = () => getNextWorker().query;
const getNextTransferWorkload = () => getNextWorker().transfer;
// --- FIM DAS MODIFICAÇÕES DE BALANCEAMENTO ---


// --- Gestor de Nonce Unificado com Auto-Recuperação ---
class NonceManager {
    constructor(provider, signer) {
        this.provider = provider;
        this.signer = signer;
        this.nonce = -1;
        this.lock = Promise.resolve();
        this.initialize();
    }

    async initialize() {
        try {
            this.nonce = await this.provider.getTransactionCount(this.signer.address, "pending");
            console.log(`Gestor de Nonce inicializado. Nonce inicial: ${this.nonce}`);
        } catch (e) {
            console.error("Falha crítica ao inicializar o gestor de nonce:", e);
            process.exit(1);
        }
    }

    async getNextNonce() {
        await this.lock;
        let releaseLock;
        this.lock = new Promise(resolve => { releaseLock = resolve; });

        try {
            const nonceToUse = this.nonce;
            this.nonce++;
            return nonceToUse;
        } finally {
            releaseLock();
        }
    }

    async resyncNonce() {
        await this.lock;
        let releaseLock;
        this.lock = new Promise(resolve => { releaseLock = resolve; });

        try {
            console.log("!!! RESSINCRONIZANDO NONCE !!!");
            const freshNonce = await this.provider.getTransactionCount(this.signer.address, "pending");
            
            if (freshNonce > this.nonce) {
                console.log(`Nonce dessincronizado. Atualizando de ${this.nonce} para ${freshNonce}.`);
                this.nonce = freshNonce;
            } else {
                console.log(`Nonce já estava correto ou adiantado (${this.nonce}). Nenhuma alteração necessária.`);
            }
        } catch (e) {
            console.error("Erro durante a ressincronização do nonce:", e);
        } finally {
            releaseLock();
        }
    }
}

// MODIFICAÇÃO: Provider do NonceManager aponta para a URL única
const provider = new ethers.JsonRpcProvider(BESU_RPC_URL); 
const signer = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);
const nonceManager = new NonceManager(provider, signer);

// --- Fila de Trabalhos (Job Queue) ---
let processingErrors = [];

class JobQueue {
    constructor(concurrency) {
        this.queue = [];
        this.workers = [];
        this.concurrency = concurrency;
        console.log(`Fila de trabalhos iniciada com ${concurrency} workers.`);
    }

    addJob(job) {
        this.queue.push(job);
        this.processQueue();
    }
    
    isIdle() {
        return this.queue.length === 0 && this.workers.length === 0;
    }

    processQueue() {
        if (this.queue.length > 0 && this.workers.length < this.concurrency) {
            const job = this.queue.shift();
            const worker = this.runWorker(job);
            this.workers.push(worker);

            worker.finally(() => {
                this.workers = this.workers.filter(w => w !== worker);
                this.processQueue();
            });
        }
    }

    async runWorker(job) {
        try {
            const nonceToUse = await nonceManager.getNextNonce();
            await job(nonceToUse);
        } catch (error) {
            console.error("Erro ao processar trabalho da fila:", error.message);
            processingErrors.push({
                timestamp: new Date().toISOString(),
                error: error.message,
                reason: error.reason || 'N/A',
                code: error.code || 'N/A'
            });

            const errorMessage = (error.error && error.error.message) || error.message || '';
            if (errorMessage.includes('nonce') || errorMessage.includes('Nonce')) {
                await nonceManager.resyncNonce();
            }
        }
    }
}

// MODIFICAÇÃO: Concorrência da fila agora usa a variável NUM_WORKERS
const writeQueue = new JobQueue(NUM_WORKERS);

// --- Endpoints de Controle ---
app.get('/queue/status', (req, res) => {
    res.status(200).json({
        isIdle: writeQueue.isIdle(),
        queueSize: writeQueue.queue.length,
        activeWorkers: writeQueue.workers.length
    });
});

app.get('/errors/get', (req, res) => {
    res.status(200).json({ errors: processingErrors });
});

app.post('/errors/clear', (req, res) => {
    console.log("Limpando log de erros de processamento.");
    processingErrors = [];
    res.status(200).json({ message: "Log de erros limpo." });
});

// --- Lógica de Monitoramento do Docker (sem alterações) ---
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
                    try {
                        const stats = JSON.parse(chunk.toString());
                        const cpuDelta = stats.cpu_stats.cpu_usage.total_usage - stats.precpu_stats.cpu_usage.total_usage;
                        const systemDelta = stats.cpu_stats.system_cpu_usage - stats.precpu_stats.system_cpu_usage;
                        const cpuCount = stats.cpu_stats.online_cpus || (stats.cpu_stats.cpu_usage.percpu_usage ? stats.cpu_stats.cpu_usage.percpu_usage.length : 0);
                        let cpuPercent = 0.0;
                        if (systemDelta > 0.0 && cpuDelta > 0.0 && cpuCount > 0) {
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
                    } catch (e) {
                        console.error("Erro ao fazer parse das estatísticas do Docker:", e);
                    }
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

// --- Endpoints ---
app.post('/open-async', (req, res) => {
    const { accountId, amount } = req.body;
    if (!accountId || amount === undefined) return res.status(400).json({ error: "Campos 'accountId' e 'amount' são obrigatórios." });

    writeQueue.addJob(async (nonce) => {
        const workload = getNextOpenWorkload();
        const txResponse = await workload.submitTransaction(accountId, amount, nonce);
        console.log(`(Fila) Transação 'open' para ${accountId} submetida. Hash: ${txResponse.hash}, Nonce: ${nonce}`);
    });

    res.status(202).json({ message: `Transação 'open' para ${accountId} enfileirada com sucesso.` });
});

app.post('/transfer-async', (req, res) => {
    const { from, to, amount } = req.body;
    if (!from || !to || amount === undefined) return res.status(400).json({ error: "Os campos 'from', 'to' e 'amount' são obrigatórios." });

    writeQueue.addJob(async (nonce) => {
        const workload = getNextTransferWorkload();
        const txResponse = await workload.submitTransaction(from, to, amount, nonce);
        console.log(`(Fila) Transação 'transfer' de ${from} para ${to} submetida. Hash: ${txResponse.hash}, Nonce: ${nonce}`);
    });

    res.status(202).json({ message: "Transação 'transfer' enfileirada com sucesso." });
});

app.get('/query/:accountId', async (req, res) => {
    const { accountId } = req.params;
    if (!accountId) return res.status(400).json({ error: "O campo 'accountId' é obrigatório." });

    try {
        const workload = getNextQueryWorkload();
        const balance = await workload.submitTransaction(accountId);
        res.status(200).json({ accountId: accountId, balance: balance.toString() });
    } catch (error) {
        console.error(`Falha ao executar 'query' para a conta ${accountId}:`, error);
        res.status(500).json({ error: "Falha ao executar a função 'query'.", details: error.message });
    }
});

// --- Iniciar o Servidor ---
app.listen(port, () => {
    // MODIFICAÇÃO: Mensagem de log
    console.log(`Servidor da API (Single Node - Node1) a correr em http://localhost:${port}`);
    console.log(`API a usar ${NUM_WORKERS} workers.`);
    console.log(`A API está a enviar todos os pedidos para: ${BESU_RPC_URL}`);
    console.log(`Usando contrato no endereço: ${CONTRACT_ADDRESS}`);
});