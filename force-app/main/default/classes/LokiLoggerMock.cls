/**
 * Mock de callout HTTP reutilizável para testar o LokiLogger (e qualquer batch
 * que dispare um log via LokiLogger.log no finish()) sem depender do Grafana real.
 */
@isTest
public class LokiLoggerMock implements HttpCalloutMock {

    private final Integer statusCode;

    public LokiLoggerMock() {
        this(204); // resposta padrão de sucesso do Loki push
    }

    public LokiLoggerMock(Integer statusCode) {
        this.statusCode = statusCode;
    }

    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setBody(statusCode < 300 ? '' : '{"error":"mock"}');
        return res;
    }
}
