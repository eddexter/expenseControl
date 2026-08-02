# expenseControl

Controle de despesas mensais em Salesforce (SFDX), com conexão via MCP para permitir que o Claude consulte e concilie despesas.

## Stack

- Salesforce DX (`sfdx-project.json`, API v66.0)
- Apex (classes de batch/schedule)
- Acesso aos objetos e abas controlado pelo Permission Set `Despesas` (não pelo perfil)

## Modelo de dados

### Carteira__c (Carteiras)

Contas/carteiras onde as despesas são pagas (conta corrente, cartão, dinheiro etc.).

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| Name | Text | — | Nome da carteira (ex: Nubank) |
| Tipo__c | Picklist | Sim | Conta Corrente, Poupança, Cartão de Crédito, Dinheiro em Espécie, Investimento, Outro |
| Instituicao__c | Text(80) | Não | Instituição financeira |
| Ativa__c | Checkbox | — | Default `true`. Indica se a carteira está em uso |
| Observacoes__c | LongTextArea(32768) | Não | Observações livres |

### Recorrencia__c (Recorrências)

Modelo de uma despesa que se repete mensalmente (ex: aluguel, assinaturas). O batch `CriarDespesasRecorrentesBatch` usa esses registros para gerar as despesas do mês.

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| Name (REC-{0000}) | AutoNumber | — | Numeração automática |
| Descricao__c | Text(120) | Sim | Descrição da recorrência |
| Valor__c | Currency(16,2) | Sim | Valor esperado |
| Dia_Vencimento__c | Number(2,0) | Sim | Dia do mês de vencimento (ajustado para o último dia do mês quando o mês for mais curto) |
| Data_Inicio__c | Date | Sim | Início da vigência |
| Data_Fim__c | Date | Não | Fim da vigência (em branco = sem data de término) |
| Ativa__c | Checkbox (fórmula) | — | `Data_Inicio__c <= HOJE() && (Data_Fim__c em branco OU Data_Fim__c >= HOJE())` |
| Carteira_Padrao__c | Lookup(Carteira__c) | Sim | Carteira usada por padrão ao gerar a despesa |
| Categoria__c | Picklist | Não | Moradia, Transporte, Alimentação, Lazer, Assinaturas, Saúde, Educação, Outros |
| Tipo_Pagamento__c | Picklist | Não | Boleto, Débito Automático, Pix, Cartão de Crédito |
| Variavel__c | Checkbox | — | Default `false`. Indica se o valor pode variar de um mês para outro (ex: cartão de crédito, conta de luz) |
| Empresa__c | Text(120) | Não | Nome da empresa como aparece no recibo/comprovante, para facilitar identificação via MCP |
| Observacoes__c | LongTextArea(32768) | Não | Observações livres |

### Despesa__c (Despesas)

Lançamento mensal de uma despesa, gerado automaticamente a partir de uma recorrência ativa ou criado manualmente.

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| Name (DESP-{00000}) | AutoNumber | — | Numeração automática |
| Descricao__c | Text(120) | Sim | Descrição da despesa |
| Valor__c | Currency(16,2) | Sim | Valor da despesa |
| Data_Vencimento__c | Date | Sim | Data de vencimento |
| Data_Pagamento__c | Date | Não | Data em que foi paga |
| Status__c | Picklist | Sim | Pendente (default), Pago, Cancelado |
| Carteira__c | Lookup(Carteira__c) | Sim | Carteira usada no pagamento |
| Recorrencia__c | Lookup(Recorrencia__c) | Não | Recorrência de origem, quando aplicável |
| Categoria__c | Picklist | Não | Mesmos valores de Recorrencia__c.Categoria__c |
| Tipo_Pagamento__c | Picklist | Não | Boleto, Débito Automático, Pix, Cartão de Crédito |
| Variavel__c | Checkbox | — | Default `false`. Indica se o valor pode variar de um mês para outro |
| Empresa__c | Text(120) | Não | Nome da empresa como aparece no recibo/comprovante, para facilitar identificação e quitação via MCP |
| Observacoes__c | LongTextArea(32768) | Não | Observações livres |

## Automação

### CriarDespesasRecorrentesBatch

