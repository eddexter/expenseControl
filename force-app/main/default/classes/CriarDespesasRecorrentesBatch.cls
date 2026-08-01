public class CriarDespesasRecorrentesBatch implements Database.Batchable<SObject>, Schedulable {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Descricao__c, Valor__c, Dia_Vencimento__c, Categoria__c, Carteira_Padrao__c,
                Tipo_Pagamento__c, Variavel__c, Empresa__c
            FROM Recorrencia__c
            WHERE Ativa__c = true
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Recorrencia__c> scope) {
        Date today = Date.today();
        Integer year = today.year();
        Integer month = today.month();
        Integer lastDayOfMonth = Date.daysInMonth(year, month);

        Map<Id, Date> dueDateByRecorrenciaId = new Map<Id, Date>();
        for (Recorrencia__c rec : scope) {
            Integer day = Math.min(rec.Dia_Vencimento__c.intValue(), lastDayOfMonth);
            dueDateByRecorrenciaId.put(rec.Id, Date.newInstance(year, month, day));
        }

        Set<Id> recorrenciaIdsComDespesaNoMes = new Set<Id>();
        for (Despesa__c existente : [
            SELECT Recorrencia__c
            FROM Despesa__c
            WHERE Recorrencia__c IN :dueDateByRecorrenciaId.keySet()
            AND CALENDAR_YEAR(Data_Vencimento__c) = :year
            AND CALENDAR_MONTH(Data_Vencimento__c) = :month
        ]) {
            recorrenciaIdsComDespesaNoMes.add(existente.Recorrencia__c);
        }

        List<Despesa__c> despesasParaCriar = new List<Despesa__c>();
        for (Recorrencia__c rec : scope) {
            if (recorrenciaIdsComDespesaNoMes.contains(rec.Id)) {
                continue;
            }
            despesasParaCriar.add(new Despesa__c(
                Descricao__c = rec.Descricao__c,
                Valor__c = rec.Valor__c,
                Data_Vencimento__c = dueDateByRecorrenciaId.get(rec.Id),
                Status__c = 'Pendente',
                Carteira__c = rec.Carteira_Padrao__c,
                Categoria__c = rec.Categoria__c,
                Tipo_Pagamento__c = rec.Tipo_Pagamento__c,
                Variavel__c = rec.Variavel__c,
                Empresa__c = rec.Empresa__c,
                Recorrencia__c = rec.Id
            ));
        }

        if (!despesasParaCriar.isEmpty()) {
            insert despesasParaCriar;
        }
    }

    public void finish(Database.BatchableContext bc) {
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new CriarDespesasRecorrentesBatch());
    }
}
