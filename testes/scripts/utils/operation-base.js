// testes/scripts/utils/operation-base.js

'use strict';

const { ethers } = require('ethers');

class OperationBase {
    constructor() {
        // Acede às propriedades do JMeter
        const DEPLOYER_PRIVATE_KEY = org.apache.jmeter.util.JMeterUtils.getProperty("DEPLOYER_PRIVATE_KEY");
        const CONTRACT_ADDRESS = org.apache.jmeter.util.JMeterUtils.getProperty("CONTRACT_ADDRESS");
        const BESU_RPC_URL = org.apache.jmeter.util.JMeterUtils.getProperty("BESU_RPC_URL");

        const CONTRACT_ABI = [{"constant":false,"inputs":[{"internalType":"string","name":"acc_from","type":"string"},{"internalType":"string","name":"acc_to","type":"string"},{"internalType":"int256","name":"amount","type":"int256"}],"name":"transfer","outputs":[],"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[{"internalType":"string","name":"acc_id","type":"string"}],"name":"query","outputs":[{"internalType":"int256","name":"amount","type":"int256"}],"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"internalType":"string","name":"acc_id","type":"string"},{"internalType":"int256","name":"amount","type":"int256"}],"name":"open","outputs":[],"stateMutability":"nonpayable","type":"function"}];

        const provider = new ethers.JsonRpcProvider(BESU_RPC_URL);
        const signer = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);
        this.contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);
    }

    async sendRequest(operation, args, isReadOnly) {
        if (isReadOnly) {
            return this.contract[operation](...Object.values(args));
        } else {
            return this.contract[operation](...Object.values(args));
        }
    }

    async submitTransaction() {
        throw new Error('submitTransaction() deve ser implementado pela classe filha');
    }
}

module.exports = OperationBase;