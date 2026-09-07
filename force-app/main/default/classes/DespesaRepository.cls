/**
 * Acesso a dados de Despesa__c — único lugar que monta SOQL/DML para o objeto.
 * Critérios de busca vêm de um DespesaFilter; a lógica de negócio (quando
 * buscar o quê, o que fazer com o resultado) fica nos Services que usam este
 * repositório, nunca aqui.
 */
public without sharing class DespesaRepository {

    private static final String CAMPOS_PADRAO =
        'Id, Recorrencia__c, Status__c, Data_Vencimento__c, Data_Pagamento__c, Tipo_Pagamento__c';

    private static final String CAMPOS_EXTRACAO =
        'Id, Descricao__c, Valor__c, Status__c, Data_Vencimento__c, Data_Pagamento__c, ' +
        'Tipo__c, Tipo_Pagamento__c, Variavel__c, Empresa__c, ' +
        'Carteira__r.Name, Carteira__r.Tipo__c, Carteira__r.Instituicao__c';

    public List<Despesa__c> buscar(DespesaFilter filtro) {
        return Database.query(montarSoql(CAMPOS_PADRAO, filtro));
    }

    public Database.QueryLocator queryLocator(DespesaFilter filtro) {
        return Database.getQueryLocator(montarSoql(CAMPOS_PADRAO, filtro));
    }

    public List<Despesa__c> buscarParaExtracao(DespesaFilter filtro) {
        return Database.query(montarSoql(CAMPOS_EXTRACAO, filtro));
    }

    public void inserir(List<Despesa__c> despesas) {
        if (!despesas.isEmpty()) {
            insert despesas;
        }
    }

    public void atualizar(List<Despesa__c> despesas) {
        if (!despesas.isEmpty()) {
            update despesas;
        }
    }

    private String montarSoql(String campos, DespesaFilter filtro) {
        String clausulaWhere = filtro.toSoqlWhere();
        return 'SELECT ' + campos + ' FROM Despesa__c' + (String.isBlank(clausulaWhere) ? '' : ' WHERE ' + clausulaWhere);
    }
}
