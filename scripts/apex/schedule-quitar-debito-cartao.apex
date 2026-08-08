// Setup único: agenda o QuitarDespesasDebitoCartaoBatch para rodar todo dia às 6h.
// Rodar uma vez por org com: sf apex run --file scripts/apex/schedule-quitar-debito-cartao.apex --target-org <alias>
String cronExpression = '0 0 6 * * ?';
System.schedule('Quitar Despesas Debito Automatico e Cartao - Diario', cronExpression, new QuitarDespesasDebitoCartaoBatch());
