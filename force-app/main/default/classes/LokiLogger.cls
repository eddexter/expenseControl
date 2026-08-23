/**
 * Envia eventos de observabilidade (execução de batches) para o Grafana Loki,
 * no momento em que o evento acontece — nunca por polling.
 * Ver claudeplanning/plano-observabilidade.md.
 *
 * Depende do Named Credential "Grafana_Loki" (protocolo Password Authentication,
 * gera o header Authorization: Basic automaticamente a partir do Instance ID /
 * Access Policy Token configurados em Setup > Named Credentials).
 *
 * Nunca lança exceção: uma falha ao logar não pode derrubar a batch que a chamou.
 */
public without sharing class LokiLogger {

    private static final String NAMED_CREDENTIAL_PATH = 'callout:Grafana_Loki/loki/api/v1/push';

    public static void log(String origem, String tipoEvento, String status, String idRastreio, Map<String, Object> detalhes) {
        try {
            Map<String, Object> linha = new Map<String, Object>{
                'origem' => origem,
                'tipoEvento' => tipoEvento,
                'status' => status,
                'idRastreio' => idRastreio,
                'timestamp' => DateTime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
            };
            if (detalhes != null) {
                linha.putAll(detalhes);
            }

            // Labels do stream ficam de baixa cardinalidade de propósito (Loki penaliza
            // séries demais no plano gratuito); o idRastreio vai só na linha do log.
            Map<String, Object> stream = new Map<String, Object>{
                'stream' => new Map<String, String>{ 'origem' => origem, 'tipo_evento' => tipoEvento, 'status' => status },
                'values' => new List<List<String>>{
                    new List<String>{ String.valueOf(System.currentTimeMillis() * 1000000L), JSON.serialize(linha) }
                }
            };
            Map<String, Object> payload = new Map<String, Object>{ 'streams' => new List<Object>{ stream } };

            HttpRequest req = new HttpRequest();
            req.setEndpoint(NAMED_CREDENTIAL_PATH);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(payload));
            req.setTimeout(5000);

            new Http().send(req);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'LokiLogger: falha ao enviar evento de observabilidade — ' + e.getMessage());
        }
    }
}
