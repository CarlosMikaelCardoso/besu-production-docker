const express = require('express');
const { ethers } = require('ethers');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os'); // Módulo para obter o diretório temporário do sistema

// --- Configuração da Aplicação e Conexão ---
const app = express();
const port = 3000;
app.use(express.json());

// --- Configuração do Ethers e Contrato ---
const BESU_RPC_URL = process.env.BESU_RPC_URL || "http://localhost:8545";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS;

if (!DEPLOYER_PRIVATE_KEY || !CONTRACT_ADDRESS) {
    console.error("Erro Crítico: As variáveis de ambiente DEPLOYER_PRIVATE_KEY e CONTRACT_ADDRESS são obrigatórias.");
    process.exit(1);
}

const CONTRACT_ABI = [
    { "constant": false, "inputs": [ { "internalType": "string", "name": "acc_from", "type": "string" }, { "internalType": "string", "name": "acc_to", "type": "string" }, { "internalType": "int256", "name": "amount", "type": "int256" } ], "name": "transfer", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
    { "constant": true, "inputs": [ { "internalType": "string", "name": "acc_id", "type": "string" } ], "name": "query", "outputs": [ { "internalType": "int256", "name": "amount", "type": "int256" } ], "stateMutability": "view", "type": "function" },
    { "constant": false, "inputs": [ { "internalType": "string", "name": "acc_id", "type": "string" }, { "internalType": "int256", "name": "amount", "type": "int256" } ], "name": "open", "outputs": [], "stateMutability": "nonpayable", "type": "function" }
];

const provider = new ethers.JsonRpcProvider(BESU_RPC_URL);
const signer = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);
const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);

// Contadores para as transações
let openTxCount = 1;
let transferTxCount = 1;

// Gerenciamento manual de nonce para lidar com alta concorrência
let noncePromise = provider.getTransactionCount(signer.getAddress(), "pending");

// --- Lógica de Monitoramento do Docker ---

const monitoringProcesses = {};
const DOCKER_CONTAINERS_TO_MONITOR = ["node1", "node2", "node3", "node4", "node5", "node6"];
const LOG_DIR = path.join(os.tmpdir(), 'jmeter_docker_logs');
if (!fs.existsSync(LOG_DIR)) {
    fs.mkdirSync(LOG_DIR, { recursive: true });
}

app.post('/monitor/start', (req, res) => {
    const { roundName, runNumber } = req.body;
    if (!roundName || !runNumber) {
        return res.status(400).json({ error: "Campos 'roundName' e 'runNumber' são obrigatórios." });
    }

    const runId = `${roundName}_run_${runNumber}`;
    const logPath = path.join(LOG_DIR, `docker_stats_${runId}.log`);

    if (monitoringProcesses[runId]) {
        return res.status(409).json({ message: `O monitoramento para ${runId} já está em execução.` });
    }

    console.log(`Iniciando monitoramento para: ${runId}. A gravar em: ${logPath}`);
    const logStream = fs.createWriteStream(logPath, { flags: 'w' });

    const getStats = () => {
        const monitorProcess = spawn('docker', [
            'stats', '--no-stream', '--format', '{{.Name}},{{.CPUPerc}},{{.MemUsage}}', ...DOCKER_CONTAINERS_TO_MONITOR
        ]);
        monitorProcess.stdout.pipe(logStream, { end: false });
        monitorProcess.stderr.on('data', (data) => console.error(`Erro no docker stats para ${runId}: ${data}`));
    };
    
    getStats();
    const intervalId = setInterval(getStats, 1000);
    monitoringProcesses[runId] = { interval: intervalId, stream: logStream, path: logPath };

    res.status(202).json({ message: `Monitoramento para ${runId} iniciado.` });
});

