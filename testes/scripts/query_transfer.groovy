// scripts/query_transfer_logic.groovy

import java.nio.file.Files
import java.nio.file.Paths
import java.util.Random

// 1. Define qual ação está a ser executada. Será passada pelo plano de teste.
String action = props.get("action", "query"); // 'query' ou 'transfer'

// 2. Caminho para o ficheiro com as contas geradas pela ronda "Open"
String accountsFilePath = "../data/generated_accounts.csv";

// 3. Lê todas as contas do ficheiro para a memória (só na primeira vez)
// Usa uma propriedade global para evitar ler o ficheiro a cada iteração
List<String> accountList = props.get("accountList");
if (accountList == null) {
    try {
        accountList = Files.readAllLines(Paths.get(accountsFilePath));
        props.put("accountList", accountList);
        log.info("Carregadas " + accountList.size() + " contas do ficheiro " + accountsFilePath);
    } catch (IOException e) {
        log.error("Não foi possível ler o ficheiro de contas: " + accountsFilePath, e);
        SampleResult.setSuccessful(false);
        SampleResult.setResponseMessage("Erro: Ficheiro de contas não encontrado em " + accountsFilePath);
        return;
    }
}

if (accountList.isEmpty()) {
     SampleResult.setSuccessful(false);
     SampleResult.setResponseMessage("Erro: A lista de contas está vazia.");
     return;
}

// 4. Seleciona conta(s) aleatoriamente
Random rand = new Random();

if (action.equalsIgnoreCase("query")) {
    String randomAccount = accountList.get(rand.nextInt(accountList.size()));
    vars.put("accountId", randomAccount);
    log.info("Selecionada conta para query: " + randomAccount);

} else if (action.equalsIgnoreCase("transfer")) {
    String sourceAccount = accountList.get(rand.nextInt(accountList.size()));
    String targetAccount = accountList.get(rand.nextInt(accountList.size()));
    vars.put("source_account", sourceAccount);
    vars.put("target_account", targetAccount);
    log.info("Selecionadas contas para transfer: " + sourceAccount + " -> " + targetAccount);
}