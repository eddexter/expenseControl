/**
 * Batchable que quita automaticamente as despesas de Débito Automático/Cartão
 * de Crédito no dia do vencimento. Só orquestra: monta o DespesaFilter, busca
 * via DespesaRepository, delegando a quitação em si ao
 * QuitarDespesasDebitoCartaoService, e o resultado ao BatchObservabilidadeService.
 *
 * Agendado via QuitarDespesasDebitoCartaoSchedulable
 * (scripts/apex/schedule-quitar-debito-cartao.apex) ou executável sob demanda
 * (scripts/apex/run-quitar-debito-cartao.apex).
 */
public class QuitarDespesasDebitoCartaoBatchable implements Database.Batchable<SObject>, Database.AllowsCallouts {

    private final DespesaRepository despesaRepository = new DespesaRepository();
    private final QuitarDespesasDebitoCartaoService service = new QuitarDespesasDebitoCartaoService(despesaRepository);

    public Database.QueryLocator start(Database.BatchableContext bc) {
        DespesaFilter filtro = new DespesaFilter()
            .comStatus('Pendente')
            .comDataVencimento(Date.today())
            .comTiposPagamento(QuitarDespesasDebitoCartaoService.TIPOS_PAGAMENTO_BAIXA_AUTOMATICA);
        return despesaRepository.queryLocator(filtro);
    }

    public void execute(Database.BatchableContext bc, List<Despesa__c> scope) {
        service.quitarDespesasVencendoHoje(scope);
    }

    public void finish(Database.BatchableContext bc) {
        new BatchObservabilidadeService().logResultado('QuitarDespesasDebitoCartaoBatchable', bc.getJobId());
    }
}
