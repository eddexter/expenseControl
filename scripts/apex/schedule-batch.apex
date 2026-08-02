// Setup único: agenda o CriarDespesasRecorrentesBatch para rodar no dia 1 de cada mês, à 01:00.
// Rodar uma vez por org com: sf apex run --file scripts/apex/schedule-batch.apex --target-org <alias>
String cronExpression = '0 0 1 1 * ?';
System.schedule('Criar Despesas Recorrentes - Mensal', cronExpression, new CriarDespesasRecorrentesBatch());