Classe `Database.Batchable` + `Schedulable` que gera as despesas do mês corrente a partir das recorrências ativas.

- Seleciona todas as `Recorrencia__c` com `Ativa__c = true`.
- Calcula a data de vencimento do mês (ajustando `Dia_Vencimento__c` para o último dia do mês quando necessário).
- É idempotente: não cria uma nova despesa se já existir uma `Despesa__c` para aquela recorrência no mês corrente.
- Copia `Descricao__c`, `Valor__c`, `Carteira_Padrao__c`, `Categoria__c`, `Tipo_Pagamento__c`, `Variavel__c` e `Empresa__c` da recorrência para a despesa criada.
- Testes em `CriarDespesasRecorrentesBatchTest` cobrem: criação para recorrência ativa, não duplicação ao rodar o batch duas vezes no mesmo mês, e não criação para recorrência inativa.

## Abas

- Abas customizadas: `Carteira__c`, `Recorrencia__c`, `Despesa__c`.
- O acesso é concedido via Permission Set `Despesas` (ver abaixo), não via perfil. O perfil `Admin` não faz parte do pacote — não versionamos/alteramos perfis neste projeto.

## List Views

Cada objeto tem uma list view `Todos` (`filterScope: Everything`, sem filtros — mostra todos os registros), com as colunas relevantes (campos `LongTextArea` como `Observacoes__c` ficam de fora por não serem suportados como coluna de list view):

- **Carteira__c**: Name, Tipo__c, Instituicao__c, Ativa__c
- **Recorrencia__c**: Name, Descricao__c, Valor__c, Categoria__c, Tipo_Pagamento__c, Empresa__c, Variavel__c, Carteira_Padrao__c, Dia_Vencimento__c, Data_Inicio__c, Data_Fim__c, Ativa__c
- **Despesa__c**: Name, Descricao__c, Valor__c, Status__c, Data_Vencimento__c, Data_Pagamento__c, Carteira__c, Categoria__c, Tipo_Pagamento__c, Empresa__c, Variavel__c, Recorrencia__c

A list view nativa "Recent" (Mais Recentes) **não é gerenciável via Metadata API** (não é retornada por `list metadata`, nem por retrieve explícito, para nenhum objeto padrão ou customizado) — não é possível versioná-la ou definir suas colunas via pacote. Decisão: não mexer nela; `Todos` é a visão principal usada no app.

## Page Layouts

Cada objeto customizado já vem com um layout padrão gerado automaticamente pelo Salesforce na criação do objeto (existe mesmo sem nunca termos feito deploy de nenhum `Layout` — não aparece no retrieve até você mexer nele ou explicitamente pedir). Esse layout do sistema é o que os perfis realmente usam por padrão; um `Layout` novo que a gente cria via metadata **não vira automaticamente o default** — fica como um layout adicional, não atribuído, a menos que seja explicitamente atribuído por perfil.

Nos 3 objetos, o layout que criamos via deploy (`Carteira Layout`, `Despesa Layout`, `Recorrência Layout`) foi **apagado na org** (editado/removido diretamente no Setup) — só sobrou o layout padrão do sistema (`Layout de Carteira`, `Layout de Despesa`, `Layout de Recorrência`), que passou a ser editado à mão por lá. Os arquivos locais órfãos somem sozinhos num próximo `sf project retrieve` (source tracking do scratch org reconcilia a exclusão).

Os 3 layouts de sistema (`Layout de Carteira`, `Layout de Despesa`, `Layout de Recorrência`) foram completados com todos os campos que faltavam, na seção "Information" já existente (junto de `OwnerId`):
- `Despesa__c-Layout de Despesa`: adicionados `Categoria__c`, `Tipo_Pagamento__c`, `Variavel__c`, `Empresa__c`, `Data_Pagamento__c`, `Recorrencia__c`, `Observacoes__c`.
- `Recorrencia__c-Layout de Recorrência`: adicionados `Ativa__c` (readonly, é fórmula), `Categoria__c`, `Tipo_Pagamento__c`, `Variavel__c`, `Empresa__c`, `Data_Fim__c`, `Observacoes__c`.
- `Carteira__c-Layout de Carteira`: adicionados `Instituicao__c`, `Ativa__c`, `Observacoes__c`.

