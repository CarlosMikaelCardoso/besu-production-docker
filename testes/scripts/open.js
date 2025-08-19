'use strict';
const OperationBase = require('./utils/operation-base.js');
const SimpleState = require('./utils/simple-state.js');

class Open extends OperationBase {
    constructor() {
        super();
        const threadNum = parseInt(ctx.vars.get('__threadNum'));
        this.simpleState = new SimpleState(threadNum);
    }
    
    async submitTransaction() {
        const accountId = vars.get("accountId");
        const createArgs = this.simpleState.getOpenAccountArguments(accountId);
        return await this.sendRequest('open', createArgs, false);
    }
}

// --- LÓGICA DE EXECUÇÃO DO JMETER ---
const workload = new Open();

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