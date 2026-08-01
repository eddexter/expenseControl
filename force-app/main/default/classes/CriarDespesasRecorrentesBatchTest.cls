@isTest
private class CriarDespesasRecorrentesBatchTest {

    @TestSetup
    static void setup() {
        Carteira__c carteira = new Carteira__c(Name = 'Nubank', Tipo__c = 'Conta Corrente');
        insert carteira;

        Recorrencia__c recorrenciaAtiva = new Recorrencia__c(
            Descricao__c = 'Aluguel',
            Valor__c = 1500,
            Dia_Vencimento__c = 31,
            Data_Inicio__c = Date.today().addMonths(-6),
            Carteira_Padrao__c = carteira.Id,
            Categoria__c = 'Moradia',
            Tipo_Pagamento__c = 'Débito Automático',
            Variavel__c = false,
            Empresa__c = 'Imobiliaria XPTO'
        );
        Recorrencia__c recorrenciaInativa = new Recorrencia__c(
            Descricao__c = 'Antiga Assinatura',
            Valor__c = 30,
            Dia_Vencimento__c = 10,
            Data_Inicio__c = Date.today().addMonths(-12),
            Data_Fim__c = Date.today().addMonths(-1),
            Carteira_Padrao__c = carteira.Id,
            Categoria__c = 'Assinaturas'
        );
        insert new List<Recorrencia__c>{ recorrenciaAtiva, recorrenciaInativa };
    }

    @isTest
    static void testCriaDespesaParaRecorrenciaAtiva() {
        Recorrencia__c rec = [SELECT Id FROM Recorrencia__c WHERE Descricao__c = 'Aluguel' LIMIT 1];

        Test.startTest();
        Database.executeBatch(new CriarDespesasRecorrentesBatch());
        Test.stopTest();

        List<Despesa__c> despesas = [
            SELECT Status__c, Valor__c, Carteira__c, Recorrencia__c, Data_Vencimento__c,
                Tipo_Pagamento__c, Variavel__c, Empresa__c
            FROM Despesa__c
            WHERE Recorrencia__c = :rec.Id
        ];
        System.assertEquals(1, despesas.size(), 'Deveria criar exatamente uma despesa para a recorrência ativa');
        System.assertEquals('Pendente', despesas[0].Status__c);
        System.assertEquals(1500, despesas[0].Valor__c);
        System.assertEquals('Débito Automático', despesas[0].Tipo_Pagamento__c,
            'Tipo de Pagamento deve ser copiado da recorrência');
        System.assertEquals(false, despesas[0].Variavel__c, 'Variável deve ser copiado da recorrência');
        System.assertEquals('Imobiliaria XPTO', despesas[0].Empresa__c, 'Empresa deve ser copiada da recorrência');

        Integer lastDay = Date.daysInMonth(Date.today().year(), Date.today().month());
        System.assertEquals(lastDay, despesas[0].Data_Vencimento__c.day(),
            'Dia 31 deve virar o último dia do mês quando o mês corrente for mais curto');
    }

    @isTest
    static void testNaoDuplicaAoRodarBatchDuasVezes() {
        Recorrencia__c rec = [SELECT Id FROM Recorrencia__c WHERE Descricao__c = 'Aluguel' LIMIT 1];

        Test.startTest();
        Database.executeBatch(new CriarDespesasRecorrentesBatch());
        Database.executeBatch(new CriarDespesasRecorrentesBatch());
        Test.stopTest();

        List<Despesa__c> despesas = [SELECT Id FROM Despesa__c WHERE Recorrencia__c = :rec.Id];
        System.assertEquals(1, despesas.size(), 'Rodar o batch duas vezes no mesmo mês não deve duplicar a despesa');
    }

    @isTest
    static void testNaoCriaDespesaParaRecorrenciaInativa() {
        Recorrencia__c rec = [SELECT Id FROM Recorrencia__c WHERE Descricao__c = 'Antiga Assinatura' LIMIT 1];

        Test.startTest();
        Database.executeBatch(new CriarDespesasRecorrentesBatch());
        Test.stopTest();

        List<Despesa__c> despesas = [SELECT Id FROM Despesa__c WHERE Recorrencia__c = :rec.Id];
        System.assertEquals(0, despesas.size(), 'Recorrência inativa (Data_Fim no passado) não deve gerar despesa');
    }
}
