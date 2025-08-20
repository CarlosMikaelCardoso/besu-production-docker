'use strict';

const { ethers } = require('ethers');

class OperationBase {
    constructor(rpcUrl, privateKey, contractAddress) {
        // MODIFICAÇÃO: Armazenamos o provider e o signer como propriedades
        // da classe de forma mais explícita e inicializamos o nonce aqui.
        const CONTRACT_ABI = [{"constant":false,"inputs":[{"internalType":"string","name":"acc_from","type":"string"},{"internalType":"string","name":"acc_to","type":"string"},{"internalType":"int256","name":"amount","type":"int256"}],"name":"transfer","outputs":[],"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[{"internalType":"string","name":"acc_id","type":"string"}],"name":"query","outputs":[{"internalType":"int256","name":"amount","type":"int256"}],"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"internalType":"string","name":"acc_id","type":"string"},{"internalType":"int256","name":"amount","type":"int256"}],"name":"open","outputs":[],"stateMutability":"nonpayable","type":"function"}];
        const provider = new ethers.JsonRpcProvider(rpcUrl);
        this.signer = new ethers.Wallet(privateKey, provider);
        this.contract = new ethers.Contract(contractAddress, CONTRACT_ABI, this.signer);
    }

    async getNextNonce() {
        // MODIFICAÇÃO: Simplificamos a lógica para obter e incrementar o nonce.
        // O método 'getNonce()' é um alias para 'getTransactionCount()' e
        // resolve o problema da função não ser encontrada.
        const nonce = await this.noncePromise;
        this.noncePromise = Promise.resolve(nonce + 1);
        return nonce;
    }
    
    async sendRequest(operation, args, isReadOnly, nonce) {
        if (isReadOnly) {
            return this.contract[operation](...Object.values(args));
        } else {
            return this.contract[operation](...Object.values(args), { nonce });
        }
    }

    async submitTransaction() {
        throw new Error('submitTransaction() deve ser implementado pela classe filha');
    }
}

module.exports = OperationBase;