// Executa o QuitarDespesasDebitoCartaoBatch imediatamente, sem agendamento.
// Util para rodar sob demanda ou testar. Rodar com: sf apex run --file scripts/apex/run-quitar-debito-cartao.apex --target-org <alias>
Database.executeBatch(new QuitarDespesasDebitoCartaoBatch());
