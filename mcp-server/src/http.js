import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { createMcpExpressApp } from '@modelcontextprotocol/sdk/server/express.js';
import { mcpAuthRouter, getOAuthProtectedResourceMetadataUrl } from '@modelcontextprotocol/sdk/server/auth/router.js';
import { requireBearerAuth } from '@modelcontextprotocol/sdk/server/auth/middleware/bearerAuth.js';
import express from 'express';
import { createServer } from './server.js';
import { provider, clientsStore, isValidLoginToken } from './oauth.js';

const PORT = Number(process.env.PORT) || 8080;
// Precisa ser a URL pública real (Function URL da Lambda) para o discovery OAuth funcionar.
// Em localhost, o SDK permite issuer em HTTP (exceção só pra desenvolvimento).
const issuerUrl = new URL(process.env.MCP_PUBLIC_URL || `http://localhost:${PORT}`);
const resourceUrl = new URL('/mcp', issuerUrl);

const app = createMcpExpressApp({ host: process.env.MCP_HTTP_HOST || '0.0.0.0' });
// A Lambda Web Adapter atua como um proxy reverso na frente do Express (define X-Forwarded-For);
// sem isso o express-rate-limit (usado internamente pelo router OAuth do SDK) loga erro a cada requisição.
app.set('trust proxy', 1);
app.use(express.urlencoded({ extended: false }));

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function renderLoginForm({ error, hidden }) {
  const hiddenInputs = Object.entries(hidden)
    .filter(([, v]) => v !== undefined && v !== null && v !== '')
    .map(([k, v]) => `<input type="hidden" name="${escapeHtml(k)}" value="${escapeHtml(v)}">`)
    .join('\n');
  return `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><title>Despesas MCP</title>
<style>
body{font-family:system-ui,-apple-system,sans-serif;max-width:360px;margin:15vh auto;padding:0 16px;color:#1a1a1a}
h1{font-size:1.2rem}
input[type=password]{width:100%;box-sizing:border-box;padding:10px;font-size:16px;margin:8px 0;border:1px solid #ccc;border-radius:6px}
button{width:100%;padding:10px;font-size:16px;border:0;border-radius:6px;background:#1a1a1a;color:#fff;cursor:pointer}
.error{color:#b00020;font-size:0.9rem;margin-bottom:8px}
</style></head>
<body>
<h1>Autorizar acesso — Despesas MCP</h1>
${error ? `<p class="error">${escapeHtml(error)}</p>` : ''}
<form method="POST" action="/authorize">
${hiddenInputs}
<label for="token">Token de acesso (MCP_AUTH_TOKEN)</label>
<input type="password" id="token" name="token" autofocus required>
<button type="submit">Autorizar</button>
</form>
</body></html>`;
}

// Substitui o /authorize padrão do SDK por um que exige a senha (MCP_AUTH_TOKEN) antes
// de emitir o código — o SDK não modela esse "passo de login" porque normalmente quem
// implementa OAuthServerProvider delega a autenticação a outro sistema (Google, GitHub etc.).
// Aqui o "outro sistema" somos nós mesmos, com um único usuário.
async function handleAuthorize(req, res) {
  const params = req.method === 'POST' ? req.body : req.query;
  const { client_id, redirect_uri, response_type, code_challenge, code_challenge_method, scope, state, resource, token } = params;

  if (!client_id) return res.status(400).send('client_id ausente.');
  const client = await clientsStore.getClient(client_id);
  if (!client) return res.status(400).send('client_id inválido ou expirado — reinicie o cadastro do conector.');

  const redirectUri = redirect_uri || (client.redirect_uris.length === 1 ? client.redirect_uris[0] : undefined);
  if (!redirectUri || !client.redirect_uris.includes(redirectUri)) {
    return res.status(400).send('redirect_uri não registrado para este client.');
  }
  if (response_type !== 'code' || !code_challenge || code_challenge_method !== 'S256') {
    return res.status(400).send('Parâmetros de autorização inválidos (esperado PKCE com S256).');
  }

  const hidden = { client_id, redirect_uri: redirectUri, response_type, code_challenge, code_challenge_method, scope, state, resource };

  if (req.method !== 'POST' || !token) {
    return res.status(200).send(renderLoginForm({ hidden }));
  }
  if (!isValidLoginToken(token)) {
    return res.status(401).send(renderLoginForm({ error: 'Token incorreto.', hidden }));
  }

  await provider.authorize(
    client,
    {
      state,
      scopes: scope ? scope.split(' ') : [],
      redirectUri,
      codeChallenge: code_challenge,
      resource: resource ? new URL(resource) : undefined
    },
    res
  );
}

app.get('/authorize', handleAuthorize);
app.post('/authorize', handleAuthorize);

// Metadados de descoberta (RFC 8414 / RFC 9728), /register (RFC 7591) e /token — tudo
// gerado pelo SDK a partir do provider acima. clientIdGeneration:false porque o
// clientsStore já gera o próprio client_id (auto-assinado, sem precisar de banco).
app.use(
  mcpAuthRouter({
    provider,
    issuerUrl,
    resourceServerUrl: resourceUrl,
    scopesSupported: ['despesas'],
    resourceName: 'Despesas MCP',
    clientRegistrationOptions: { clientIdGeneration: false }
  })
);

app.use(
  '/mcp',
  requireBearerAuth({ verifier: provider, resourceMetadataUrl: getOAuthProtectedResourceMetadataUrl(resourceUrl) })
);

app.post('/mcp', async (req, res) => {
  const server = createServer();
  try {
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
    res.on('close', () => {
      transport.close();
      server.close();
    });
  } catch (err) {
    console.error('Erro ao tratar requisição MCP:', err);
    if (!res.headersSent) {
      res.status(500).json({
        jsonrpc: '2.0',
        error: { code: -32603, message: 'Erro interno do servidor.' },
        id: null
      });
    }
  }
});

app.get('/mcp', (_req, res) => {
  res.status(405).json({
    jsonrpc: '2.0',
    error: { code: -32000, message: 'Method not allowed.' },
    id: null
  });
});

app.delete('/mcp', (_req, res) => {
  res.status(405).json({
    jsonrpc: '2.0',
    error: { code: -32000, message: 'Method not allowed.' },
    id: null
  });
});

app.listen(PORT, () => {
  console.log(`Servidor MCP (Streamable HTTP + OAuth) ouvindo na porta ${PORT}`);
  console.log(`Issuer OAuth: ${issuerUrl.href}`);
});
