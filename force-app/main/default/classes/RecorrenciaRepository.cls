/**
 * Acesso a dados de Recorrencia__c — único lugar que monta SOQL para o objeto.
 * Sem lógica de negócio: quem decide o que fazer com as recorrências ativas é
 * o CriarDespesasRecorrentesService/Batchable.
 */
public without sharing class RecorrenciaRepository {

    private static final String CAMPOS_PADRAO =
        'Id, Descricao__c, Valor__c, Dia_Vencimento__c, Tipo__c, Carteira_Padrao__c, ' +
        'Tipo_Pagamento__c, Variavel__c, Empresa__c';

    public Database.QueryLocator queryLocatorAtivas() {
        return Database.getQueryLocator(
            'SELECT ' + CAMPOS_PADRAO + ' FROM Recorrencia__c WHERE Ativa__c = true'
        );
    }
}
