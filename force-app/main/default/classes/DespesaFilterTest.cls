/**
 * Testes puros do DespesaFilter — sem SOQL/DML, já que toSoqlWhere() só monta
 * texto a partir dos critérios informados.
 */
@isTest
private class DespesaFilterTest {

    @isTest
    static void testSemCondicoesRetornaClausulaVazia() {
        System.assertEquals('', new DespesaFilter().toSoqlWhere());
    }

    @isTest
    static void testStatusEDataVencimentoIgualCombinamComAnd() {
        Date data = Date.newInstance(2026, 9, 6);

        String clausula = new DespesaFilter().comStatus('Pendente').comDataVencimento(data).toSoqlWhere();

        System.assertEquals('Status__c = \'Pendente\' AND Data_Vencimento__c = 2026-09-06', clausula);
    }

    @isTest
    static void testDataVencimentoEntre() {
        Date de = Date.newInstance(2026, 9, 1);
        Date ate = Date.newInstance(2026, 9, 30);

        String clausula = new DespesaFilter().comDataVencimentoEntre(de, ate).toSoqlWhere();

        System.assertEquals('Data_Vencimento__c >= 2026-09-01 AND Data_Vencimento__c <= 2026-09-30', clausula);
    }

    @isTest
    static void testTiposPagamentoViraClausulaIn() {
        String clausula = new DespesaFilter()
            .comTiposPagamento(new List<String>{ 'Débito Automático', 'Cartão de Crédito' })
            .toSoqlWhere();

        System.assertEquals('Tipo_Pagamento__c IN (\'Débito Automático\', \'Cartão de Crédito\')', clausula);
    }

    @isTest
    static void testTiposPagamentoVazioNaoAdicionaCondicao() {
        String clausula = new DespesaFilter().comTiposPagamento(new List<String>()).toSoqlWhere();

        System.assertEquals('', clausula);
    }

    @isTest
    static void testSemDataExtracao() {
        System.assertEquals('Data_Extracao__c = null', new DespesaFilter().semDataExtracao().toSoqlWhere());
    }

    @isTest
    static void testEscapaAspaSimplesNoStatus() {
        String clausula = new DespesaFilter().comStatus('Pendente\' OR Status__c != \'Pendente').toSoqlWhere();

        System.assert(clausula.contains('\\\''), 'Aspas simples devem ser escapadas: ' + clausula);
    }
}
