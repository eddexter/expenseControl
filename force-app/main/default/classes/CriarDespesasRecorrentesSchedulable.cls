/**
 * Agenda a execução do CriarDespesasRecorrentesBatchable. Responsabilidade
 * única: disparar o batch — nenhuma regra de negócio aqui.
 * Setup único via scripts/apex/schedule-batch.apex (dia 1 de cada mês, 01:00).
 */
public class CriarDespesasRecorrentesSchedulable implements Schedulable {

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new CriarDespesasRecorrentesBatchable());
    }
}
