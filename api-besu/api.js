const express = require('express');
const { ethers } = require('ethers');

// --- Configuração da Aplicação e Conexão ---
const app = express();
const port = 3000;
app.use(express.json());

const BESU_RPC_URL = "http://localhost:8545";
const DEPLOYER_PRIVATE_KEY = "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63";

// !!! IMPORTANTE: SUBSTITUA ESTE ENDEREÇO PELO ENDEREÇO REAL DO SEU CONTRATO IMPLANTADO !!!
// Ele deve ser o mesmo que está em 'contract_address.txt'
const CONTRACT_ADDRESS = "0x664D6EbAbbD5cf656eD07A509AFfBC81f9615741"; 
const CONTRACT_ABI = [
    { "constant": false, "inputs": [ { "internalType": "string", "name": "acc_from", "type": "string" }, { "internalType": "string", "name": "acc_to", "type": "string" }, { "internalType": "int256", "name": "amount", "type": "int256" } ], "name": "transfer", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
    { "constant": true, "inputs": [ { "internalType": "string", "name": "acc_id", "type": "string" } ], "name": "query", "outputs": [ { "internalType": "int256", "name": "amount", "type": "int256" } ], "stateMutability": "view", "type": "function" },
    { "constant": false, "inputs": [ { "internalType": "string", "name": "acc_id", "type": "string" }, { "internalType": "int256", "name": "amount", "type": "int256" } ], "name": "open", "outputs": [], "stateMutability": "nonpayable", "type": "function" }
];

// --- Inicialização do Ethers ---
const provider = new ethers.JsonRpcProvider(BESU_RPC_URL);
const signer = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);
const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);

// --- SISTEMA DE FILA DE TRANSAÇÕES (MODELO WORKER) ---
const transactionQueue = [];
let isProcessing = false;
let currentNonce;

async function transactionWorker() {
    if (isProcessing || transactionQueue.length === 0) return;
    isProcessing = true;
    while (transactionQueue.length > 0) {
        const task = transactionQueue.shift();
        try {
            // Adiciona um log antes de submeter a transação
            console.log(`Tentando submeter transação: ${task.name} com nonce ${currentNonce}`);
            const tx = await task.action({ nonce: currentNonce });
            console.log(`Transação submetida. Nonce: ${currentNonce}, Hash: ${tx.hash}`);
            currentNonce++;
        } catch (error) {
            console.error(`Falha ao processar tarefa '${task.name}'. Nonce: ${currentNonce}. Erro: ${error.message}`);
            // Em caso de erro, você pode querer tentar novamente ou ter uma estratégia de fallback
            // Por enquanto, apenas logamos o erro.
            currentNonce++; // Incrementa o nonce mesmo em caso de falha para evitar nonce stuck
        }
    }
    isProcessing = false;
}

function enqueueAndProcess(task) {
    transactionQueue.push(task);
    transactionWorker();
}

// --- Endpoints da API ---
app.post('/open', (req, res) => {
    const { accountId, amount } = req.body;
    if (!accountId || amount === undefined) {
        return res.status(400).json({ error: "Campos 'accountId' e 'amount' são obrigatórios." });
    }
    enqueueAndProcess({ name: 'open', action: (opts) => contract.open(accountId, amount, opts) });
    res.status(202).json({ 
        message: "Pedido 'open' recebido e enfileirado.",
        data: req.body 
    });
});

app.post('/transfer', (req, res) => {
    const { from, to, amount } = req.body;
    if (!from || !to || amount === undefined) {
        return res.status(400).json({ error: "Os campos 'from', 'to' e 'amount' são obrigatórios." });
    }
    enqueueAndProcess({ name: 'transfer', action: (opts) => contract.transfer(from, to, amount, opts) });
    res.status(202).json({ 
        message: "Pedido 'transfer' recebido e enfileirado.",
        data: req.body
    });
});

app.get('/query/:accountId', async (req, res) => {
    try {
        // Loga o accountId que está sendo consultado
        console.log(`Tentando consultar saldo para accountId: ${req.params.accountId}`);
        const balance = await contract.query(req.params.accountId);
        res.status(200).json({ accountId: req.params.accountId, balance: balance.toString() });
    } catch (error) {
        console.error(`Falha ao executar a função 'query' para accountId: ${req.params.accountId}. Erro: ${error.message}`);
        res.status(500).json({ error: "Falha ao executar a função 'query'.", details: error.message });
    }
});

// --- Iniciar o Servidor e obter o nonce inicial ---
(async () => {
    try {
        currentNonce = await provider.getTransactionCount(signer.address, 'latest');
        app.listen(port, () => {
            console.log(`Servidor da API com Worker a correr em http://10.126.1.238:${port}`);
            console.log(`Nonce inicial obtido: ${currentNonce}`);
        });
    } catch (error) {
        console.error("Falha ao inicializar o servidor e obter o nonce. Verifique a conexão com o nó Besu.", error);
        process.exit(1);
    }
})();
