@isTest
private class LokiLoggerServiceTest {

    @isTest
    static void testLogComRespostaDeSucesso() {
        Test.setMock(HttpCalloutMock.class, new LokiLoggerServiceMock(204));

        Test.startTest();
        LokiLoggerService.log('TesteBatch', 'batch_finish', 'sucesso', '707xx0000000001', new Map<String, Object>{ 'itensProcessados' => 3 });
        Test.stopTest();

        // Sucesso é "não lançar exceção" — LokiLoggerService nunca propaga falha de callout.
        System.assert(true, 'log() deve concluir sem lançar exceção quando o mock responde 204');
    }

    @isTest
    static void testLogComRespostaDeErroNaoLancaExcecao() {
        Test.setMock(HttpCalloutMock.class, new LokiLoggerServiceMock(500));

        Test.startTest();
        LokiLoggerService.log('TesteBatch', 'batch_finish', 'falha', null, null);
        Test.stopTest();

        System.assert(true, 'log() deve engolir erros de status HTTP sem propagar exceção');
    }

    @isTest
    static void testLogSemMockNaoLancaExcecao() {
        // Sem Test.setMock, a plataforma lança CalloutException ao tentar o callout real;
        // LokiLoggerService precisa capturar isso e nunca deixar vazar para quem chamou.
        Test.startTest();
        LokiLoggerService.log('TesteBatch', 'batch_finish', 'sucesso', 'idQualquer', new Map<String, Object>{ 'chave' => 'valor' });
        Test.stopTest();

        System.assert(true, 'log() deve engolir a exceção de callout não mockado');
    }
}
