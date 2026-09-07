/**
 * Acesso a dados de AsyncApexJob (job de batch já finalizado). Usado pelo
 * BatchObservabilidadeService para saber se um batch terminou com erro antes
 * de logar o evento de observabilidade.
 */
public without sharing class AsyncApexJobRepository {

    public AsyncApexJob buscarResumo(Id jobId) {
        return [
            SELECT Status, NumberOfErrors, JobItemsProcessed, TotalJobItems
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];
    }
}
