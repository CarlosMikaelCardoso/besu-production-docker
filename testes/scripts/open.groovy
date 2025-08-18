// scripts/open_logic.groovy

// Dicionário para gerar nomes de contas, igual ao do Caliper
final String DICTIONARY = "abcdefghijklmnopqrstuvwxyz";

// Função para converter um número para base-26 (a, b, c... aa, ab...)
String get26Num(long number) {
    if (number == 0) return "";
    StringBuilder result = new StringBuilder();
    while (number > 0) {
        long remainder = number % DICTIONARY.length();
        result.insert(0, DICTIONARY.charAt((int)remainder));
        number = (number - remainder) / DICTIONARY.length();
    }
    return result.toString();
}

// 1. Obtém o número da thread e da iteração atual
// Cada thread JMeter atua como um "worker" do Caliper
int workerIndex = ctx.getThreadNum();
int iteration = ctx.getVariables().getIteration();

// 2. Gera um prefixo único para o worker, igual ao do Caliper
String accountPrefix = get26Num(workerIndex);

// 3. Gera a chave da conta baseada na iteração
// A combinação do prefixo + iteração garante uma conta única por transação
String accountKey = accountPrefix + get26Num(iteration);

// 4. Define a variável "accountId" que será usada no corpo da requisição HTTP
vars.put("accountId", "userJmeter" + accountKey);

// 5. (Opcional, mas recomendado) Log para depuração
log.info("Worker " + workerIndex + " gerou a conta: " + vars.get("accountId"));