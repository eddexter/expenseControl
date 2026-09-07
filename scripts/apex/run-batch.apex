// Executa o CriarDespesasRecorrentesBatchable imediatamente, sem agendamento.
// Util para rodar sob demanda ou testar. Rodar com: sf apex run --file scripts/apex/run-batch.apex --target-org <alias>
Database.executeBatch(new CriarDespesasRecorrentesBatchable());
