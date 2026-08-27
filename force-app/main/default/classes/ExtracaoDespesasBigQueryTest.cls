@isTest
private class ExtracaoDespesasBigQueryTest {

    @TestSetup
    static void setup() {
        Carteira__c carteira = new Carteira__c(Name = 'Nubank', Tipo__c = 'Conta Corrente');
        insert carteira;

        Date primeiroDiaMesAtual = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        Date primeiroDiaProximoMes = primeiroDiaMesAtual.addMonths(1);

        insert new List<Despesa__c>{
            new Despesa__c(
                Descricao__c = 'Aluguel mes atual',
                Valor__c = 1500,
                Data_Vencimento__c = primeiroDiaMesAtual.addDays(9),
                Status__c = 'Pendente',
                Carteira__c = carteira.Id
            ),
            new Despesa__c(
                Descricao__c = 'Aluguel mes seguinte',
                Valor__c = 1500,
                Data_Vencimento__c = primeiroDiaProximoMes.addDays(9),
                Status__c = 'Pendente',
                Carteira__c = carteira.Id
            ),
            new Despesa__c(
                Descricao__c = 'Internet mes atual - ja extraida',
                Valor__c = 100,
                Data_Vencimento__c = primeiroDiaMesAtual.addDays(14),
                Status__c = 'Pago',
                Data_Pagamento__c = primeiroDiaMesAtual.addDays(14),
                Data_Extracao__c = Date.today().addDays(-1),
                Carteira__c = carteira.Id
            )
        };
    }

    @isTest
    static void testExtraiApenasDespesasDoMesEscolhidoAindaNaoExtraidas() {
        Test.setMock(HttpCalloutMock.class, new LokiLoggerMock(200));

        Test.startTest();
        ExtracaoDespesasBigQuery.ExtracaoInput input = new ExtracaoDespesasBigQuery.ExtracaoInput();
        input.mesVencimento = Date.today();
        List<ExtracaoDespesasBigQuery.ExtracaoResultado> resultados =
            ExtracaoDespesasBigQuery.extrair(new List<ExtracaoDespesasBigQuery.ExtracaoInput>{ input });
        Test.stopTest();

        System.assertEquals(1, resultados.size());
        System.assertEquals(1, resultados[0].quantidadeExtraida,
            'Só a despesa do mês atual ainda não extraída deve ser processada');

        Despesa__c aluguelMesAtual = [SELECT Data_Extracao__c FROM Despesa__c WHERE Descricao__c = 'Aluguel mes atual'];
        System.assertEquals(Date.today(), aluguelMesAtual.Data_Extracao__c);

        Despesa__c aluguelMesSeguinte = [SELECT Data_Extracao__c FROM Despesa__c WHERE Descricao__c = 'Aluguel mes seguinte'];
        System.assertEquals(null, aluguelMesSeguinte.Data_Extracao__c, 'Despesa de outro mês não deve ser tocada');

        Despesa__c internetJaExtraida = [
            SELECT Data_Extracao__c
            FROM Despesa__c
            WHERE Descricao__c = 'Internet mes atual - ja extraida'
        ];
        System.assertEquals(Date.today().addDays(-1), internetJaExtraida.Data_Extracao__c,
            'Despesa já extraída não deve ser reprocessada nem ter a data sobrescrita');
    }

    @isTest
    static void testFalhaNoCalloutNaoMarcaComoExtraida() {
        Test.setMock(HttpCalloutMock.class, new LokiLoggerMock(500));

        Test.startTest();
        ExtracaoDespesasBigQuery.ExtracaoResultado resultado = ExtracaoDespesasBigQuery.extrairMes(Date.today());
        Test.stopTest();

        System.assertEquals(0, resultado.quantidadeExtraida);

        Despesa__c aluguelMesAtual = [SELECT Data_Extracao__c FROM Despesa__c WHERE Descricao__c = 'Aluguel mes atual'];
        System.assertEquals(null, aluguelMesAtual.Data_Extracao__c,
            'Callout com falha não deve marcar a despesa como extraída — próxima tentativa reprocessa o mesmo mês');
    }

    @isTest
    static void testMesSemDespesasPendentes() {
        Test.setMock(HttpCalloutMock.class, new LokiLoggerMock(200));

        Test.startTest();
        ExtracaoDespesasBigQuery.ExtracaoResultado resultado =
            ExtracaoDespesasBigQuery.extrairMes(Date.today().addMonths(2));
        Test.stopTest();

        System.assertEquals(0, resultado.quantidadeExtraida);
    }

    // Regressão: Date.format() é sensível ao locale da org (ex.: "02/08/2026" numa org
    // pt-BR) e o BigQuery exige DATE em ISO 8601 (yyyy-MM-dd) — descoberto num teste
    // ponta a ponta real contra a Cloud Function. Confirma que o payload sempre usa ISO,
    // não o formato de exibição do usuário.
    @isTest
    static void testPayloadEnviaDataEmFormatoIso() {
        CapturaRequisicaoMock mock = new CapturaRequisicaoMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtracaoDespesasBigQuery.extrairMes(Date.today());
        Test.stopTest();

        Date vencimentoEsperado = Date.newInstance(Date.today().year(), Date.today().month(), 1).addDays(9);
        String isoEsperado = String.valueOf(vencimentoEsperado);
        System.assert(mock.corpoCapturado.contains(isoEsperado),
            'Payload deve conter a data de vencimento em ISO (' + isoEsperado + '), corpo: ' + mock.corpoCapturado);
        System.assert(!mock.corpoCapturado.contains('/'),
            'Payload não deve conter datas em formato de exibição (com "/"), corpo: ' + mock.corpoCapturado);
    }

    private class CapturaRequisicaoMock implements HttpCalloutMock {
        public String corpoCapturado;

        public HttpResponse respond(HttpRequest req) {
            corpoCapturado = req.getBody();
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"ok":true}');
            return res;
        }
    }
}
