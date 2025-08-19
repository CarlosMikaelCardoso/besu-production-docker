'use strict';
const OperationBase = require('./utils/operation-base.js');
const SimpleState = require('./utils/simple-state.js');

class Transfer extends OperationBase {
    constructor() {
        super();
        const threadNum = parseInt(ctx.vars.get('__threadNum'));
        const totalThreads = ctx.getThreadGroup().getNumberOfThreads();
        this.simpleState = new SimpleState(threadNum, 1000, totalThreads);
    }

    async submitTransaction() {
        const transferArgs = this.simpleState.getTransferArguments();
        return await this.sendRequest('transfer', transferArgs, false);
    }
}

// --- LÓGICA DE EXECUÇÃO DO JMETER ---
const workload = new Transfer();

SampleResult.sampleStart();
workload.submitTransaction()
    .then(result => {
        SampleResult.sampleEnd();
        SampleResult.setSuccessful(true);
        SampleResult.setResponseCodeOK();
        SampleResult.setResponseMessage(`Tx submitted: ${result.hash}`);
    })
    .catch(err => {
        SampleResult.sampleEnd();
        SampleResult.setSuccessful(false);
        SampleResult.setResponseCode("500");
        SampleResult.setResponseMessage(err.message);
        Log.error(err);
    });