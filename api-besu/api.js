const express = require('express');
const { ethers } = require('ethers');

// --- Configuração da Aplicação e Conexão ---
const app = express();
const port = 3000;
app.use(express.json());

/*
AJUSTE: As configurações críticas (URL do RPC, chave privada e endereço do contrato)
são carregadas a partir de variáveis de ambiente. Isso evita expor dados
sensíveis no código-fonte e facilita a execução em diferentes ambientes.
*/

// Exporta as variáveis de ambiente necessárias para a configuração do Besu.
// export BESU_RPC_URL="http://localhost:8545"
// export DEPLOYER_PRIVATE_KEY="0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63"
// export CONTRACT_ADDRESS="0x42699A7612A82f1d9C36148af9C77354759b210b"

const BESU_RPC_URL = process.env.BESU_RPC_URL || "http://localhost:8545";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS;

// Validação para garantir que as variáveis essenciais foram definidas no ambiente
if (!DEPLOYER_PRIVATE_KEY || !CONTRACT_ADDRESS) {
    console.error("Erro Crítico: As variáveis de ambiente DEPLOYER_PRIVATE_KEY e CONTRACT_ADDRESS são obrigatórias.");
    process.exit(1); // Encerra a aplicação se as variáveis não estiverem configuradas
}

const CONTRACT_ABI = [
    { "constant": false, "inputs": [ { "internalType": "string", "name": "acc_from", "type": "string" }, { "internalType": "string", "name": "acc_to", "type": "string" }, { "internalType": "int256", "name": "amount", "type": "int256" } ], "name": "transfer", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
    { "constant": true, "inputs": [ { "internalType": "string", "name": "acc_id", "type": "string" } ], "name": "query", "outputs": [ { "internalType": "int256", "name": "amount", "type": "int256" } ], "stateMutability": "view", "type": "function" },
    { "constant": false, "inputs": [ { "internalType": "string", "name": "acc_id", "type": "string" }, { "internalType": "int256", "name": "amount", "type": "int256" } ], "name": "open", "outputs": [], "stateMutability": "nonpayable", "type": "function" }
];

// --- Inicialização do Ethers ---
const provider = new ethers.JsonRpcProvider(BESU_RPC_URL);
const signer = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);
const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);
let count = 1;

// --- Endpoints da API ---

// O endpoint agora é 'async' para poder usar 'await'.
app.post('/open', async (req, res) => {
    const { accountId, amount } = req.body;
    if (!accountId || amount === undefined) {
        return res.status(400).json({ error: "Campos 'accountId' e 'amount' são obrigatórios." });
    }

    try {
        console.log(`Recebido pedido 'open' para a conta: ${accountId}. Submetendo para a blockchain...`);
        const tx = await contract.open(accountId, amount);
        const receipt = await tx.wait(); // Espera a transação ser confirmada
        console.log(`Transação 'open' ${count}, concluída com sucesso! Hash: ${receipt.hash}`);
        count++;
        res.status(200).json({
            message: `Transação 'open' confirmada na blockchain.`,
            transactionHash: receipt.hash
        });

    } catch (error) {
        console.error(`Erro ao processar transação 'open' para a conta ${accountId}:`, error);
        res.status(500).json({ error: "Falha ao confirmar a transação 'open'.", details: error.message });
    }
});

// O endpoint agora é 'async' para poder usar 'await'.
app.post('/transfer', async (req, res) => {
    const { from, to, amount } = req.body;
    if (!from || !to || amount === undefined) {
        return res.status(400).json({ error: "Os campos 'from', 'to' e 'amount' são obrigatórios." });
    }

    try {
        console.log(`Recebido pedido 'transfer' de ${from} para ${to}. Submetendo para a blockchain...`);
        const tx = await contract.transfer(from, to, amount);
        const receipt = await tx.wait(); // Espera a transação ser confirmada
        console.log(`Transação 'transfer' concluída com sucesso! Hash: ${receipt.hash}`);
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