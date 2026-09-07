/**
 * Batchable que gera as despesas do mês corrente a partir das recorrências
 * ativas. Só orquestra: busca via RecorrenciaRepository, delegando a regra de
 * negócio (cálculo de vencimento, dedupe, criação) ao
 * CriarDespesasRecorrentesService, e o resultado ao BatchObservabilidadeService.
 *
 * Agendado via CriarDespesasRecorrentesSchedulable (scripts/apex/schedule-batch.apex)
 * ou executável sob demanda (scripts/apex/run-batch.apex).
 */
public class CriarDespesasRecorrentesBatchable implements Database.Batchable<SObject>, Database.AllowsCallouts {

    private final RecorrenciaRepository recorrenciaRepository = new RecorrenciaRepository();
    private final CriarDespesasRecorrentesService service = new CriarDespesasRecorrentesService();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return recorrenciaRepository.queryLocatorAtivas();
    }

    public void execute(Database.BatchableContext bc, List<Recorrencia__c> scope) {
        service.gerarDespesasParaRecorrencias(scope);
    }

    public void finish(Database.BatchableContext bc) {
        new BatchObservabilidadeService().logResultado('CriarDespesasRecorrentesBatchable', bc.getJobId());
    }
}
