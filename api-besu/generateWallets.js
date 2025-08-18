// generateWallets.js
const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

// Defina quantas contas "worker" você quer. 20 é um bom começo.
const NUM_WALLETS = 20;

let wallets = [];
for (let i = 0; i < NUM_WALLETS; i++) {
    const wallet = ethers.Wallet.createRandom();
    wallets.push({
        address: wallet.address,
        privateKey: wallet.privateKey
    });
}

// Salva as carteiras num ficheiro JSON para a API poder ler
fs.writeFileSync(path.join(__dirname, 'wallets.json'), JSON.stringify(wallets, null, 2));

console.log(`${NUM_WALLETS} carteiras geradas com sucesso em wallets.json!`);
console.log("Agora, adicione estes endereços ao seu ficheiro genesis.json para financiá-los.");