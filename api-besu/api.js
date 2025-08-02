const express = require('express');
const { ethers } = require('ethers');
const { spawn } = require('child_process'); // Módulo para executar processos externos
const fs = require('fs'); // Módulo para interagir com o sistema de ficheiros
const path = require('path'); // Módulo para lidar com caminhos de ficheiros

// --- Configuração da Aplicação e Conexão ---
const app = express();
const port = 3000;
app.use(express.json());

// --- Configuração do Ethers e Contrato ---
const BESU_RPC_URL = process.env.BESU_RPC_URL || "http://localhost:8545";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS;

// Validação para garantir que as variáveis essenciais foram definidas
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
let openTxCount = 1;

// --- Lógica de Monitoramento do Docker ---

const monitoringProcesses = {};
const DOCKER_CONTAINERS_TO_MONITOR = ["node1", "node2", "node3", "node4", "node5", "node6"];

/**
 * Endpoint para iniciar o monitoramento do Docker para um round de teste específico.
 */
app.post('/monitor/start', (req, res) => {
    const { roundName, runNumber, logPath } = req.body;
    if (!roundName || !runNumber || !logPath) {
        return res.status(400).json({ error: "Campos 'roundName', 'runNumber' e 'logPath' são obrigatórios." });
    }

    const runId = `${roundName}_run_${runNumber}`;
    if (monitoringProcesses[runId]) {
        return res.status(409).json({ message: `O monitoramento para ${runId} já está em execução.` });
    }

    console.log(`Iniciando monitoramento para: ${runId}. A gravar em: ${logPath}`);

    // Garante que o diretório de logs existe
    const dir = path.dirname(logPath);
    if (!fs.existsSync(dir)){
        fs.mkdirSync(dir, { recursive: true });
    }

    // Cria um stream para o ficheiro de log
    const logStream = fs.createWriteStream(logPath, { flags: 'a' });

    // Função que executa 'docker stats' e escreve no stream
    const getStats = () => {
        const monitorProcess = spawn('docker', [
            'stats', '--no-stream', '--format', '{{.Name}},{{.CPUPerc}},{{.MemUsage}}', ...DOCKER_CONTAINERS_TO_MONITOR
        ]);
        
        monitorProcess.stdout.pipe(logStream, { end: false }); // Não fecha o stream de escrita
        monitorProcess.stderr.on('data', (data) => {
            console.error(`Erro no docker stats para ${runId}: ${data}`);
        });
    };
    
    // Executa a função imediatamente e depois a cada segundo
    getStats();
    const intervalId = setInterval(getStats, 1000);

    // Armazena o ID do intervalo para poder pará-lo mais tarde
    monitoringProcesses[runId] = { interval: intervalId, stream: logStream };

    res.status(202).json({ message: `Monitoramento para ${runId} iniciado.` });
});

/**
 * Endpoint para parar o monitoramento do Docker.
 */
app.post('/monitor/stop', (req, res) => {
    const { roundName, runNumber } = req.body;
    if (!roundName || !runNumber) {
        return res.status(400).json({ error: "Campos 'roundName' e 'runNumber' são obrigatórios." });
    }

    const runId = `${roundName}_run_${runNumber}`;
    const processInfo = monitoringProcesses[runId];

    if (processInfo) {
        console.log(`Parando monitoramento para: ${runId}`);
        clearInterval(processInfo.interval); // Para o loop de recolha
        processInfo.stream.end(); // Fecha o stream do ficheiro
        delete monitoringProcesses[runId];
        res.status(200).json({ message: `Monitoramento para ${runId} parado.` });
    } else {
        res.status(404).json({ message: `Nenhum processo de monitoramento encontrado para ${runId}.` });
    }
});


// --- Endpoints de Transação (Síncronos) ---

app.post('/open', async (req, res) => {
    const { accountId, amount } = req.body;
    if (!accountId || amount === undefined) {
        return res.status(400).json({ error: "Campos 'accountId' e 'amount' são obrigatórios." });
    }

    try {
        console.log(`Recebido pedido 'open' para a conta: ${accountId}. Submetendo...`);
        const tx = await contract.open(accountId, amount);
        const receipt = await tx.wait();
        console.log(`Transação 'open' #${openTxCount} confirmada com sucesso! Hash: ${receipt.hash}`);
        openTxCount++;
        res.status(200).json({
            message: `Transação 'open' confirmada na blockchain.`,
            transactionHash: receipt.hash
        });

    } catch (error) {
        console.error(`Erro ao processar transação 'open' para a conta ${accountId}:`, error);
        res.status(500).json({ error: "Falha ao confirmar a transação 'open'.", details: error.message });
    }
});

app.post('/transfer', async (req, res) => {
    const { from, to, amount } = req.body;
    if (!from || !to || amount === undefined) {
        return res.status(400).json({ error: "Os campos 'from', 'to' e 'amount' são obrigatórios." });
    }

    try {
        console.log(`Recebido pedido 'transfer' de ${from} para ${to}. Submetendo...`);
        const tx = await contract.transfer(from, to, amount);
        const receipt = await tx.wait();
        console.log(`Transação 'transfer' confirmada com sucesso! Hash: ${receipt.hash}`);
        res.status(200).json({
            message: "Transação 'transfer' confirmada na blockchain.",
            transactionHash: receipt.hash
        });

    } catch (error) {
        console.error(`Erro ao processar transação 'transfer' de ${from} para ${to}:`, error);
        res.status(500).json({ error: "Falha ao confirmar a transação 'transfer'.", details: error.message });
    }
});

app.get('/query/:accountId', async (req, res) => {
    try {
        const balance = await contract.query(req.params.accountId);
        res.status(200).json({ accountId: req.params.accountId, balance: balance.toString() });
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
