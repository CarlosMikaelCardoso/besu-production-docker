const express = require('express');
const { ethers } = require('ethers');

// --- Configuração da Aplicação e Conexão ---
const app = express();
const port = 3000;
app.use(express.json());

const BESU_RPC_URL = "http://localhost:8545";
const DEPLOYER_PRIVATE_KEY = "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63";

// !!! IMPORTANTE: SUBSTITUA ESTE ENDEREÇO PELO ENDEREÇO REAL DO SEU CONTRATO IMPLANTADO !!!
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

// --- Endpoints da API ---

// MODIFICAÇÃO: O endpoint agora é 'async' para poder usar 'await'.
app.post('/open', async (req, res) => {
    const { accountId, amount } = req.body;
    if (!accountId || amount === undefined) {
        return res.status(400).json({ error: "Campos 'accountId' e 'amount' são obrigatórios." });
    }

    try {
        console.log(`Recebido pedido 'open' para a conta: ${accountId}. Submetendo para a blockchain...`);
        
        // 1. Submete a transação para a rede
        const tx = await contract.open(accountId, amount);
        
        // 2. Espera a transação ser minerada e confirmada (aqui é a grande mudança)
        const receipt = await tx.wait();
        
        console.log(`Transação 'open' concluída com sucesso! Hash: ${receipt.hash}`);
        
        // 3. Retorna 200 OK com o hash da transação apenas após a confirmação.
        res.status(200).json({ 
            message: "Transação 'open' confirmada na blockchain.",
            transactionHash: receipt.hash 
        });

    } catch (error) {
        console.error(`Erro ao processar transação 'open' para a conta ${accountId}:`, error);
        res.status(500).json({ error: "Falha ao confirmar a transação 'open'.", details: error.message });
    }
});

// MODIFICAÇÃO: O endpoint agora é 'async' para poder usar 'await'.
app.post('/transfer', async (req, res) => {
    const { from, to, amount } = req.body;
    if (!from || !to || amount === undefined) {
        return res.status(400).json({ error: "Os campos 'from', 'to' e 'amount' são obrigatórios." });
    }

    try {
        console.log(`Recebido pedido 'transfer' de ${from} para ${to}. Submetendo para a blockchain...`);

        // 1. Submete a transação
        const tx = await contract.transfer(from, to, amount);
        
        // 2. Espera pela confirmação
        const receipt = await tx.wait();

        console.log(`Transação 'transfer' concluída com sucesso! Hash: ${receipt.hash}`);

        // 3. Retorna 200 OK apenas após a confirmação
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
    console.log(`Servidor da API a correr em http://10.126.1.238:${port}`);
    console.log("Modo de operação: Síncrono (espera a confirmação da transação).");
});