import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const LOGIN_URL = process.env.SF_LOGIN_URL;
const CLIENT_ID = process.env.SF_CLIENT_ID;
const CLIENT_SECRET = process.env.SF_CLIENT_SECRET;
const API_VERSION = process.env.SF_API_VERSION || '62.0';

if (!LOGIN_URL || !CLIENT_ID || !CLIENT_SECRET) {
  throw new Error(
    'Defina SF_LOGIN_URL, SF_CLIENT_ID e SF_CLIENT_SECRET no arquivo mcp-server/.env (veja .env.example).'
  );
}

let cachedToken = null;

async function getAccessToken() {
  if (cachedToken && cachedToken.expiresAt > Date.now()) {
    return cachedToken;
  }

  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    client_id: CLIENT_ID,
    client_secret: CLIENT_SECRET
  });

  const res = await fetch(`${LOGIN_URL}/services/oauth2/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Falha ao autenticar no Salesforce (${res.status}): ${text}`);
  }

  const json = await res.json();
  cachedToken = {
    accessToken: json.access_token,
    instanceUrl: json.instance_url,
    // client_credentials não retorna expires_in de forma confiável; renovamos preventivamente
    expiresAt: Date.now() + 25 * 60 * 1000
  };
  return cachedToken;
}

async function sfFetch(pathAndQuery, options = {}) {
  const { accessToken, instanceUrl } = await getAccessToken();
  return fetch(`${instanceUrl}${pathAndQuery}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      ...(options.headers || {})
    }
  });
}

export async function querySOQL(soql) {
  const res = await sfFetch(`/services/data/v${API_VERSION}/query?q=${encodeURIComponent(soql)}`);
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Erro na consulta SOQL (${res.status}): ${text}`);
  }
  const json = await res.json();
  return json.records;
}

export async function updateRecord(sobject, id, fields) {
  const res = await sfFetch(`/services/data/v${API_VERSION}/sobjects/${sobject}/${id}`, {
    method: 'PATCH',
    body: JSON.stringify(fields)
  });
  if (res.status !== 204) {
    const text = await res.text();
    throw new Error(`Erro ao atualizar ${sobject} ${id} (${res.status}): ${text}`);
  }
  return true;
}
