// Cloud Function HTTP (2ª geração) — recebe o payload de Despesa__c enviado pelo Apex
// (ExtracaoDespesasBigQuery.cls, callout via Named Credential GCP_Extracao_Despesas) e
// grava no BigQuery via load job (não streaming insert — sem custo). Ver
// claudeplanning/plano-extracao-mvp4.md.
//
// Autenticação: a Cloud Function é pública (--allow-unauthenticated), protegida por um
// segredo compartilhado enviado como a senha de Basic Auth (o Named Credential do lado
// Salesforce gera esse header automaticamente a partir do protocolo Password). O
// username não é validado — só a senha importa.

import crypto from 'node:crypto';
import functions from '@google-cloud/functions-framework';
import { BigQuery } from '@google-cloud/bigquery';

const PROJECT_ID = process.env.GCP_PROJECT_ID;
const DATASET = process.env.BQ_DATASET || 'expense_control';
const TABLE = process.env.BQ_TABLE || 'despesas_raw';
const SHARED_SECRET = process.env.INGEST_SHARED_SECRET;

const bigquery = new BigQuery({ projectId: PROJECT_ID });

/** Extrai a senha de um header "Authorization: Basic base64(usuario:senha)". */
function extrairSenhaBasicAuth(header) {
  if (!header || !header.startsWith('Basic ')) {
    return null;
  }
  try {
    const decodificado = Buffer.from(header.slice('Basic '.length), 'base64').toString('utf8');
    const separador = decodificado.indexOf(':');
    return separador === -1 ? decodificado : decodificado.slice(separador + 1);
  } catch {
    return null;
  }
}

/** Comparação em tempo constante, tolerante a tamanhos diferentes (evita lançar exceção). */
function segredosIguais(a, b) {
  const bufA = Buffer.from(a || '', 'utf8');
  const bufB = Buffer.from(b || '', 'utf8');
  if (bufA.length !== bufB.length) {
    return false;
  }
  return crypto.timingSafeEqual(bufA, bufB);
}

/** Grava as linhas no BigQuery via load job (table.createWriteStream = LOAD, não streaming insert). */
function carregarNoBigQuery(linhasNdjson) {
  return new Promise((resolve, reject) => {
    const table = bigquery.dataset(DATASET).table(TABLE);
    const stream = table.createWriteStream({
      sourceFormat: 'NEWLINE_DELIMITED_JSON',
      writeDisposition: 'WRITE_APPEND',
    });
    stream.on('error', reject);
    stream.on('job', (job) => {
      job.on('complete', () => resolve(job));
      job.on('error', reject);
    });
    stream.end(linhasNdjson);
  });
}

functions.http('extrairDespesas', async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Método não suportado, use POST.' });
    return;
  }

  if (!SHARED_SECRET) {
    console.error('INGEST_SHARED_SECRET não configurado no ambiente da function.');
    res.status(500).json({ error: 'Configuração ausente no servidor.' });
    return;
  }

  const senhaRecebida = extrairSenhaBasicAuth(req.headers['authorization']);
  if (!senhaRecebida || !segredosIguais(senhaRecebida, SHARED_SECRET)) {
    res.status(401).json({ error: 'Não autorizado.' });
    return;
  }

  const despesas = req.body && req.body.despesas;
  if (!Array.isArray(despesas) || despesas.length === 0) {
    res.status(400).json({ error: 'Payload inválido: esperado { despesas: [...] } com ao menos um item.' });
    return;
  }

  const extractionTimestamp = new Date().toISOString();
  const linhas = despesas.map((despesa) => ({ ...despesa, extraction_timestamp: extractionTimestamp }));
  const ndjson = linhas.map((linha) => JSON.stringify(linha)).join('\n');

  try {
    await carregarNoBigQuery(ndjson);
    res.status(200).json({ ok: true, linhasGravadas: linhas.length });
  } catch (err) {
    console.error('Falha ao gravar no BigQuery:', err);
    res.status(500).json({ error: 'Falha ao gravar no BigQuery.' });
  }
});