## Lightning Record Pages

Cada objeto tem uma Lightning Record Page (`Carteira_Record_Page`, `Despesa_Record_Page`, `Recorrencia_Record_Page`), atribuída como página padrão de visualização **especificamente para o aplicativo Despesas**, via `actionOverrides` (`actionName: View`) em `Despesas.app-meta.xml` — não é uma atribuição por perfil, então outros apps/perfis continuam usando a página padrão gerada automaticamente pelo Salesforce. `actionName: Edit` não é suportado como override de app (erro de deploy "A ação Edit não pode ser substituída") — só `View` foi sobrescrita.

`Carteira_Record_Page` continua no padrão original: `force:highlightsPanel` (header) + `force:detailPanel` (main — mostra os campos do Page Layout clássico atribuído ao objeto) + `force:relatedListContainer` (sidebar).

`Despesa_Record_Page` e `Recorrencia_Record_Page` foram depois editadas manualmente no Lightning App Builder (fora do fluxo `sf project deploy`) para usar campos individuais via Dynamic Forms em vez do `force:detailPanel`, e o resultado foi trazido para o repo com `sf project retrieve start`. É a referência real de como o Dynamic Forms funciona neste schema (não documentei via tentativa/erro): cada campo é um `itemInstances > fieldInstance` dentro de uma região `type: Facet` (não `main`/`sidebar` direto), `fieldItem` usa só `Record.<Campo>` (sem prefixo do objeto), e `uiBehavior` é minúsculo (`required`/`readonly`/`none`).

## Compact Layouts

Criados na org e atribuídos como compact layout padrão (`compactLayoutAssignment` no `.object-meta.xml` do objeto), usados no Highlights Panel das Record Pages:

- **Carteira__c** → `CarteiraCompacto`: `Name`, `Ativa__c`, `Tipo__c`, `Instituicao__c`.
- **Recorrencia__c** → `RecorrenciaCompacto`: `Name`, `Empresa__c`, `Dia_Vencimento__c`, `Valor__c`.
- **Despesa__c** → `DespesaCompacto`: `Name`, `Empresa__c`, `Data_Vencimento__c`, `Status__c`, `Valor__c`.

## Aplicativo Despesas

Lightning App `Despesas` com apenas os 3 objetos do controle de despesas no menu, nesta ordem: **Despesas**, **Recorrências**, **Carteira**.

### Permission Set `Despesas`

Concede tudo que é necessário para atuar no app:

- Acesso ao aplicativo `Despesas` (`applicationVisibilities`).
- CRUD completo (criar, ler, editar, excluir) em `Carteira__c`, `Recorrencia__c` e `Despesa__c`.
- FLS (leitura/edição) em todos os campos customizados dos 3 objetos — exceto campos obrigatórios (sempre acessíveis automaticamente quando o objeto é acessível, não aceitam entrada explícita de `fieldPermissions`) e o campo fórmula `Recorrencia__c.Ativa__c` (somente leitura, por ser calculado).
- Abas `Carteira__c`, `Recorrencia__c` e `Despesa__c` visíveis (`tabSettings`).

## Integração MCP customizada (conciliação de comprovantes)

O MCP oficial da Salesforce (`@salesforce/mcp`) só expõe leitura (`run_soql_query`) — sem DML. Como o objetivo é o Claude **identificar e quitar** despesas a partir de um comprovante de pagamento, construímos um servidor MCP próprio em `mcp-server/` (Node.js).

**Escopo**: o fluxo cobre pagamentos manuais conferidos por comprovante — Boleto, Pix, Cartão de Crédito. Despesas com `Tipo_Pagamento__c = 'Débito Automático'` **não** passam por esse matching: a baixa delas é automática (outro mecanismo, ainda não construído), então elas ficam de fora do fluxo de conciliação por comprovante.

### Autenticação — Connected App `Despesas MCP`

