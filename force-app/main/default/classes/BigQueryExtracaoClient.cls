/**
 * Callout para a Cloud Function de extração de despesas no GCP, via Named
 * Credential "GCP_Extracao_Despesas" (protocolo Password, gera o header
 * Authorization: Basic automaticamente). Responsabilidade única: enviar o
 * payload já pronto e devolver a resposta — quem decide o que fazer com o
 * resultado é o ExtracaoDespesasBigQueryService.
 */
public without sharing class BigQueryExtracaoClient {

    private static final String NAMED_CREDENTIAL_PATH = 'callout:GCP_Extracao_Despesas';

    public HttpResponse enviar(Map<String, Object> payload) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL_PATH);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(30000);

        return new Http().send(req);
    }
}
