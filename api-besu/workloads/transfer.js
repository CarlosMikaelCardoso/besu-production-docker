'use strict';

const OperationBase = require('./utils/operation-base.js');

class Transfer extends OperationBase {
    constructor(rpcUrl, privateKey, contractAddress) {
        super(rpcUrl, privateKey, contractAddress);
    }

    /**
     * Monta e envia uma transação de transferência.
     * @param {string} fromAccount A conta de origem.
     * @param {string} toAccount A conta de destino.
     * @param {number} amount O valor a ser transferido.
     * @returns {Promise<any>} O objeto da transação enviada.
     */
    async submitTransaction(fromAccount, toAccount, amount, nonce) {
        const transferArgs = {
            acc_from: fromAccount,
            acc_to: toAccount,
            amount: amount
        };
        // Passa o nonce para a sendRequest
        return await this.sendRequest('transfer', transferArgs, false, nonce);
    }
}

// MODIFICAÇÃO: Exporta a classe.
module.exports = Transfer;