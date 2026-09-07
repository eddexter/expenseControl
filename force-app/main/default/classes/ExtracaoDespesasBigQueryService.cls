/**
 * Orquestra a extração sob demanda de Despesa__c para o BigQuery (MVP4). Ver
 * claudeplanning/plano-extracao-mvp4.md.
 *
 * Busca despesas ainda não extraídas (Data_Extracao__c = null) com
 * Data_Vencimento__c dentro do mês escolhido (DespesaRepository +
 * DespesaFilter), monta o payload (DespesaExtracaoPayloadBuilder), envia via
 * BigQueryExtracaoClient e só marca Data_Extracao__c depois de confirmar
 * sucesso (HTTP 2xx) — se o callout falhar, nada é atualizado e a próxima
 * chamada (mesmo mês) reprocessa os mesmos registros, sem duplicar e sem perder.
 */
public without sharing class ExtracaoDespesasBigQueryService {

    public class Resultado {
        public String mensagem;
        public Integer quantidadeExtraida;
    }

    private final DespesaRepository despesaRepository;
    private final DespesaExtracaoPayloadBuilder payloadBuilder;
    private final BigQueryExtracaoClient client;

    public ExtracaoDespesasBigQueryService() {
        this(new DespesaRepository(), new DespesaExtracaoPayloadBuilder(), new BigQueryExtracaoClient());
    }

    public ExtracaoDespesasBigQueryService(
        DespesaRepository despesaRepository,
        DespesaExtracaoPayloadBuilder payloadBuilder,
        BigQueryExtracaoClient client
    ) {
        this.despesaRepository = despesaRepository;
        this.payloadBuilder = payloadBuilder;
        this.client = client;
    }

    public Resultado extrairMes(Date mesVencimento) {
        Resultado resultado = new Resultado();

        Date primeiroDiaDoMes = Date.newInstance(mesVencimento.year(), mesVencimento.month(), 1);
        Date ultimoDiaDoMes = primeiroDiaDoMes.addMonths(1).addDays(-1);

        DespesaFilter filtro = new DespesaFilter()
            .semDataExtracao()
            .comDataVencimentoEntre(primeiroDiaDoMes, ultimoDiaDoMes);

        List<Despesa__c> despesas = despesaRepository.buscarParaExtracao(filtro);

        if (despesas.isEmpty()) {
            resultado.mensagem = 'Nenhuma despesa pendente de extração em ' + primeiroDiaDoMes.format() + '.';
            resultado.quantidadeExtraida = 0;
            return resultado;
        }

        Map<String, Object> payload = payloadBuilder.montar(despesas);
        HttpResponse res = client.enviar(payload);

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            List<Despesa__c> paraAtualizar = new List<Despesa__c>();
            for (Despesa__c d : despesas) {
                paraAtualizar.add(new Despesa__c(Id = d.Id, Data_Extracao__c = Date.today()));
            }
            despesaRepository.atualizar(paraAtualizar);

            resultado.mensagem = paraAtualizar.size() + ' despesa(s) extraída(s) com sucesso para ' + primeiroDiaDoMes.format() + '.';
            resultado.quantidadeExtraida = paraAtualizar.size();
        } else {
            resultado.mensagem = 'Falha ao extrair despesas: HTTP ' + res.getStatusCode() + ' — ' + res.getBody() +
                '. Nenhum registro foi marcado como extraído; a próxima tentativa reprocessa o mesmo mês.';
            resultado.quantidadeExtraida = 0;
        }

        return resultado;
    }
}
