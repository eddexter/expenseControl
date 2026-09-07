/**
 * Mock de callout HTTP reutilizável para testar o LokiLoggerService (e
 * qualquer classe que dispare um log via LokiLoggerService.log) sem depender
 * do Grafana real.
 */
@isTest
public class LokiLoggerServiceMock implements HttpCalloutMock {

    private final Integer statusCode;

    public LokiLoggerServiceMock() {
        this(204); // resposta padrão de sucesso do Loki push
    }

    public LokiLoggerServiceMock(Integer statusCode) {
        this.statusCode = statusCode;
    }

    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setBody(statusCode < 300 ? '' : '{"error":"mock"}');
        return res;
    }
}
