/**
 * Objeto de critério de busca para Despesa__c: cada instância representa um
 * conjunto de condições combinadas com AND. Usado pelo DespesaRepository para
 * montar a consulta (SOQL dinâmico) sem espalhar WHERE clauses pelo código de
 * negócio (Services/Batchables). Métodos "com*"/"sem*" retornam a própria
 * instância (fluent) para permitir encadeamento.
 *
 * Valores são interpolados diretamente no texto do SOQL (sem bind variables)
 * porque só vêm de código interno já tipado (Date/Id/String controlados pelo
 * próprio Apex, nunca input bruto de usuário) — evita a limitação de escopo de
 * bind em SOQL dinâmico; Strings ainda assim são escapadas defensivamente.
 */
public class DespesaFilter {

    private String status;
    private Date dataVencimentoIgual;
    private Date dataVencimentoDe;
    private Date dataVencimentoAte;
    private List<String> tiposPagamento;
    private Set<Id> recorrenciaIds;
    private Boolean semDataExtracao;

    public DespesaFilter comStatus(String status) {
        this.status = status;
        return this;
    }

    public DespesaFilter comDataVencimento(Date data) {
        this.dataVencimentoIgual = data;
        return this;
    }

    public DespesaFilter comDataVencimentoEntre(Date de, Date ate) {
        this.dataVencimentoDe = de;
        this.dataVencimentoAte = ate;
        return this;
    }

    public DespesaFilter comTiposPagamento(List<String> tipos) {
        this.tiposPagamento = tipos;
        return this;
    }

    public DespesaFilter comRecorrenciaIds(Set<Id> ids) {
        this.recorrenciaIds = ids;
        return this;
    }

    public DespesaFilter semDataExtracao() {
        this.semDataExtracao = true;
        return this;
    }

    public String toSoqlWhere() {
        List<String> condicoes = new List<String>();

        if (status != null) {
            condicoes.add('Status__c = ' + quote(status));
        }
        if (dataVencimentoIgual != null) {
            condicoes.add('Data_Vencimento__c = ' + String.valueOf(dataVencimentoIgual));
        }
        if (dataVencimentoDe != null) {
            condicoes.add('Data_Vencimento__c >= ' + String.valueOf(dataVencimentoDe));
        }
        if (dataVencimentoAte != null) {
            condicoes.add('Data_Vencimento__c <= ' + String.valueOf(dataVencimentoAte));
        }
        if (tiposPagamento != null && !tiposPagamento.isEmpty()) {
            List<String> tiposEntreAspas = new List<String>();
            for (String tipo : tiposPagamento) {
                tiposEntreAspas.add(quote(tipo));
            }
            condicoes.add('Tipo_Pagamento__c IN (' + String.join(tiposEntreAspas, ', ') + ')');
        }
        if (recorrenciaIds != null && !recorrenciaIds.isEmpty()) {
            List<String> idsEntreAspas = new List<String>();
            for (Id recId : recorrenciaIds) {
                idsEntreAspas.add(quote(String.valueOf(recId)));
            }
            condicoes.add('Recorrencia__c IN (' + String.join(idsEntreAspas, ', ') + ')');
        }
        if (semDataExtracao == true) {
            condicoes.add('Data_Extracao__c = null');
        }

        return condicoes.isEmpty() ? '' : String.join(condicoes, ' AND ');
    }

    private String quote(String valor) {
        return '\'' + String.escapeSingleQuotes(valor) + '\'';
    }
}
