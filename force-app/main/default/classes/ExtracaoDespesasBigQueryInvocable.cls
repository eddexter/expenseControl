/**
 * Entrada do Flow de Admin (Extracao_Despesas_Mensal): o admin escolhe o
 * mês/ano e essa classe traduz Input/Output do Flow para o
 * ExtracaoDespesasBigQueryService — nenhuma regra de negócio aqui.
 */
public without sharing class ExtracaoDespesasBigQueryInvocable {

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

    @InvocableMethod(label='Extrair Despesas para BigQuery' description='Extrai despesas pendentes de extração do mês/ano escolhido e envia para o BigQuery.')
    public static List<ExtracaoResultado> extrair(List<ExtracaoInput> inputs) {
        List<ExtracaoResultado> resultados = new List<ExtracaoResultado>();
        for (ExtracaoInput input : inputs) {
            ExtracaoDespesasBigQueryService.Resultado origem = new ExtracaoDespesasBigQueryService().extrairMes(input.mesVencimento);
            resultados.add(paraResultadoDoFlow(origem));
        }
        return resultados;
    }

    private static ExtracaoResultado paraResultadoDoFlow(ExtracaoDespesasBigQueryService.Resultado origem) {
        ExtracaoResultado resultado = new ExtracaoResultado();
        resultado.mensagem = origem.mensagem;
        resultado.quantidadeExtraida = origem.quantidadeExtraida;
        return resultado;
    }
}
