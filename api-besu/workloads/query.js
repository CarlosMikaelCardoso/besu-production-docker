'use strict';

const OperationBase = require('./utils/operation-base.js');

class Query extends OperationBase {
    constructor(rpcUrl, privateKey, contractAddress) {
        super(rpcUrl, privateKey, contractAddress);
    }

    /**
     * Monta e envia uma transação de consulta.
     * @param {string} accountId A conta a ser consultada.
     * @returns {Promise<any>} O resultado da consulta (saldo).
     */
    async submitTransaction(accountId) {
        // MODIFICAÇÃO: A lógica para obter uma conta aleatória foi removida.
        // O script agora recebe o 'accountId' diretamente da API.
        const queryArgs = {
            acc_id: accountId
        };
        // A flag 'true' indica que esta é uma transação de leitura (read-only).
        return await this.sendRequest('query', queryArgs, true);
    }
}

// MODIFICAÇÃO: Exporta a classe para ser instanciada pela API.
module.exports = Query;