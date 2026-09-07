/**
 * Regra de negócio de "gerar as despesas do mês a partir das recorrências
 * ativas" — usada pelo CriarDespesasRecorrentesBatchable. Idempotente: não
 * cria uma despesa nova para uma recorrência que já tem despesa no mês
 * corrente (verificado via DespesaRepository, não recalculado aqui).
 */
public class CriarDespesasRecorrentesService {

    private final DespesaRepository despesaRepository;

    public CriarDespesasRecorrentesService() {
        this(new DespesaRepository());
    }

    public CriarDespesasRecorrentesService(DespesaRepository despesaRepository) {
        this.despesaRepository = despesaRepository;
    }

    public void gerarDespesasParaRecorrencias(List<Recorrencia__c> recorrencias) {
        if (recorrencias.isEmpty()) {
            return;
        }

        Date hoje = Date.today();
        Integer ano = hoje.year();
        Integer mes = hoje.month();
        Integer ultimoDiaDoMes = Date.daysInMonth(ano, mes);

        Map<Id, Date> vencimentoPorRecorrenciaId = new Map<Id, Date>();
        for (Recorrencia__c rec : recorrencias) {
            Integer dia = Math.min(rec.Dia_Vencimento__c.intValue(), ultimoDiaDoMes);
            vencimentoPorRecorrenciaId.put(rec.Id, Date.newInstance(ano, mes, dia));
        }

        Set<Id> recorrenciaIdsComDespesaNoMes = buscarRecorrenciaIdsComDespesaNoMes(
            vencimentoPorRecorrenciaId.keySet(), ano, mes
        );

        List<Despesa__c> despesasParaCriar = new List<Despesa__c>();
        for (Recorrencia__c rec : recorrencias) {
            if (recorrenciaIdsComDespesaNoMes.contains(rec.Id)) {
                continue;
            }
            despesasParaCriar.add(new Despesa__c(
                Descricao__c = rec.Descricao__c,
                Valor__c = rec.Valor__c,
                Data_Vencimento__c = vencimentoPorRecorrenciaId.get(rec.Id),
                Status__c = 'Pendente',
                Carteira__c = rec.Carteira_Padrao__c,
                Tipo__c = rec.Tipo__c,
                Tipo_Pagamento__c = rec.Tipo_Pagamento__c,
                Variavel__c = rec.Variavel__c,
                Empresa__c = rec.Empresa__c,
                Recorrencia__c = rec.Id
            ));
        }

        despesaRepository.inserir(despesasParaCriar);
    }

    private Set<Id> buscarRecorrenciaIdsComDespesaNoMes(Set<Id> recorrenciaIds, Integer ano, Integer mes) {
        Date primeiroDiaDoMes = Date.newInstance(ano, mes, 1);
        Date ultimoDiaDoMes = primeiroDiaDoMes.addMonths(1).addDays(-1);

        DespesaFilter filtro = new DespesaFilter()
            .comRecorrenciaIds(recorrenciaIds)
            .comDataVencimentoEntre(primeiroDiaDoMes, ultimoDiaDoMes);

        Set<Id> resultado = new Set<Id>();
        for (Despesa__c despesa : despesaRepository.buscar(filtro)) {
            resultado.add(despesa.Recorrencia__c);
        }
        return resultado;
    }
}