- Criado diretamente na org via OAuth **Client Credentials Flow** (`isClientCredentialEnabled`, `oauthClientCredentialUser` = usuário da org, escopo `Api`, `ipRelaxation = BYPASS`).
- **Não faz parte do pacote/git**: a metadata do Connected App embute `consumerKey`/`consumerSecret` em texto puro, então foi implantada uma única vez e o arquivo (`force-app/main/default/connectedApps/Despesas_MCP.connectedApp-meta.xml`) foi removido do disco depois — o mesmo padrão usado para o perfil `Admin`. As credenciais reais vivem só em `mcp-server/.env` (gitignorado).
- Para recriar/rotacionar: gerar novos valores aleatórios para `consumerKey`/`consumerSecret`, recriar o XML do Connected App com esse formato, `sf project deploy start`, atualizar `mcp-server/.env`, e apagar o XML de novo.

### Servidor `mcp-server/`

Node.js (ESM) usando `@modelcontextprotocol/sdk` + `zod`, autenticação via REST (`fetch`, sem `jsforce`). Configuração em `mcp-server/.env` (veja `mcp-server/.env.example`): `SF_LOGIN_URL`, `SF_CLIENT_ID`, `SF_CLIENT_SECRET`, `SF_API_VERSION`.

Registrado no Claude Code via `.mcp.json` na raiz do projeto (`despesas-salesforce` → `node mcp-server/src/index.js`). Requer Node.js instalado (LTS, instalado via `winget install OpenJS.NodeJS.LTS`).

**Ferramentas expostas:**

- `buscar_despesas_pendentes` — lista `Despesa__c` com `Status__c = 'Pendente'`, com filtros opcionais de mês, empresa e carteira.
- `identificar_despesa_por_comprovante` — recebe os dados extraídos de um comprovante (empresa, descrição, valor, data, tipo de pagamento) e retorna os candidatos entre as despesas pendentes, ordenados por pontuação de confiança (`mcp-server/src/matching.js`).
- `quitar_despesa` — atualiza `Status__c = 'Pago'` e `Data_Pagamento__c`; opcionalmente ajusta `Valor__c`. Recusa (a menos que `forcar = true`) quando a despesa já não está `Pendente`, ou quando o valor pago diverge do cadastrado numa despesa **não variável**.

**Heurística de matching** (`scoreCandidate`, 0–100):

| Sinal | Peso | Observação |
|---|---|---|
| `Empresa__c` | até 50 | Maior peso — normaliza acentos/maiúsculas e remove sufixos (LTDA, S.A. etc.) antes de comparar |
| `Descricao__c` | até 20 | Reforça o match quando `Empresa__c` está vago, ausente ou não bate exatamente (comparação por termos em comum) |
| `Tipo_Pagamento__c` | +10 | Sinal de apoio |
| `Valor__c` | até 25 (ou -15) | **Depende de `Variavel__c`**: se `false`, exige quase-exatidão (divergência maior é sinal *negativo*); se `true` (ex: cartão de crédito, conta de luz), tolera diferença de até 30% com peso menor, já que o valor pode variar mês a mês |
| `Data_Vencimento__c` | até 10 | Proximidade entre a data do comprovante e o vencimento, como desempate |

Confiança: `alta` (≥70), `média` (40–69), `baixa` (<40). O Claude deve sempre confirmar com o usuário antes de chamar `quitar_despesa`, exceto quando a confiança é alta e o valor bate.

### Acesso remoto (Claude.ai / app mobile) via AWS Lambda

`mcp-server/src/index.js` (stdio) continua sendo o modo usado pelo Claude Code local. Para usar as mesmas ferramentas em outros dispositivos (Claude.ai web, app mobile), o servidor também expõe um modo HTTP em `mcp-server/src/http.js`, hospedado como **AWS Lambda** (deploy real em `sa-east-1`, conta `637423214195`, função `despesas-mcp-server`, URL em `mcp-server/.env` → `MCP_PUBLIC_URL`).

