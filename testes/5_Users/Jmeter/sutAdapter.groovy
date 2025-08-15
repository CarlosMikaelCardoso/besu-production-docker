import org.apache.http.client.methods.HttpPost
import org.apache.http.client.methods.HttpGet
import org.apache.http.impl.client.HttpClients
import org.apache.http.util.EntityUtils
import org.apache.http.entity.StringEntity
import groovy.json.JsonSlurper
import groovy.json.JsonOutput

// --- PARÂMETROS CONFIGURÁVEIS ---
// Estes valores podem ser passados via linha de comando do JMeter com -J
def action = props.get("action", "open") // 'open' ou 'transfer'
def apiHost = props.get("apiHost", "localhost")
def apiPort = props.get("apiPort", "3000") as Integer
def pollingIntervalMs = props.get("pollingIntervalMs", "2000") as Long
def maxAttempts = props.get("maxAttempts", "30") as Integer

// --- MONTAGEM DO PAYLOAD ---
def payload
if (action == "open") {
    payload = [accountId: vars.get("accountId"), amount: 10000]
} else if (action == "transfer") {
    payload = [
        from: vars.get("source_account"), 
        to: vars.get("target_account"), 
        amount: 100
    ]
} else {
    SampleResult.setSuccessful(false)
    SampleResult.setResponseMessage("Ação inválida: ${action}")
    return
}

def jsonPayload = JsonOutput.toJson(payload)
def httpClient = HttpClients.createDefault()
def slurper = new JsonSlurper()

// --- PASSO 1: SUBMETER TRANSAÇÃO ---
def postRequest = new HttpPost("http://${apiHost}:${apiPort}/${action}-async")
postRequest.setHeader("Content-Type", "application/json")
postRequest.setEntity(new StringEntity(jsonPayload))

def postResponse = httpClient.execute(postRequest)
def responseBody = EntityUtils.toString(postResponse.getEntity())

if (postResponse.getStatusLine().getStatusCode() != 202) {
    SampleResult.setSuccessful(false)
    SampleResult.setResponseCode(postResponse.getStatusLine().getStatusCode().toString())
    SampleResult.setResponseMessage("Falha ao submeter a transação: " + responseBody)
    return
}

def txHash = (slurper.parseText(responseBody)).transactionHash
if (!txHash) {
    SampleResult.setSuccessful(false)
    SampleResult.setResponseMessage("Não foi possível obter o hash da transação.")
    return
}

// --- PASSO 2: POLLING PARA CONFIRMAÇÃO ---
def receipt = null
for (int i = 0; i < maxAttempts; i++) {
    def getRequest = new HttpGet("http://${apiHost}:${apiPort}/receipt/${txHash}")
    def getResponse = httpClient.execute(getRequest)
    def getBody = EntityUtils.toString(getResponse.getEntity())
    def getResult = slurper.parseText(getBody)

    if (getResult.status == 'confirmed') {
        receipt = getResult.receipt
        break
    }
    Thread.sleep(pollingIntervalMs)
}

// --- PASSO 3: REGISTRAR RESULTADO ---
if (receipt != null) {
    SampleResult.setSuccessful(true)
    SampleResult.setResponseCode("200")
    SampleResult.setResponseMessage("Transação ${action} confirmada.")
} else {
    SampleResult.setSuccessful(false)
    SampleResult.setResponseCode("504") // Timeout
    SampleResult.setResponseMessage("Timeout esperando pela confirmação da transação ${action}.")
}