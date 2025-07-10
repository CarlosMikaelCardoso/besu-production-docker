const { ethers } = require("hardhat");

// Endereço do contrato
const CONTRACT_ADDRESS = "0xa50a51c09a5c451C52BB714527E1974b686D8e77"; 

// ABI do contrato
const CONTRACT_ABI = [
    { "constant": false, "inputs": [ { "internalType": "string", "name": "acc_from", "type": "string" }, { "internalType": "string", "name": "acc_to", "type": "string" }, { "internalType": "int256", "name": "amount", "type": "int256" } ], "name": "transfer", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
    { "constant": true, "inputs": [ { "internalType": "string", "name": "acc_id", "type": "string" } ], "name": "query", "outputs": [ { "internalType": "int256", "name": "amount", "type": "int256" } ], "stateMutability": "view", "type": "function" },
    { "constant": false, "inputs": [ { "internalType": "string", "name": "acc_id", "type": "string" }, { "internalType": "int256", "name": "amount", "type": "int256" } ], "name": "open", "outputs": [], "stateMutability": "nonpayable", "type": "function" }
];

async function main() {
    const [signer] = await ethers.getSigners();
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);
    console.log("Conectado com sucesso ao contrato em:", await contract.getAddress());

    // --- Demonstração de um fluxo de transações de escrita ---

    const sourceAccount = "conta_origem_final";
    const destAccount = "conta_destino_final";

    // 1. Abrir a conta de origem com 2000 unidades
    console.log(`\n1. A criar a conta '${sourceAccount}'...`);
    const tx1 = await contract.open(sourceAccount, 2000);
    await tx1.wait();
    console.log(`   ✅ Conta '${sourceAccount}' criada com sucesso.`);

    // 2. Abrir a conta de destino com 0 unidades
    console.log(`2. A criar a conta '${destAccount}'...`);
    const tx2 = await contract.open(destAccount, 0);
    await tx2.wait();
    console.log(`   ✅ Conta '${destAccount}' criada com sucesso.`);

    // 3. Transferir 350 unidades da origem para o destino
    console.log(`3. A transferir 350 unidades de '${sourceAccount}' para '${destAccount}'...`);
    const tx3 = await contract.transfer(sourceAccount, destAccount, 350);
    await tx3.wait();
    console.log(`   ✅ Transferência concluída com sucesso!`);

    console.log("\nFluxo de transações de escrita executado com sucesso!");
}

main().catch((error) => {
    console.error("Ocorreu um erro:", error);
    process.exitCode = 1;
});