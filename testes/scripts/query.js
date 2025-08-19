'use strict';
const OperationBase = require('./utils/operation-base.js');
const SimpleState = require('./utils/simple-state.js');

class Query extends OperationBase {
    constructor() {
        super();
        const threadNum = parseInt(ctx.vars.get('__threadNum'));
        const totalThreads = ctx.getThreadGroup().getNumberOfThreads();
        this.simpleState = new SimpleState(threadNum, 1000, totalThreads);
    }
    
    async submitTransaction() {
        const queryArgs = this.simpleState.getQueryArguments();
        return await this.sendRequest('query', queryArgs, true);
    }
}

// --- LÓGICA DE EXECUÇÃO DO JMETER ---
const workload = new Query();

SampleResult.sampleStart();
workload.submitTransaction()
    .then(result => {
        SampleResult.sampleEnd();
        SampleResult.setSuccessful(true);
        SampleResult.setResponseCodeOK();
        SampleResult.setResponseMessage(`Query successful. Balance: ${result.toString()}`);
    })
    .catch(err => {
        SampleResult.sampleEnd();
        SampleResult.setSuccessful(false);
        SampleResult.setResponseCode("500");
        SampleResult.setResponseMessage(err.message);
        Log.error(err);
    });