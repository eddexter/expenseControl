/**
 * Testes puros do DespesaExtracaoPayloadBuilder — sObjects montados em
 * memória (putSObject para simular o relacionamento Carteira__r), sem
 * inserir nada no banco.
 */
@isTest
private class DespesaExtracaoPayloadBuilderTest {

    @isTest
    static void testMontaLinhaComCamposDaDespesaEDaCarteira() {
        Despesa__c despesa = new Despesa__c(
            Descricao__c = 'Aluguel',
            Valor__c = 1500,
            Status__c = 'Pago',
            Data_Vencimento__c = Date.newInstance(2026, 9, 10),
            Data_Pagamento__c = Date.newInstance(2026, 9, 9),
            Tipo__c = 'Moradia',
            Tipo_Pagamento__c = 'Pix',
            Variavel__c = false,
            Empresa__c = 'Imobiliaria XPTO'
        );
        despesa.putSObject('Carteira__r', new Carteira__c(
            Name = 'Nubank',
            Tipo__c = 'Conta Corrente',
            Instituicao__c = 'Nubank'
        ));

        Test.startTest();
        Map<String, Object> payload = new DespesaExtracaoPayloadBuilder().montar(new List<Despesa__c>{ despesa });
        Test.stopTest();

        List<Object> linhas = (List<Object>) payload.get('despesas');
        System.assertEquals(1, linhas.size());

        Map<String, Object> linha = (Map<String, Object>) linhas[0];
        System.assertEquals('Aluguel', linha.get('descricao'));
        System.assertEquals('2026-09-10', linha.get('data_vencimento'),
            'Data deve estar em ISO 8601, não no formato de exibição do usuário');
        System.assertEquals('2026-09-09', linha.get('data_pagamento'));
        System.assertEquals('Nubank', linha.get('carteira_nome'));
        System.assertEquals('Conta Corrente', linha.get('carteira_tipo'));
    }

    @isTest
    static void testCamposDeCarteiraNulosQuandoSemRelacionamento() {
        Despesa__c despesa = new Despesa__c(Descricao__c = 'Sem carteira setada', Valor__c = 10, Status__c = 'Pendente');

        Test.startTest();
        Map<String, Object> payload = new DespesaExtracaoPayloadBuilder().montar(new List<Despesa__c>{ despesa });
        Test.stopTest();

        Map<String, Object> linha = (Map<String, Object>) ((List<Object>) payload.get('despesas'))[0];
        System.assertEquals(null, linha.get('carteira_nome'));
    }

    @isTest
    static void testDataNulaViraNullNoPayload() {
        Despesa__c despesa = new Despesa__c(Descricao__c = 'Sem pagamento ainda', Valor__c = 10, Status__c = 'Pendente');

        Test.startTest();
        Map<String, Object> payload = new DespesaExtracaoPayloadBuilder().montar(new List<Despesa__c>{ despesa });
        Test.stopTest();

        Map<String, Object> linha = (Map<String, Object>) ((List<Object>) payload.get('despesas'))[0];
        System.assertEquals(null, linha.get('data_pagamento'));
    }
}
