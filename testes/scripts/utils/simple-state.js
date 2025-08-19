'use strict';
const Dictionary = 'abcdefghijklmnopqrstuvwxyz';

function _get26Num(number) {
    let result = '';
    while (number >= 0) {
        result = Dictionary.charAt(number % Dictionary.length) + result;
        number = Math.floor(number / Dictionary.length) - 1;
    }
    return result;
}

class SimpleState {
    constructor(workerIndex, numberOfAccounts, totalWorkers) {
        this.workerIndex = workerIndex;
        this.accountPrefix = _get26Num(this.workerIndex);
        this.accountsPerWorker = numberOfAccounts / totalWorkers;
    }

    _getAccountKey(index) {
        return this.accountPrefix + _get26Num(index);
    }

    getOpenAccountArguments(accountIdFromCSV) {
        return { acc_id: this.accountPrefix + accountIdFromCSV, amount: 10000 };
    }

    getQueryArguments() {
        const randomIndex = Math.ceil(Math.random() * this.accountsPerWorker);
        return { acc_id: this._getAccountKey(randomIndex) };
    }

    getTransferArguments() {
        const randomSourceIndex = Math.ceil(Math.random() * this.accountsPerWorker);
        let randomTargetIndex = Math.ceil(Math.random() * this.accountsPerWorker);
        while (randomSourceIndex === randomTargetIndex) {
            randomTargetIndex = Math.ceil(Math.random() * this.accountsPerWorker);
        }
        return { acc_from: this._getAccountKey(randomSourceIndex), acc_to: this._getAccountKey(randomTargetIndex), amount: 100 };
    }
}
module.exports = SimpleState;