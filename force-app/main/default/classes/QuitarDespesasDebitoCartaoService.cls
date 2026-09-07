/**
 * Regra de negócio de "quitar despesas de Débito Automático/Cartão de Crédito
 * vencendo hoje" — usada pelo QuitarDespesasDebitoCartaoBatchable. Não decide
 * quais despesas se qualificam (isso é responsabilidade do DespesaFilter usado
 * no start() do batch); só sabe como quitar as que recebe.
 */
public class QuitarDespesasDebitoCartaoService {

    public static final List<String> TIPOS_PAGAMENTO_BAIXA_AUTOMATICA = new List<String>{
        'Débito Automático', 'Cartão de Crédito'
    };

    private final DespesaRepository despesaRepository;

    public QuitarDespesasDebitoCartaoService() {
        this(new DespesaRepository());
    }

    public QuitarDespesasDebitoCartaoService(DespesaRepository despesaRepository) {
        this.despesaRepository = despesaRepository;
    }

    public void quitarDespesasVencendoHoje(List<Despesa__c> despesas) {
        Date hoje = Date.today();
        for (Despesa__c despesa : despesas) {
            despesa.Status__c = 'Pago';
            despesa.Data_Pagamento__c = hoje;
        }
        despesaRepository.atualizar(despesas);
    }
}
