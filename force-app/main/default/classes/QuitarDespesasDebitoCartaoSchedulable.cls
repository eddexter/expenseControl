/**
 * Agenda a execução do QuitarDespesasDebitoCartaoBatchable. Responsabilidade
 * única: disparar o batch — nenhuma regra de negócio aqui.
 * Setup único via scripts/apex/schedule-quitar-debito-cartao.apex (todo dia às 6h).
 */
public class QuitarDespesasDebitoCartaoSchedulable implements Schedulable {

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new QuitarDespesasDebitoCartaoBatchable());
    }
}
