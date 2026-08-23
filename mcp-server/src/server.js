import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { querySOQL, updateRecord, createRecord } from './salesforce.js';
import { scoreCandidate } from './matching.js';
import { logEvent } from './observability.js';

const DESPESA_FIELDS = [
  'Id',
  'Name',
  'Descricao__c',
  'Valor__c',
  'Status__c',
  'Data_Vencimento__c',
  'Data_Pagamento__c',
  'Carteira__c',
  'Tipo_Pagamento__c',
  'Empresa__c',
  'Variavel__c',
  'Recorrencia__c'
].join(', ');

const TIPOS_PAGAMENTO_QUITACAO_CONFIRMACAO = ['Débito Automático', 'Cartão de Crédito'];

function soqlEscape(value) {
  return String(value).replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function textResult(payload) {
  return { content: [{ type: 'text', text: JSON.stringify(payload, null, 2) }] };
}

function errorResult(message) {
  return { content: [{ type: 'text', text: `Erro: ${message}` }], isError: true };
}

export function createServer() {
  const server = new McpServer({ name: 'despesas-mcp-server', version: '1.0.0' });

  server.registerTool(
    'buscar_despesas_pendentes',
    {
      title: 'Buscar despesas pendentes',
      description:
        'Lista despesas (Despesa__c) com Status__c = Pendente no Salesforce, opcionalmente filtradas por mês de vencimento, empresa ou carteira. Use para navegação manual ou para reduzir o conjunto antes de identificar um comprovante.',
      inputSchema: {
        mes: z.string().regex(/^\d{4}-\d{2}$/).optional().describe('Filtro de mês de vencimento no formato YYYY-MM'),
        empresa: z.string().optional().describe('Filtro parcial (LIKE) pelo campo Empresa__c'),
        carteiraId: z.string().optional().describe('Id da Carteira__c para filtrar')
      }
    },
    async ({ mes, empresa, carteiraId }) => {
      try {
        const condicoes = ["Status__c = 'Pendente'"];
        if (mes) {
          const [ano, mesNum] = mes.split('-');
          condicoes.push(`CALENDAR_YEAR(Data_Vencimento__c) = ${Number(ano)}`);
          condicoes.push(`CALENDAR_MONTH(Data_Vencimento__c) = ${Number(mesNum)}`);
        }
        if (empresa) {
          condicoes.push(`Empresa__c LIKE '%${soqlEscape(empresa)}%'`);
        }
        if (carteiraId) {
          condicoes.push(`Carteira__c = '${soqlEscape(carteiraId)}'`);
        }

        const soql = `SELECT ${DESPESA_FIELDS} FROM Despesa__c WHERE ${condicoes.join(' AND ')} ORDER BY Data_Vencimento__c ASC LIMIT 200`;
        const records = await querySOQL(soql);
        return textResult({ total: records.length, despesas: records });
      } catch (err) {
        return errorResult(err.message);
      }
    }
  );

  server.registerTool(
    'identificar_despesa_por_comprovante',
    {
      title: 'Identificar despesa a partir de um comprovante',
      description:
        'Compara os dados extraídos de um comprovante de pagamento (empresa, descrição, valor, data, tipo de pagamento) contra as despesas pendentes no Salesforce e retorna os candidatos mais prováveis, ordenados por pontuação de confiança. ' +
        'Empresa__c tem o maior peso; Descricao__c reforça o match quando o nome da empresa está vago ou incompleto. ' +
        'O peso e a tolerância de Valor__c dependem de Variavel__c: quando a despesa é variável (ex: cartão de crédito, conta de luz), o valor pode não bater exatamente, então recebe peso menor e tolerância maior; quando não é variável, um valor divergente é um sinal negativo forte. ' +
        'Sempre confirme com o usuário antes de chamar quitar_despesa, a menos que a confiança seja alta e o valor bata.',
      inputSchema: {
        empresa: z.string().optional().describe('Nome da empresa/beneficiário como aparece no comprovante'),
        descricao: z.string().optional().describe('Descrição, histórico ou observação do comprovante'),
        valor: z.number().optional().describe('Valor pago, conforme o comprovante'),
        data: z.string().optional().describe('Data do pagamento no formato YYYY-MM-DD'),
        tipoPagamento: z.string().optional().describe('Boleto, Débito Automático, Pix ou Cartão de Crédito'),
        limite: z.number().int().min(1).max(20).optional().describe('Quantidade máxima de candidatos a retornar (padrão 5)')
      }
    },
    async ({ empresa, descricao, valor, data, tipoPagamento, limite }) => {
      try {
        const soql = `SELECT ${DESPESA_FIELDS} FROM Despesa__c WHERE Status__c = 'Pendente' ORDER BY Data_Vencimento__c DESC LIMIT 200`;
        const pendentes = await querySOQL(soql);

        const comprovante = { empresa, descricao, valor, data, tipoPagamento };
        const candidatos = pendentes
          .map((despesa) => ({ despesa, ...scoreCandidate(despesa, comprovante) }))
          .filter((c) => c.score > 0)
          .sort((a, b) => b.score - a.score)
          .slice(0, limite || 5);

        return textResult({
          comprovante,
          totalDespesasPendentesAnalisadas: pendentes.length,
          candidatos: candidatos.map((c) => ({
            despesaId: c.despesa.Id,
            nome: c.despesa.Name,
            descricao: c.despesa.Descricao__c,
            empresa: c.despesa.Empresa__c,
            valor: c.despesa.Valor__c,
            variavel: c.despesa.Variavel__c,
            tipoPagamento: c.despesa.Tipo_Pagamento__c,
            dataVencimento: c.despesa.Data_Vencimento__c,
            pontuacao: c.score,
            confianca: c.confianca,
            motivos: c.motivos
          }))
        });
      } catch (err) {
        return errorResult(err.message);
      }
    }
  );

  server.registerTool(
    'quitar_despesa',
    {
      title: 'Quitar despesa',
      description:
        'Marca uma Despesa__c como Paga (Status__c = Pago) e registra Data_Pagamento__c. ' +
        'Se valorPago for informado e a despesa NÃO for variável, o valor deve bater com Valor__c (pequenas diferenças de arredondamento são toleradas); divergências maiores exigem forcar = true. ' +
        'Se a despesa já não estiver Pendente, também exige forcar = true. ' +
        'Se Tipo_Pagamento__c for Débito Automático ou Cartão de Crédito, a baixa é tipicamente automática por outro mecanismo — confirme com o usuário antes de quitar manualmente; passe forcar = true só após essa confirmação.',
      inputSchema: {
        despesaId: z.string().describe('Id do registro Despesa__c a ser quitado'),
        dataPagamento: z.string().describe('Data em que o pagamento foi efetuado, no formato YYYY-MM-DD'),
        valorPago: z.number().optional().describe('Valor efetivamente pago, se diferente do valor cadastrado'),
        forcar: z.boolean().optional().describe('Ignora as validações de segurança (status atual, divergência de valor e tipo de pagamento Débito Automático/Cartão de Crédito)')
      }
    },
    async ({ despesaId, dataPagamento, valorPago, forcar }) => {
      try {
        const [despesa] = await querySOQL(
          `SELECT Id, Status__c, Variavel__c, Valor__c, Empresa__c, Descricao__c, Tipo_Pagamento__c FROM Despesa__c WHERE Id = '${soqlEscape(despesaId)}' LIMIT 1`
        );

        if (!despesa) {
          return errorResult(`Nenhuma Despesa__c encontrada com Id ${despesaId}.`);
        }

        if (despesa.Status__c !== 'Pendente' && !forcar) {
          await logEvent({ tipoEvento: 'quitar_despesa', status: 'bloqueado', idRastreio: despesa.Id, detalhes: { motivo: 'status_nao_pendente', statusAtual: despesa.Status__c } });
          return errorResult(
            `Despesa ${despesa.Id} (${despesa.Descricao__c}) está com Status__c = '${despesa.Status__c}', não 'Pendente'. Passe forcar = true para quitar mesmo assim.`
          );
        }

        if (TIPOS_PAGAMENTO_QUITACAO_CONFIRMACAO.includes(despesa.Tipo_Pagamento__c) && !forcar) {
          await logEvent({ tipoEvento: 'quitar_despesa', status: 'bloqueado', idRastreio: despesa.Id, detalhes: { motivo: 'confirmacao_tipo_pagamento', tipoPagamento: despesa.Tipo_Pagamento__c } });
          return errorResult(
            `Despesa ${despesa.Id} (${despesa.Descricao__c}) tem Tipo_Pagamento__c = '${despesa.Tipo_Pagamento__c}'. Confirme com o usuário se essa despesa deve mesmo ser quitada manualmente antes de prosseguir, e passe forcar = true para efetivar.`
          );
        }

        const fields = { Status__c: 'Pago', Data_Pagamento__c: dataPagamento };

        if (valorPago != null) {
          const diff = Math.abs(valorPago - despesa.Valor__c);
          if (!despesa.Variavel__c && diff > 0.02 && !forcar) {
            await logEvent({ tipoEvento: 'quitar_despesa', status: 'bloqueado', idRastreio: despesa.Id, detalhes: { motivo: 'divergencia_valor', valorPago, valorCadastrado: despesa.Valor__c } });
            return errorResult(
              `Valor pago (${valorPago}) diverge do valor cadastrado (${despesa.Valor__c}) e a despesa NÃO é variável. Passe forcar = true se o valor pago estiver correto mesmo assim.`
            );
          }
          if (diff > 0.01) {
            fields.Valor__c = valorPago;
          }
        }

        await updateRecord('Despesa__c', despesa.Id, fields);

        await logEvent({ tipoEvento: 'quitar_despesa', status: 'sucesso', idRastreio: despesa.Id, detalhes: { empresa: despesa.Empresa__c, descricao: despesa.Descricao__c, ...fields } });

        return textResult({
          sucesso: true,
          despesaId: despesa.Id,
          empresa: despesa.Empresa__c,
          descricao: despesa.Descricao__c,
          camposAtualizados: fields
        });
      } catch (err) {
        await logEvent({ tipoEvento: 'quitar_despesa', status: 'falha', idRastreio: despesaId, detalhes: { erro: err.message } });
        return errorResult(err.message);
      }
    }
  );

  server.registerTool(
    'buscar_carteiras',
    {
      title: 'Buscar carteiras',
      description:
        'Lista as Carteira__c cadastradas (Id, Name, Tipo__c, Instituicao__c, Ativa__c). Use para resolver o carteiraId a partir do nome do cartão/conta mencionado no comprovante ou pelo usuário, antes de chamar criar_despesa. ' +
        "Ao montar uma Despesa__c a partir de um comprovante de Débito ou Pix, filtre tipo = 'Conta Corrente' e pergunte ao usuário qual conta corrente cadastrada corresponde. Para um comprovante de Cartão de Crédito, filtre tipo = 'Cartão de Crédito' e pergunte qual cartão cadastrado corresponde.",
      inputSchema: {
        nome: z.string().optional().describe('Filtro parcial (LIKE) pelo Name da carteira'),
        tipo: z
          .string()
          .optional()
          .describe(
            "Filtro exato pelo Tipo__c da carteira (Conta Corrente, Poupança, Cartão de Crédito, Dinheiro em Espécie, Investimento, Outro). Use 'Conta Corrente' para comprovantes de Débito/Pix e 'Cartão de Crédito' para comprovantes de Cartão de Crédito."
          ),
        apenasAtivas: z.boolean().optional().describe('Se true (padrão), traz só carteiras com Ativa__c = true')
      }
    },
    async ({ nome, tipo, apenasAtivas }) => {
      try {
        const condicoes = [];
        if (apenasAtivas !== false) {
          condicoes.push('Ativa__c = true');
        }
        if (nome) {
          condicoes.push(`Name LIKE '%${soqlEscape(nome)}%'`);
        }
        if (tipo) {
          condicoes.push(`Tipo__c = '${soqlEscape(tipo)}'`);
        }
        const where = condicoes.length ? ` WHERE ${condicoes.join(' AND ')}` : '';
        const soql = `SELECT Id, Name, Tipo__c, Instituicao__c, Ativa__c FROM Carteira__c${where} ORDER BY Name ASC LIMIT 200`;
        const carteiras = await querySOQL(soql);
        return textResult({ total: carteiras.length, carteiras });
      } catch (err) {
        return errorResult(err.message);
      }
    }
  );

  server.registerTool(
    'criar_despesa',
    {
      title: 'Criar despesa avulsa a partir de um comprovante',
      description:
        'Cria uma Despesa__c avulsa (não vinculada a nenhuma Recorrencia__c) a partir de um comprovante de pagamento já efetuado — foto de nota/recibo, ou comprovante de transação por aproximação/NFC no celular. ' +
        'A despesa é criada diretamente com Status__c = Pago e Data_Pagamento__c = dataPagamento, já que o comprovante prova que o pagamento já ocorreu. ' +
        'Antes de usar esta ferramenta, chame identificar_despesa_por_comprovante para conferir se o comprovante não corresponde a uma despesa pendente já existente (ex: gerada por uma recorrência) — só crie uma despesa nova quando não houver correspondência razoável. ' +
        'carteiraId NUNCA deve ser adivinhado: se o comprovante for de Débito ou Pix, chame buscar_carteiras com tipo = "Conta Corrente" e pergunte ao usuário qual conta corrente cadastrada usar; se for de Cartão de Crédito, chame buscar_carteiras com tipo = "Cartão de Crédito" e pergunte qual cartão cadastrado usar — mesmo havendo só uma opção, confirme com o usuário antes de criar a despesa.',
      inputSchema: {
        descricao: z.string().describe('Descrição da despesa'),
        valor: z.number().describe('Valor pago, conforme o comprovante'),
        carteiraId: z.string().describe('Id da Carteira__c usada no pagamento (veja buscar_carteiras)'),
        dataPagamento: z.string().describe('Data em que o pagamento foi efetuado, no formato YYYY-MM-DD'),
        dataVencimento: z
          .string()
          .optional()
          .describe('Data de vencimento no formato YYYY-MM-DD; se omitida, usa a própria dataPagamento'),
        tipo: z.string().optional().describe('Tipo__c (Global Value Set Tipo_Despesa), ex: Alimentação, Combustível, Compras'),
        tipoPagamento: z.string().optional().describe('Tipo_Pagamento__c: Boleto, Débito Automático, Pix ou Cartão de Crédito'),
        empresa: z.string().optional().describe('Nome da empresa/beneficiário como aparece no comprovante'),
        observacoes: z.string().optional().describe('Observações livres sobre a despesa'),
        variavel: z.boolean().optional().describe('Variavel__c — se o valor costuma variar (padrão false)')
      }
    },
    async ({ descricao, valor, carteiraId, dataPagamento, dataVencimento, tipo, tipoPagamento, empresa, observacoes, variavel }) => {
      try {
        const fields = {
          Descricao__c: descricao,
          Valor__c: valor,
          Carteira__c: carteiraId,
          Status__c: 'Pago',
          Data_Pagamento__c: dataPagamento,
          Data_Vencimento__c: dataVencimento || dataPagamento
        };
        if (tipo) fields.Tipo__c = tipo;
        if (tipoPagamento) fields.Tipo_Pagamento__c = tipoPagamento;
        if (empresa) fields.Empresa__c = empresa;
        if (observacoes) fields.Observacoes__c = observacoes;
        if (variavel != null) fields.Variavel__c = variavel;

        const despesaId = await createRecord('Despesa__c', fields);

        await logEvent({ tipoEvento: 'criar_despesa', status: 'sucesso', idRastreio: despesaId, detalhes: { ...fields } });

        return textResult({
          sucesso: true,
          despesaId,
          camposCriados: fields
        });
      } catch (err) {
        await logEvent({ tipoEvento: 'criar_despesa', status: 'falha', detalhes: { erro: err.message } });
        return errorResult(err.message);
      }
    }
  );

  return server;
}
