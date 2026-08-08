public class QuitarDespesasDebitoCartaoBatch implements Database.Batchable<SObject>, Schedulable {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Status__c, Data_Pagamento__c
            FROM Despesa__c
            WHERE Status__c = 'Pendente'
            AND Data_Vencimento__c = TODAY
            AND Tipo_Pagamento__c IN ('Débito Automático', 'Cartão de Crédito')
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Despesa__c> scope) {
        for (Despesa__c despesa : scope) {
            despesa.Status__c = 'Pago';
            despesa.Data_Pagamento__c = Date.today();
        }
        update scope;
    }

    public void finish(Database.BatchableContext bc) {
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new QuitarDespesasDebitoCartaoBatch());
    }
}