- Ambos os modos compartilham a mesma lógica de ferramentas (`mcp-server/src/server.js`).
- `src/http.js` implementa o transporte Streamable HTTP do MCP em modo stateless (uma instância de servidor por requisição — adequado a Lambda).
- **Empacotamento: zip + [AWS Lambda Web Adapter](https://github.com/awslabs/aws-lambda-web-adapter) como Layer** (não como container/Docker — evita a dependência do Docker, que não estava disponível no ambiente de deploy). `mcp-server/run.sh` (`node src/http.js`) é o `--handler`; a Web Adapter (`AWS_LAMBDA_EXEC_WRAPPER=/opt/bootstrap`) traduz eventos da Function URL para requisições HTTP normais. Existe também um `mcp-server/Dockerfile` alternativo (não testado) para quem preferir container.

#### Autenticação: OAuth 2.1, não só um Bearer token fixo

A primeira versão só exigia `Authorization: Bearer <MCP_AUTH_TOKEN>` fixo. O **Claude.ai recusa esse modelo** — o fluxo de "Adicionar conector personalizado" exige um servidor OAuth de verdade (descoberta via `/.well-known/...`, registro dinâmico de client — RFC 7591, PKCE). `mcp-server/src/oauth.js` implementa isso usando o `OAuthServerProvider` que o próprio `@modelcontextprotocol/sdk` já traz (`server/auth/router.js`), então não foi necessário escrever RFC 7591/PKCE/discovery na mão — só a peça específica deste projeto: **um único usuário, autenticado por senha** (o próprio `MCP_AUTH_TOKEN`) em vez de um provedor social (Google/GitHub/etc.).

- **Sem banco de dados**: como a Lambda não tem estado persistente entre invocações, clients registrados, códigos de autorização e tokens (access + refresh) são todos *blobs assinados por HMAC-SHA256* (chave = `MCP_AUTH_TOKEN`) contendo os próprios dados — verificar a assinatura é o equivalente a "buscar no banco". Único efeito colateral: não dá pra revogar um token individual antes de expirar (não há registro central pra apagar). Aceitável para uso pessoal; o TTL do access token é curto (1h) e do código de autorização é bem curto (60s).
- **`/authorize`**: o SDK entrega esse endpoint pronto, mas ele não modela um "passo de login" (normalmente delega pra outro provedor). Por isso `http.js` intercepta `GET`/`POST /authorize` **antes** do router do SDK: mostra um formulário HTML pedindo o `MCP_AUTH_TOKEN` como senha, e só chama `provider.authorize()` (que emite o código e redireciona) depois de validar.
- `/register`, `/token`, `/.well-known/oauth-authorization-server` e `/.well-known/oauth-protected-resource/mcp` são gerados automaticamente pelo `mcpAuthRouter` do SDK a partir do provider.
- `/mcp` continua aceitando o `MCP_AUTH_TOKEN` estático direto no header `Authorization: Bearer` (para curl/teste manual), além de qualquer access token emitido pelo fluxo OAuth.
- **Limitação conhecida da AWS**: a Function URL renomeia o header de resposta `WWW-Authenticate` para `x-amzn-Remapped-www-authenticate` (não documentado, observado empiricamente). Se a descoberta automática do Claude.ai falhar por causa disso, o fallback é ele tentar `/.well-known/oauth-authorization-server` direto na URL base — o que funciona (testado via curl simulando o `redirect_uri` do Claude.ai ponta a ponta: registro → login → troca de código → `/mcp`).

#### Deploy (rodar localmente, requer AWS CLI configurado — `aws configure` ou SSO)

```bash
cd mcp-server

# 1. Empacotar: instala deps de produção numa pasta limpa e gera dist/function.zip
#    (run.sh vai com permissão 0755 dentro do zip via `archiver`, já que o
#    Compress-Archive do Windows não preserva permissões Unix)
npm run build:lambda

# 2. Gerar o token de autenticação (é a senha de login E a chave de assinatura OAuth)
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"

# 3. Papel IAM de execução (logging básico)
aws iam create-role --role-name despesas-mcp-lambda-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name despesas-mcp-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# 4. Criar a função (layer da Web Adapter — ARN varia por região, confirme a versão atual)
aws lambda create-function \
  --region <region> --function-name despesas-mcp-server \
  --runtime nodejs20.x --handler run.sh \
  --role arn:aws:iam::<account-id>:role/despesas-mcp-lambda-role \
  --layers arn:aws:lambda:<region>:753240598075:layer:LambdaAdapterLayerX86:28 \
  --timeout 30 --memory-size 512 --zip-file fileb://dist/function.zip \
  --environment "Variables={AWS_LAMBDA_EXEC_WRAPPER=/opt/bootstrap,PORT=8080,MCP_PUBLIC_URL=https://<id>.lambda-url.<region>.on.aws,SF_LOGIN_URL=...,SF_CLIENT_ID=...,SF_CLIENT_SECRET=...,SF_API_VERSION=62.0,MCP_AUTH_TOKEN=...}"
# MCP_PUBLIC_URL só se conhece depois do passo 6 — crie a função sem essa variável e
# rode `aws lambda update-function-configuration` depois de obter a URL.

# 5. Function URL (auth da AWS = NONE; a autenticação real é o formulário OAuth acima).
#    Desde out/2025 a AWS exige as DUAS permissões abaixo (só a primeira dá 403 "Forbidden").
aws lambda create-function-url-config --region <region> --function-name despesas-mcp-server --auth-type NONE
aws lambda add-permission --region <region> --function-name despesas-mcp-server \
  --statement-id FunctionURLAllowPublicAccess --action lambda:InvokeFunctionUrl \
  --principal "*" --function-url-auth-type NONE
aws lambda add-permission --region <region> --function-name despesas-mcp-server \
  --statement-id FunctionURLInvokeAllowPublicAccess --action lambda:InvokeFunction \
  --principal "*" --invoked-via-function-url

# 6. Obter a URL e voltar no passo 4 para setar MCP_PUBLIC_URL
aws lambda get-function-url-config --region <region> --function-name despesas-mcp-server --query FunctionUrl --output text
```

Para atualizar o código depois de um deploy: `npm run build:lambda` de novo, e `aws lambda update-function-code --function-name despesas-mcp-server --zip-file fileb://dist/function.zip`.

**Cadastro no Claude.ai**: Configurações → Conectores → Adicionar conector personalizado, colando a URL base da Lambda (sem `/mcp`). O Claude.ai deve descobrir o servidor OAuth sozinho e abrir a tela de login (o formulário HTML acima) pedindo o `MCP_AUTH_TOKEN`.

## Deploy

```bash
sf project deploy start --target-org <alias>
sf apex run test --target-org <alias> --class-names CriarDespesasRecorrentesBatchTest --synchronous
```

## Histórico de mudanças

- **2026-08-01** — Scaffold inicial do projeto SFDX: objetos `Carteira__c`, `Recorrencia__c`, `Despesa__c`, batch `CriarDespesasRecorrentesBatch` (+ teste), abas e perfil Admin.
- **2026-08-01** — Adicionados os campos `Tipo_Pagamento__c`, `Variavel__c` e `Empresa__c` em `Recorrencia__c` e `Despesa__c`, para apoiar identificação e quitação de registros via MCP. Batch atualizado para propagar esses campos da recorrência para a despesa gerada.
- **2026-08-01** — Criado o Lightning App `Despesas` (abas Despesas, Recorrências, Carteira, nessa ordem) e o Permission Set `Despesas` com CRUD completo nos 3 objetos, FLS nos campos customizados, abas e acesso ao aplicativo.
- **2026-08-01** — Removido o perfil `Admin` do pacote: revertida a alteração de tabVisibilities feita nele (voltou ao estado anterior na org) e o arquivo `Admin.profile-meta.xml` deixou de ser versionado. Gestão de acesso passa a ser feita exclusivamente pelo Permission Set `Despesas`.
- **2026-08-01** — Criada a list view `Todos` em `Carteira__c`, `Recorrencia__c` e `Despesa__c`, mostrando todos os registros com os campos relevantes de cada objeto.
- **2026-08-01** — Avaliado replicar as colunas na list view nativa "Recent"; não é possível via Metadata API (não é retrievable/deployable). Decisão: manter `Todos` como visão principal, sem alterar a Recent.
- **2026-08-01** — Descoberto que o MCP oficial da Salesforce só tem leitura (`run_soql_query`, sem DML). Criado Connected App `Despesas MCP` (Client Credentials Flow, não versionado — só a org tem a credencial, réplica em `mcp-server/.env`) e um servidor MCP customizado em `mcp-server/` com as ferramentas `buscar_despesas_pendentes`, `identificar_despesa_por_comprovante` (heurística ponderada considerando Empresa__c, Descricao__c, Tipo_Pagamento__c, Valor__c com tolerância guiada por Variavel__c, e Data_Vencimento__c) e `quitar_despesa`. Node.js instalado no ambiente (winget) como pré-requisito. Fluxo cobre apenas pagamentos manuais (Boleto/Pix/Cartão) — Débito Automático é baixado por outro mecanismo, fora de escopo.
- **2026-08-01** — Refatorado `mcp-server` para separar as ferramentas (`src/server.js`) do transporte: `src/index.js` (stdio, uso local no Claude Code) e novo `src/http.js` (Streamable HTTP stateless, protegido por `Authorization: Bearer <MCP_AUTH_TOKEN>`), para permitir acesso remoto via Claude.ai/app mobile. Testado localmente: handshake MCP e rejeição de token ausente/incorreto (401) funcionando.
- **2026-08-01** — Deploy real do `mcp-server` como AWS Lambda (`despesas-mcp-server`, conta `637423214195`, região `sa-east-1`), sem Docker: empacotamento zip + [AWS Lambda Web Adapter](https://github.com/awslabs/aws-lambda-web-adapter) como Layer, `run.sh` como handler. AWS CLI instalado localmente (winget) e autenticado (`aws configure`). Testado ponta a ponta na Lambda real: rejeição sem token, handshake MCP com token, e chamada de `buscar_despesas_pendentes` retornando dados reais do Salesforce. Descoberto no processo: desde out/2025 a AWS exige duas permissões (`lambda:InvokeFunctionUrl` **e** `lambda:InvokeFunction`) no resource policy da Function URL — só a primeira resulta em 403 "Forbidden" silencioso vindo do próprio Lambda (não da nossa aplicação).
- **2026-08-02** — Criados os page layouts (`Carteira Layout`, `Recorrência Layout`, `Despesa Layout`), um por objeto, com todos os campos organizados em seções e related lists entre os objetos vinculados. Deploy feito na org `financeiro-dev`.
- **2026-08-02** — Criadas as Lightning Record Pages (`Carteira_Record_Page`, `Despesa_Record_Page`, `Recorrencia_Record_Page`) e atribuídas como página padrão de visualização exclusivamente no aplicativo Despesas (`actionOverrides` em `Despesas.app-meta.xml`, action `View`). Tentativa inicial de listar campos individualmente via Dynamic Forms (`fieldInstance`/`Record.<Objeto>.<Campo>`) esbarrou em erros de metadata (campos não permitidos na região `main` do template `flexipage:recordHomeTemplateDesktop`); resolvido usando `force:detailPanel`, que renderiza o Page Layout clássico completo (100% dos campos) dentro da página Lightning.
- **2026-08-02** — Criado no Setup o compact layout `RecorrenciaCompacto` (`Name`, `Empresa__c`, `Dia_Vencimento__c`, `Valor__c`) e atribuído como padrão de `Recorrencia__c`; `Recorrencia_Record_Page` editada manualmente no Lightning App Builder para usar Dynamic Forms (campos individuais) em vez de `force:detailPanel`. Ambos trazidos para o repo via `sf project retrieve start`. O retrieve completo do `CustomObject` trouxe também boilerplate padrão do Salesforce (actionOverrides `Default` para toda ação/formFactor, flags como `enableActivities`/`visibility`/`externalSharingModel`) — descartado, mantendo só `compactLayoutAssignment` no `Recorrencia__c.object-meta.xml`. Mesma limpeza nos campos/list view retrieved junto (eram só reordenação + defaults explícitos como `trackTrending: false`, sem mudança de comportamento).
- **2026-08-02** — Retrieve de `Despesa__c`: compact layout `DespesaCompacto` (`Name`, `Empresa__c`, `Data_Vencimento__c`, `Status__c`, `Valor__c`) e sua atribuição, `Despesa_Record_Page` editada no App Builder para Dynamic Forms (mesmo padrão do `Recorrencia_Record_Page`), e o Page Layout realmente em uso. Descoberto no processo: o `Despesa Layout`/`Recorrência Layout` que criamos via deploy **nunca foram, de fato, os layouts exibidos** — cada objeto customizado já vem com um layout padrão gerado pelo próprio Salesforce na criação (`Layout de Despesa`, `Layout de Recorrência`, `Layout de Carteira`), e um `Layout` novo via metadata não vira default automaticamente sem atribuição por perfil. O usuário passou a editar esses layouts de sistema diretamente no Setup; os nossos ficaram órfãos e foram apagados na org — o `sf project retrieve start` seguinte removeu sozinho os arquivos locais correspondentes (source tracking do scratch org). `Layout de Despesa` retrieved tem só 6 campos (falta `Categoria__c`, `Data_Pagamento__c`, `Empresa__c`, `Observacoes__c`, `Recorrencia__c`, `Tipo_Pagamento__c`, `Variavel__c`) — completado no changelog seguinte. Na época deste retrieve, `Carteira__c` ainda tinha os dois layouts (sistema + o nosso) coexistindo na org; o nosso foi apagado depois, mesmo padrão dos outros dois objetos.
- **2026-08-02** — Retrieved também `Layout de Recorrência` e `Layout de Carteira` (os layouts de sistema reais de cada objeto) e completados os campos faltantes nos 3 (`Layout de Despesa`, `Layout de Recorrência`, `Layout de Carteira`), adicionando-os à seção "Information" já existente junto de `OwnerId`. Deploy feito na org `financeiro-dev`.
- **2026-08-02** — Retrieve de `Carteira__c`: compact layout `CarteiraCompacto` (`Name`, `Ativa__c`, `Tipo__c`, `Instituicao__c`) e sua atribuição, e `Carteira_Record_Page` editada no App Builder (mesmo padrão de migração para Dynamic Forms que `Despesa_Record_Page`/`Recorrencia_Record_Page`). Limpeza do boilerplate do retrieve completo do `CustomObject` seguindo o mesmo padrão já estabelecido.
- **2026-08-01** — Trocado o Bearer token fixo por **OAuth 2.1 completo** (`mcp-server/src/oauth.js`) em `/mcp`: o Claude.ai recusou a conexão pedindo OAuth de verdade. Reaproveitado o `OAuthServerProvider`/`mcpAuthRouter` que o `@modelcontextprotocol/sdk` já traz (discovery RFC 8414/9728, registro dinâmico RFC 7591, PKCE) — só foi implementada a peça específica: login de usuário único, com o `MCP_AUTH_TOKEN` como senha num formulário HTML servido em `/authorize`. Sem banco de dados: clients/códigos/tokens são blobs auto-assinados por HMAC (stateless, compatível com Lambda entre invocações frias), com a troca de não dar pra revogar um token antes de expirar — aceitável para uso pessoal com TTLs curtos. Corrigido um bug encontrado no processo: token inválido em `/mcp` devolvia 500 em vez de 401 (faltava usar as classes de erro do SDK — `InvalidTokenError`/`InvalidGrantError` — em vez de `Error` genérico). Testado ponta a ponta na Lambda real simulando o `redirect_uri` do Claude.ai: registro de client, formulário de login, troca de código por token, `tools/list` autenticado. Descoberto: a Function URL da AWS renomeia o header `WWW-Authenticate` para `x-amzn-Remapped-www-authenticate` (não documentado) — pode afetar a descoberta automática do Claude.ai; se afetar, o fallback é a descoberta via `/.well-known/oauth-authorization-server` direto na URL base, que funciona. Build do zip formalizado em `mcp-server/scripts/build-lambda-zip.mjs` (`npm run build:lambda`, usa `archiver` como devDependency). Depois desse teste, um segundo bug apareceu: qualquer requisição com token inválido derrubava a Lambda com 502 (`Extension.Crash` nos logs — a Lambda Web Adapter, em Rust, quebra ao serializar um header HTTP com acento UTF-8; o `error_description` "Token **invá**lido..." ia para o header `WWW-Authenticate`). Corrigido removendo acentos de toda mensagem de erro OAuth (headers HTTP não são seguros para UTF-8 bruto). De quebra, também corrigido um warning de `express-rate-limit` sobre `X-Forwarded-For` sem `trust proxy` configurado (`app.set('trust proxy', 1)` — a Web Adapter atua como proxy reverso). Reconfirmado ponta a ponta na Lambda após as correções (login errado → 401, fluxo completo → 200, logs limpos). Passo pendente: validar visualmente o cadastro do conector na UI do Claude.ai.