app.post('/monitor/stop', (req, res) => {
    const { roundName, runNumber } = req.body;
    if (!roundName || !runNumber) {
        return res.status(400).json({ error: "Campos 'roundName' e 'runNumber' são obrigatórios." });
    }

    const runId = `${roundName}_run_${runNumber}`;
    const processInfo = monitoringProcesses[runId];

    if (processInfo) {
        console.log(`Parando monitoramento para: ${runId}`);
        clearInterval(processInfo.interval);
        processInfo.stream.end();
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

    if (fs.existsSync(logPath)) {
        res.sendFile(logPath);
    } else {
        res.status(404).send('Ficheiro de log não encontrado.');
    }
});


// --- Endpoints de Transação (Síncronos) ---

app.post('/open', async (req, res) => {
    const { accountId, amount } = req.body;
    if (!accountId || amount === undefined) {
        return res.status(400).json({ error: "Campos 'accountId' e 'amount' são obrigatórios." });
    }
    try {
        const nonce = await noncePromise;
        noncePromise = Promise.resolve(nonce + 1);

        console.log(`Recebido pedido 'open' para a conta: ${accountId}. Submetendo com nonce ${nonce}...`);
        const tx = await contract.open(accountId, amount, { nonce });
        const receipt = await tx.wait();
        console.log(`Transação 'open' #${openTxCount} confirmada com sucesso! Hash: ${receipt.hash}`);
        openTxCount++;
        res.status(200).json({
            message: `Transação 'open' confirmada na blockchain.`,
            transactionHash: receipt.hash
        });
    } catch (error) {
        console.error(`Erro ao processar transação 'open' para a conta ${accountId}:`, error);
        if (error.code === 'NONCE_EXPIRED' || error.code === 'REPLACEMENT_UNDERPRICED') {
            noncePromise = provider.getTransactionCount(signer.getAddress(), "pending");
            console.error("Nonce dessincronizado. A reiniciar a contagem de nonce.");
        }
        res.status(500).json({ error: "Falha ao confirmar a transação 'open'.", details: error.message });
    }
});

app.post('/transfer', async (req, res) => {
    const { from, to, amount } = req.body;
    if (!from || !to || amount === undefined) {
        return res.status(400).json({ error: "Os campos 'from', 'to' e 'amount' são obrigatórios." });
    }
    try {
        const nonce = await noncePromise;
        noncePromise = Promise.resolve(nonce + 1);

        console.log(`Recebido pedido 'transfer' de ${from} para ${to}. Submetendo com nonce ${nonce}...`);
        const tx = await contract.transfer(from, to, amount, { nonce });
        const receipt = await tx.wait();
        
        // MODIFICAÇÃO: Adicionado log com o contador de transferências
        console.log(`Transação 'transfer' #${transferTxCount} confirmada com sucesso! Hash: ${receipt.hash}`);
        transferTxCount++; // Incrementa o contador

        res.status(200).json({
            message: "Transação 'transfer' confirmada na blockchain.",
            transactionHash: receipt.hash
        });
    } catch (error) {
        console.error(`Erro ao processar transação 'transfer' de ${from} para ${to}:`, error);
        if (error.code === 'NONCE_EXPIRED' || error.code === 'REPLACEMENT_UNDERPRICED') {
            noncePromise = provider.getTransactionCount(signer.getAddress(), "pending");
            console.error("Nonce dessincronizado. A reiniciar a contagem de nonce.");
        }
        res.status(500).json({ error: "Falha ao confirmar a transação 'transfer'.", details: error.message });
    }
});

app.get('/query/:accountId', async (req, res) => {
    try {
        const accountId = req.params.accountId;
        const balance = await contract.query(accountId);
        
        // MODIFICAÇÃO: Adicionado log para mostrar os dados da consulta
        console.log(`Consulta para conta: ${accountId}, Saldo encontrado: ${balance.toString()}`);

        res.status(200).json({ accountId: accountId, balance: balance.toString() });
    } catch (error) {
        console.error(`Falha ao executar 'query' para a conta ${req.params.accountId}:`, error);
        res.status(500).json({ error: "Falha ao executar a função 'query'.", details: error.message });
    }
});

// --- Iniciar o Servidor ---
app.listen(port, () => {
    console.log(`Servidor da API a correr em http://localhost:${port}`);
    console.log("Modo de operação: Síncrono (espera a confirmação da transação).");
    console.log(`Usando contrato no endereço: ${CONTRACT_ADDRESS}`);
});
