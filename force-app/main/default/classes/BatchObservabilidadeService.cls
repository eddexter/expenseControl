/**
 * Traduz o resultado de um batch finalizado (AsyncApexJob) em um evento de
 * observabilidade enviado ao Grafana Loki via LokiLoggerService. Usado no
 * finish() dos Batchables deste projeto, para não duplicar em cada um a mesma
 * consulta a AsyncApexJob + montagem dos detalhes do log.
 */
public without sharing class BatchObservabilidadeService {

    private final AsyncApexJobRepository asyncApexJobRepository;

    public BatchObservabilidadeService() {
        this(new AsyncApexJobRepository());
    }

    public BatchObservabilidadeService(AsyncApexJobRepository asyncApexJobRepository) {
        this.asyncApexJobRepository = asyncApexJobRepository;
    }

    public void logResultado(String origem, Id jobId) {
        AsyncApexJob job = asyncApexJobRepository.buscarResumo(jobId);
        String status = (job.NumberOfErrors == 0) ? 'sucesso' : 'falha';
        LokiLoggerService.log(origem, 'batch_finish', status, jobId, new Map<String, Object>{
            'itensProcessados' => job.JobItemsProcessed,
            'totalItens' => job.TotalJobItems,
            'erros' => job.NumberOfErrors
        });
    }
}
