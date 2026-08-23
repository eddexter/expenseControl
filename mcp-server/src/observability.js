import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '.env') });

// Observabilidade — Grafana Cloud (Loki). Ver claudeplanning/plano-observabilidade.md.
// Envio é reativo (disparado pela própria ação do MCP), nunca por polling.
// Se as variáveis não estiverem configuradas, o envio é apenas desabilitado —
// isso nunca impede a ação principal (criar/quitar despesa) de funcionar.
const LOKI_URL = process.env.GRAFANA_LOKI_URL;
const LOKI_USER = process.env.GRAFANA_LOKI_USER;
const LOKI_TOKEN = process.env.GRAFANA_LOKI_TOKEN;

const enabled = Boolean(LOKI_URL && LOKI_USER && LOKI_TOKEN);
if (!enabled) {
  console.warn(
    '[observability] GRAFANA_LOKI_URL/GRAFANA_LOKI_USER/GRAFANA_LOKI_TOKEN não configurados — eventos de observabilidade do MCP não serão enviados.'
  );
}

/**
 * Envia um evento estruturado para o Grafana Loki, no momento em que ele acontece.
 * Nunca lança exceção: uma falha ao logar não pode derrubar a ação de negócio
 * (criar/quitar despesa) que disparou o evento.
 *
 * @param {string} tipoEvento - ex: 'criar_despesa', 'quitar_despesa'
 * @param {string} status - ex: 'sucesso', 'falha', 'bloqueado'
 * @param {string} [idRastreio] - Id do registro Salesforce envolvido (Despesa__c), quando houver
 * @param {object} [detalhes] - campos adicionais livres para o corpo do log (não viram label do Loki)
 */
export async function logEvent({ tipoEvento, status, idRastreio, detalhes }) {
  if (!enabled) return;

  try {
    const timestampNs = `${Date.now()}000000`;
    const linha = JSON.stringify({
      origem: 'mcp',
      tipoEvento,
      status,
      idRastreio: idRastreio || null,
      timestamp: new Date().toISOString(),
      ...(detalhes || {})
    });

    const auth = Buffer.from(`${LOKI_USER}:${LOKI_TOKEN}`).toString('base64');
    const payload = {
      streams: [
        {
          // Labels ficam de baixa cardinalidade de propósito (Loki penaliza séries demais);
          // qualquer identificador específico do caso vai só na linha do log, não aqui.
          stream: { origem: 'mcp', tipo_evento: tipoEvento, status },
          values: [[timestampNs, linha]]
        }
      ]
    };

    const res = await fetch(`${LOKI_URL.replace(/\/$/, '')}/loki/api/v1/push`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Basic ${auth}` },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(3000)
    });

    if (!res.ok) {
      const text = await res.text();
      console.error(`[observability] Falha ao enviar evento ao Loki (${res.status}): ${text}`);
    }
  } catch (err) {
    console.error(`[observability] Erro ao enviar evento ao Loki: ${err.message}`);
  }
}
