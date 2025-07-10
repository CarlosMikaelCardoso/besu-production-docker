const express = require('express');
const { ethers } = require('ethers');

// --- Configuração da Aplicação e Conexão ---
const app = express();
const port = 3000;
app.use(express.json());

const BESU_RPC_URL = "http://localhost:8545";
const DEPLOYER_PRIVATE_KEY = "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63";

const CONTRACT_ADDRESS = "0xa50a51c09a5c451C52BB714527E1974b686D8e77";
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
            const tx = await task.action({ nonce: currentNonce });
            console.log(`Transação submetida. Nonce: ${currentNonce}, Hash: ${tx.hash}`);
            currentNonce++;
        } catch (error) {
            console.error(`Falha ao processar tarefa. Nonce: ${currentNonce}. Erro: ${error.message}`);
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
    enqueueAndProcess({ action: (opts) => contract.open(accountId, amount, opts) });
    // ALTERAÇÃO AQUI: Incluindo os dados da requisição na resposta
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
    enqueueAndProcess({ action: (opts) => contract.transfer(from, to, amount, opts) });
    // ALTERAÇÃO AQUI: Incluindo os dados da requisição na resposta
    res.status(202).json({ 
        message: "Pedido 'transfer' recebido e enfileirado.",
        data: req.body
    });
});

app.get('/query/:accountId', async (req, res) => {
    try {
        const balance = await contract.query(req.params.accountId);
        res.status(200).json({ accountId: req.params.accountId, balance: balance.toString() });
    } catch (error) {
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