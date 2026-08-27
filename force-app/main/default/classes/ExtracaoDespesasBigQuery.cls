/**
 * Extração sob demanda de Despesa__c para o BigQuery (MVP4). Ver
 * claudeplanning/plano-extracao-mvp4.md.
 *
 * Chamado pelo Flow de Admin (mês/ano escolhido pelo usuário) via @InvocableMethod.
 * Busca despesas ainda não extraídas (Data_Extracao__c = null) com Data_Vencimento__c
 * dentro do mês escolhido, envia o payload achatado (com os campos de Carteira__c via
 * relacionamento) para a Cloud Function via callout, e só marca Data_Extracao__c depois
 * de confirmar sucesso (HTTP 2xx) — se o callout falhar, nada é atualizado e a próxima
 * tentativa (mesmo mês) reprocessa os mesmos registros, sem duplicar e sem perder.
 *
 * Depende do Named Credential "GCP_Extracao_Despesas" (protocolo Password, gera o header
 * Authorization: Basic automaticamente a partir do segredo compartilhado configurado em
 * Setup > Named Credentials — a Cloud Function valida esse header do lado dela).
 */
public without sharing class ExtracaoDespesasBigQuery {

    public class ExtracaoInput {
        @InvocableVariable(label='Mês de vencimento' required=true description='Qualquer data dentro do mês/ano a extrair — só o mês e o ano são usados.')
        public Date mesVencimento;
    }

    public class ExtracaoResultado {
        @InvocableVariable(label='Mensagem')
        public String mensagem;

        @InvocableVariable(label='Quantidade extraída')
        public Integer quantidadeExtraida;
    }

    private static final String NAMED_CREDENTIAL_PATH = 'callout:GCP_Extracao_Despesas';

    @InvocableMethod(label='Extrair Despesas para BigQuery' description='Extrai despesas pendentes de extração do mês/ano escolhido e envia para o BigQuery.')
    public static List<ExtracaoResultado> extrair(List<ExtracaoInput> inputs) {
        List<ExtracaoResultado> resultados = new List<ExtracaoResultado>();
        for (ExtracaoInput input : inputs) {
            resultados.add(extrairMes(input.mesVencimento));
        }
        return resultados;
    }

    public static ExtracaoResultado extrairMes(Date mesVencimento) {
        ExtracaoResultado resultado = new ExtracaoResultado();

        Date primeiroDiaDoMes = Date.newInstance(mesVencimento.year(), mesVencimento.month(), 1);
        Date ultimoDiaDoMes = primeiroDiaDoMes.addMonths(1).addDays(-1);

        List<Despesa__c> despesas = [
            SELECT Id, Descricao__c, Valor__c, Status__c, Data_Vencimento__c, Data_Pagamento__c,
                Tipo__c, Tipo_Pagamento__c, Variavel__c, Empresa__c,
                Carteira__r.Name, Carteira__r.Tipo__c, Carteira__r.Instituicao__c
            FROM Despesa__c
            WHERE Data_Extracao__c = null
            AND Data_Vencimento__c >= :primeiroDiaDoMes
            AND Data_Vencimento__c <= :ultimoDiaDoMes
        ];

        if (despesas.isEmpty()) {
            resultado.mensagem = 'Nenhuma despesa pendente de extração em ' + primeiroDiaDoMes.format() + '.';
            resultado.quantidadeExtraida = 0;
            return resultado;
        }

        List<Object> linhas = new List<Object>();
        for (Despesa__c d : despesas) {
            linhas.add(new Map<String, Object>{
                'despesa_id' => d.Id,
                'descricao' => d.Descricao__c,
                'valor' => d.Valor__c,
                'status' => d.Status__c,
                'data_vencimento' => toIsoDate(d.Data_Vencimento__c),
                'data_pagamento' => toIsoDate(d.Data_Pagamento__c),
                'tipo' => d.Tipo__c,
                'tipo_pagamento' => d.Tipo_Pagamento__c,
                'variavel' => d.Variavel__c,
                'empresa' => d.Empresa__c,
                'carteira_nome' => d.Carteira__r != null ? d.Carteira__r.Name : null,
                'carteira_tipo' => d.Carteira__r != null ? d.Carteira__r.Tipo__c : null,
                'carteira_instituicao' => d.Carteira__r != null ? d.Carteira__r.Instituicao__c : null
            });
        }

        Map<String, Object> payload = new Map<String, Object>{ 'despesas' => linhas };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL_PATH);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(30000);

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            List<Despesa__c> paraAtualizar = new List<Despesa__c>();
            for (Despesa__c d : despesas) {
                paraAtualizar.add(new Despesa__c(Id = d.Id, Data_Extracao__c = Date.today()));
            }
            update paraAtualizar;

            resultado.mensagem = paraAtualizar.size() + ' despesa(s) extraída(s) com sucesso para ' + primeiroDiaDoMes.format() + '.';
            resultado.quantidadeExtraida = paraAtualizar.size();
        } else {
            resultado.mensagem = 'Falha ao extrair despesas: HTTP ' + res.getStatusCode() + ' — ' + res.getBody() +
                '. Nenhum registro foi marcado como extraído; a próxima tentativa reprocessa o mesmo mês.';
            resultado.quantidadeExtraida = 0;
        }

        return resultado;
    }

    /**
     * Date.format() é sensível ao locale da org (ex.: "02/08/2026" numa org pt-BR) — o
     * BigQuery exige DATE em ISO 8601 (yyyy-MM-dd). String.valueOf(Date) sempre produz
     * esse formato fixo, independente do locale, então é o certo aqui (não .format()).
     */
    private static String toIsoDate(Date d) {
        return d == null ? null : String.valueOf(d);
    }
}
