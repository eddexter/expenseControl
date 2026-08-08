@isTest
private class QuitarDespesasDebitoCartaoBatchTest {

    @TestSetup
    static void setup() {
        Carteira__c carteira = new Carteira__c(Name = 'Nubank', Tipo__c = 'Conta Corrente');
        insert carteira;

        List<Despesa__c> despesas = new List<Despesa__c>{
            new Despesa__c(
                Descricao__c = 'Financiamento - Débito Automático vencendo hoje',
                Valor__c = 500,
                Data_Vencimento__c = Date.today(),
                Status__c = 'Pendente',
                Carteira__c = carteira.Id,
                Tipo_Pagamento__c = 'Débito Automático'
            ),
            new Despesa__c(
                Descricao__c = 'Assinatura - Cartão de Crédito vencendo hoje',
                Valor__c = 60,
                Data_Vencimento__c = Date.today(),
                Status__c = 'Pendente',
                Carteira__c = carteira.Id,
                Tipo_Pagamento__c = 'Cartão de Crédito'
            ),
            new Despesa__c(
                Descricao__c = 'Boleto vencendo hoje',
                Valor__c = 200,
                Data_Vencimento__c = Date.today(),
                Status__c = 'Pendente',
                Carteira__c = carteira.Id,
                Tipo_Pagamento__c = 'Boleto'
            ),
            new Despesa__c(
                Descricao__c = 'Débito Automático vencendo amanhã',
                Valor__c = 300,
                Data_Vencimento__c = Date.today().addDays(1),
                Status__c = 'Pendente',
                Carteira__c = carteira.Id,
                Tipo_Pagamento__c = 'Débito Automático'
            ),
            new Despesa__c(
                Descricao__c = 'Cartão de Crédito já pago vencendo hoje',
                Valor__c = 80,
                Data_Vencimento__c = Date.today(),
                Data_Pagamento__c = Date.today().addDays(-1),
                Status__c = 'Pago',
                Carteira__c = carteira.Id,
                Tipo_Pagamento__c = 'Cartão de Crédito'
            )
        };
        insert despesas;
    }

    @isTest
    static void testQuitaDebitoAutomaticoECartaoVencendoHoje() {
        Test.startTest();
        Database.executeBatch(new QuitarDespesasDebitoCartaoBatch());
        Test.stopTest();

        Map<String, Despesa__c> despesaPorDescricao = new Map<String, Despesa__c>();
        for (Despesa__c despesa : [SELECT Descricao__c, Status__c, Data_Pagamento__c FROM Despesa__c]) {
            despesaPorDescricao.put(despesa.Descricao__c, despesa);
        }

        Despesa__c debitoAutomatico = despesaPorDescricao.get('Financiamento - Débito Automático vencendo hoje');
        System.assertEquals('Pago', debitoAutomatico.Status__c, 'Débito Automático vencendo hoje deve ser quitado');
        System.assertEquals(Date.today(), debitoAutomatico.Data_Pagamento__c);

        Despesa__c cartao = despesaPorDescricao.get('Assinatura - Cartão de Crédito vencendo hoje');
        System.assertEquals('Pago', cartao.Status__c, 'Cartão de Crédito vencendo hoje deve ser quitado');
        System.assertEquals(Date.today(), cartao.Data_Pagamento__c);
    }

    @isTest
    static void testNaoQuitaOutroTipoDePagamento() {
        Test.startTest();
        Database.executeBatch(new QuitarDespesasDebitoCartaoBatch());
        Test.stopTest();

        Despesa__c boleto = [SELECT Status__c FROM Despesa__c WHERE Descricao__c = 'Boleto vencendo hoje'];
        System.assertEquals('Pendente', boleto.Status__c, 'Boleto não deve ser quitado automaticamente');
    }

    @isTest
    static void testNaoQuitaVencimentoFuturo() {
        Test.startTest();
        Database.executeBatch(new QuitarDespesasDebitoCartaoBatch());
        Test.stopTest();

        Despesa__c futura = [SELECT Status__c FROM Despesa__c WHERE Descricao__c = 'Débito Automático vencendo amanhã'];
        System.assertEquals('Pendente', futura.Status__c, 'Despesa vencendo amanhã não deve ser quitada hoje');
    }

    @isTest
    static void testNaoAlteraDespesaJaPaga() {
        Test.startTest();
        Database.executeBatch(new QuitarDespesasDebitoCartaoBatch());
        Test.stopTest();

        Despesa__c jaPaga = [
            SELECT Status__c, Data_Pagamento__c
            FROM Despesa__c
            WHERE Descricao__c = 'Cartão de Crédito já pago vencendo hoje'
        ];
        System.assertEquals('Pago', jaPaga.Status__c);
        System.assertEquals(Date.today().addDays(-1), jaPaga.Data_Pagamento__c,
            'Data de pagamento original não deve ser sobrescrita, pois a despesa já não está Pendente');
    }
}
