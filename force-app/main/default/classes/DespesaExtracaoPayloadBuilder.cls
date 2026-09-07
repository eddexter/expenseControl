/**
 * Monta o payload (linhas achatadas) enviado à Cloud Function de extração, a
 * partir de Despesa__c já carregadas com os campos de Carteira__c via
 * relacionamento (DespesaRepository.buscarParaExtracao). Responsabilidade
 * única: mapear Despesa__c -> Map de saída — sem SOQL nem callout.
 */
public without sharing class DespesaExtracaoPayloadBuilder {

    public Map<String, Object> montar(List<Despesa__c> despesas) {
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
        return new Map<String, Object>{ 'despesas' => linhas };
    }

    /**
     * Date.format() é sensível ao locale da org (ex.: "02/08/2026" numa org
     * pt-BR) — o BigQuery exige DATE em ISO 8601 (yyyy-MM-dd). String.valueOf(Date)
     * sempre produz esse formato fixo, independente do locale, então é o
     * certo aqui (não .format()).
     */
    private String toIsoDate(Date d) {
        return d == null ? null : String.valueOf(d);
    }
}
