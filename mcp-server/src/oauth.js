import crypto from 'node:crypto';
import { InvalidTokenError, InvalidGrantError } from '@modelcontextprotocol/sdk/server/auth/errors.js';

const SECRET = process.env.MCP_AUTH_TOKEN;

if (!SECRET) {
  throw new Error('Defina MCP_AUTH_TOKEN no ambiente — é a senha de login em /authorize e a chave de assinatura dos tokens OAuth.');
}

// Servidor OAuth 2.1 "stateless": em vez de guardar clients/códigos/tokens num banco
// (Lambda não tem estado persistente entre invocações), cada um deles é um blob
// assinado por HMAC contendo os próprios dados — verificar a assinatura é o mesmo
// que "buscar no banco". Isso torna impossível revogar um token individualmente
// antes de expirar, mas para um servidor pessoal de um usuário só é uma troca aceitável
// pela simplicidade de não precisar de um DynamoDB só para isso.
const CODE_TTL_MS = 60 * 1000; // código de autorização: só precisa sobreviver ao redirect do navegador
const ACCESS_TTL_MS = 60 * 60 * 1000; // 1h
const REFRESH_TTL_MS = 180 * 24 * 60 * 60 * 1000; // 180 dias

function sign(payload) {
  const json = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const sig = crypto.createHmac('sha256', SECRET).update(json).digest('base64url');
  return `${json}.${sig}`;
}

function verify(token) {
  if (typeof token !== 'string') return null;
  const dot = token.lastIndexOf('.');
  if (dot < 0) return null;
  const json = token.slice(0, dot);
  const sig = token.slice(dot + 1);
  const expected = crypto.createHmac('sha256', SECRET).update(json).digest('base64url');
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;

  let payload;
  try {
    payload = JSON.parse(Buffer.from(json, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
  if (typeof payload.exp === 'number' && Date.now() > payload.exp) return null;
  return payload;
}

/** Compara em tempo constante contra o MCP_AUTH_TOKEN — usado tanto no formulário de login quanto para aceitar o token estático direto no /mcp (uso manual/curl). */
export function isValidLoginToken(candidate) {
  if (typeof candidate !== 'string') return false;
  const a = Buffer.from(candidate);
  const b = Buffer.from(SECRET);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

export const clientsStore = {
  async getClient(clientId) {
    const data = verify(clientId);
    if (!data || data.t !== 'client') return undefined;
    return {
      client_id: clientId,
      redirect_uris: data.ru,
      client_name: data.cn,
      token_endpoint_auth_method: 'none',
      grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code']
    };
  },
  async registerClient(clientInfo) {
    // client_id é o próprio registro assinado — dispensa guardar clientes registrados em algum lugar.
    const clientId = sign({ t: 'client', ru: clientInfo.redirect_uris, cn: clientInfo.client_name });
    return {
      ...clientInfo,
      client_id: clientId,
      client_id_issued_at: Math.floor(Date.now() / 1000),
      token_endpoint_auth_method: 'none'
    };
  }
};

function mintTokens(clientId, scopes, resource) {
  const scope = (scopes || []).join(' ');
  const res = resource ? resource.toString() : undefined;
  const access_token = sign({ t: 'access', cid: clientId, scope, res, exp: Date.now() + ACCESS_TTL_MS });
  const refresh_token = sign({ t: 'refresh', cid: clientId, scope, res, exp: Date.now() + REFRESH_TTL_MS });
  return { access_token, token_type: 'bearer', expires_in: Math.floor(ACCESS_TTL_MS / 1000), refresh_token, scope };
}

export const provider = {
  clientsStore,

  // Só é chamado depois que o formulário em /authorize já validou a senha (ver http.js).
  async authorize(client, params, res) {
    const code = sign({
      t: 'code',
      cid: client.client_id,
      cc: params.codeChallenge,
      scope: (params.scopes || []).join(' '),
      res: params.resource ? params.resource.toString() : undefined,
      exp: Date.now() + CODE_TTL_MS
    });
    const target = new URL(params.redirectUri);
    target.searchParams.set('code', code);
    if (params.state !== undefined) target.searchParams.set('state', params.state);
    res.redirect(target.toString());
  },

  async challengeForAuthorizationCode(client, authorizationCode) {
    const data = verify(authorizationCode);
    if (!data || data.t !== 'code' || data.cid !== client.client_id) {
      throw new InvalidGrantError('Codigo de autorizacao invalido ou expirado.');
    }
    return data.cc;
  },

  async exchangeAuthorizationCode(client, authorizationCode) {
    const data = verify(authorizationCode);
    if (!data || data.t !== 'code' || data.cid !== client.client_id) {
      throw new InvalidGrantError('Codigo de autorizacao invalido ou expirado.');
    }
    return mintTokens(client.client_id, data.scope ? data.scope.split(' ') : [], data.res ? new URL(data.res) : undefined);
  },

  async exchangeRefreshToken(client, refreshToken, scopes, resource) {
    const data = verify(refreshToken);
    if (!data || data.t !== 'refresh' || data.cid !== client.client_id) {
      throw new InvalidGrantError('Refresh token invalido ou expirado.');
    }
    return mintTokens(
      client.client_id,
      scopes || (data.scope ? data.scope.split(' ') : []),
      resource || (data.res ? new URL(data.res) : undefined)
    );
  },

  async verifyAccessToken(token) {
    if (isValidLoginToken(token)) {
      return { token, clientId: 'static', scopes: [], expiresAt: Math.floor(Date.now() / 1000) + 3600 };
    }
    const data = verify(token);
    if (!data || data.t !== 'access') {
      throw new InvalidTokenError('Token invalido ou expirado.');
    }
    return {
      token,
      clientId: data.cid,
      scopes: data.scope ? data.scope.split(' ') : [],
      expiresAt: Math.floor(data.exp / 1000),
      resource: data.res ? new URL(data.res) : undefined
    };
  }
};
