'use strict';

// MODIFICAÇÃO: A classe agora é inicializada sem parâmetros e não depende do JMeter.
const OperationBase = require('./utils/operation-base.js');

class Open extends OperationBase {
    constructor(rpcUrl, privateKey, contractAddress) {
        super(rpcUrl, privateKey, contractAddress);
    }
    
    // MODIFICAÇÃO: O método agora aceita os argumentos diretamente.
    // A lógica de negócio está focada apenas em montar e enviar a transação.
    async submitTransaction(accountId, amount, nonce) {
        const createArgs = { 
            acc_id: accountId, 
            amount: amount 
        };
        // Passa o nonce para a sendRequest
        return await this.sendRequest('open', createArgs, false, nonce);
    }
}

// MODIFICAÇÃO: O arquivo não exporta mais uma instância, mas sim a própria classe.
// Isso permite que a API a configure com as variáveis de ambiente corretas.
module.exports = Open;