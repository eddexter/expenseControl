@isTest
private class ExtracaoDespesasBigQueryInvocableTest {

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
    static void testInvocableExtraiApenasDespesasDoMesEscolhidoAindaNaoExtraidas() {
        Test.setMock(HttpCalloutMock.class, new LokiLoggerServiceMock(200));

        Test.startTest();
        ExtracaoDespesasBigQueryInvocable.ExtracaoInput input = new ExtracaoDespesasBigQueryInvocable.ExtracaoInput();
        input.mesVencimento = Date.today();
        List<ExtracaoDespesasBigQueryInvocable.ExtracaoResultado> resultados =
            ExtracaoDespesasBigQueryInvocable.extrair(new List<ExtracaoDespesasBigQueryInvocable.ExtracaoInput>{ input });
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
    static void testServiceFalhaNoCalloutNaoMarcaComoExtraida() {
        Test.setMock(HttpCalloutMock.class, new LokiLoggerServiceMock(500));

        Test.startTest();
        ExtracaoDespesasBigQueryService.Resultado resultado = new ExtracaoDespesasBigQueryService().extrairMes(Date.today());
        Test.stopTest();

        System.assertEquals(0, resultado.quantidadeExtraida);

        Despesa__c aluguelMesAtual = [SELECT Data_Extracao__c FROM Despesa__c WHERE Descricao__c = 'Aluguel mes atual'];
        System.assertEquals(null, aluguelMesAtual.Data_Extracao__c,
            'Callout com falha não deve marcar a despesa como extraída — próxima tentativa reprocessa o mesmo mês');
    }

    @isTest
    static void testServiceMesSemDespesasPendentes() {
        Test.setMock(HttpCalloutMock.class, new LokiLoggerServiceMock(200));

        Test.startTest();
        ExtracaoDespesasBigQueryService.Resultado resultado =
            new ExtracaoDespesasBigQueryService().extrairMes(Date.today().addMonths(2));
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
        new ExtracaoDespesasBigQueryService().extrairMes(Date.today());
        Test.stopTest();

        Date vencimentoEsperado = Date.newInstance(Date.today().year(), Date.today().month(), 1).addDays(9);
        String isoEsperado = String.valueOf(vencimentoEsperado);
        System.assert(mock.corpoCapturado.contains(isoEsperado),
            'Payload deve conter a data de vencimento em ISO (' + isoEsperado + '), corpo: ' + mock.corpoCapturado);
        System.assert(!mock.corpoCapturado.contains('/'),
            'Payload não deve conter datas em formato de exibição (com "/"), corpo: ' + mock.corpoCapturado);
    }

    // Além do callout pro GCP, o service agora também loga o resultado no Grafana
    // Loki (LokiLoggerService) — filtra pelo endpoint pra não deixar o corpo do
    // log de observabilidade sobrescrever o payload de despesas capturado.
    private class CapturaRequisicaoMock implements HttpCalloutMock {
        public String corpoCapturado;

        public HttpResponse respond(HttpRequest req) {
            if (req.getEndpoint().startsWith('callout:GCP_Extracao_Despesas')) {
                corpoCapturado = req.getBody();
            }
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"ok":true}');
            return res;
        }
    }

    @isTest
    static void testExtracaoComSucessoEnviaLogComQuantidadeExtraida() {
        CapturaTodasRequisicoesMock mock = new CapturaTodasRequisicoesMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new ExtracaoDespesasBigQueryService().extrairMes(Date.today());
        Test.stopTest();

        HttpRequest logRequest = mock.requisicaoParaEndpoint('Grafana_Loki');
        System.assertNotEquals(null, logRequest, 'Extração com sucesso deve enviar um evento de log ao Grafana Loki');
        // A linha do Loki vai como JSON serializado dentro do campo "values" (LokiLoggerService),
        // por isso as aspas internas chegam escapadas (\") no corpo da requisição.
        System.assert(logRequest.getBody().contains('\\"status\\":\\"sucesso\\"'),
            'Log deve reportar status de sucesso, corpo: ' + logRequest.getBody());
        System.assert(logRequest.getBody().contains('\\"quantidadeExtraida\\":1'),
            'Log deve reportar a quantidade de despesas extraídas, corpo: ' + logRequest.getBody());
    }

    @isTest
    static void testExtracaoSemDespesasPendentesEnviaLogComoSemDados() {
        CapturaTodasRequisicoesMock mock = new CapturaTodasRequisicoesMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new ExtracaoDespesasBigQueryService().extrairMes(Date.today().addMonths(2));
        Test.stopTest();

        HttpRequest logRequest = mock.requisicaoParaEndpoint('Grafana_Loki');
        System.assertNotEquals(null, logRequest, 'Mês sem despesas pendentes deve enviar um evento de log ao Grafana Loki');
        System.assert(logRequest.getBody().contains('\\"status\\":\\"sem_dados\\"'),
            'Log deve reportar status de sem_dados, corpo: ' + logRequest.getBody());
        System.assert(logRequest.getBody().contains('\\"quantidadeExtraida\\":0'),
            'Log deve reportar quantidade zero, corpo: ' + logRequest.getBody());
    }

    @isTest
    static void testExtracaoComFalhaNoCalloutEnviaLogComoFalha() {
        CapturaTodasRequisicoesMock mock = new CapturaTodasRequisicoesMock(500);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new ExtracaoDespesasBigQueryService().extrairMes(Date.today());
        Test.stopTest();

        HttpRequest logRequest = mock.requisicaoParaEndpoint('Grafana_Loki');
        System.assertNotEquals(null, logRequest, 'Falha no callout deve enviar um evento de log ao Grafana Loki');
        System.assert(logRequest.getBody().contains('\\"status\\":\\"falha\\"'),
            'Log deve reportar status de falha, corpo: ' + logRequest.getBody());
        System.assert(logRequest.getBody().contains('\\"quantidadeExtraida\\":0'),
            'Log deve reportar quantidade zero quando o callout falha, corpo: ' + logRequest.getBody());
    }

    // Mock genérico que responde ao mesmo status para qualquer endpoint (GCP ou
    // Grafana Loki) e guarda todas as requisições feitas na transação, pra
    // permitir inspecionar especificamente o evento enviado ao Loki.
    private class CapturaTodasRequisicoesMock implements HttpCalloutMock {
        private final Integer statusCode;
        private final List<HttpRequest> requisicoes = new List<HttpRequest>();

        CapturaTodasRequisicoesMock() {
            this(200);
        }

        CapturaTodasRequisicoesMock(Integer statusCode) {
            this.statusCode = statusCode;
        }

        public HttpResponse respond(HttpRequest req) {
            requisicoes.add(req);
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(statusCode < 300 ? '{"ok":true}' : '{"error":"mock"}');
            return res;
        }

        HttpRequest requisicaoParaEndpoint(String trechoDoEndpoint) {
            for (HttpRequest req : requisicoes) {
                if (req.getEndpoint().contains(trechoDoEndpoint)) {
                    return req;
                }
            }
            return null;
        }
    }
}
