const STOPWORDS_EMPRESA = new Set(['ltda', 'sa', 's a', 'me', 'eireli', 'epp', 'cia', 'comercio', 'com']);

function normalize(text) {
  if (!text) return '';
  return text
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9 ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizeEmpresa(text) {
  const norm = normalize(text);
  return norm
    .split(' ')
    .filter((t) => t && !STOPWORDS_EMPRESA.has(t))
    .join(' ');
}

function tokenOverlap(a, b, minLen = 3) {
  const tokensA = new Set(a.split(' ').filter((t) => t.length >= minLen));
  const tokensB = new Set(b.split(' ').filter((t) => t.length >= minLen));
  return [...tokensA].filter((t) => tokensB.has(t));
}

/**
 * Compara um comprovante extraído (empresa, descrição, valor, data, tipo de pagamento)
 * contra um registro Despesa__c pendente e retorna uma pontuação 0-100 com a justificativa.
 *
 * Peso maior em Empresa__c; Descricao__c reforça quando Empresa__c é vaga/ausente.
 * Valor__c só exige exatidão quando Variavel__c = false — quando a despesa é variável
 * (ex: cartão de crédito, conta de luz), o valor tem peso menor e tolerância maior.
 */
export function scoreCandidate(despesa, comprovante) {
  let score = 0;
  const motivos = [];

  if (comprovante.empresa && despesa.Empresa__c) {
    const a = normalizeEmpresa(comprovante.empresa);
    const b = normalizeEmpresa(despesa.Empresa__c);
    if (a && b) {
      if (a === b) {
        score += 50;
        motivos.push('empresa: correspondência exata (+50)');
      } else if (a.includes(b) || b.includes(a)) {
        score += 35;
        motivos.push('empresa: correspondência parcial (+35)');
      } else {
        const comuns = tokenOverlap(a, b);
        if (comuns.length > 0) {
          score += 20;
          motivos.push(`empresa: termos em comum [${comuns.join(', ')}] (+20)`);
        }
      }
    }
  }

  if (comprovante.descricao && despesa.Descricao__c) {
    const a = normalize(comprovante.descricao);
    const b = normalize(despesa.Descricao__c);
    if (a && b) {
      if (a === b) {
        score += 20;
        motivos.push('descrição: correspondência exata (+20)');
      } else {
        const comuns = tokenOverlap(a, b);
        if (comuns.length > 0) {
          const pontos = Math.min(15, comuns.length * 5);
          score += pontos;
          motivos.push(`descrição: termos em comum [${comuns.join(', ')}] (+${pontos})`);
        }
      }
    }
  }

  if (comprovante.tipoPagamento && despesa.Tipo_Pagamento__c) {
    if (normalize(comprovante.tipoPagamento) === normalize(despesa.Tipo_Pagamento__c)) {
      score += 10;
      motivos.push('tipo de pagamento: correspondência (+10)');
    }
  }

  if (comprovante.valor != null && despesa.Valor__c != null) {
    const diff = Math.abs(comprovante.valor - despesa.Valor__c);
    const pct = despesa.Valor__c > 0 ? diff / despesa.Valor__c : 1;

    if (despesa.Variavel__c) {
      if (diff <= 0.01) {
        score += 15;
        motivos.push('valor: exato (mesmo sendo despesa variável) (+15)');
      } else if (pct <= 0.3) {
        score += 10;
        motivos.push(`valor: dentro da tolerância de despesa variável, diferença de ${(pct * 100).toFixed(0)}% (+10)`);
      } else {
        motivos.push(`valor: fora da tolerância mesmo sendo variável, diferença de ${(pct * 100).toFixed(0)}% (+0)`);
      }
    } else if (diff <= 0.01) {
      score += 25;
      motivos.push('valor: exato (+25)');
    } else if (pct <= 0.02) {
      score += 15;
      motivos.push('valor: praticamente exato, pequena diferença de arredondamento (+15)');
    } else {
      score -= 15;
      motivos.push(`valor: divergente e despesa NÃO é variável — sinal negativo, diferença de ${(pct * 100).toFixed(0)}% (-15)`);
    }
  }

  if (comprovante.data && despesa.Data_Vencimento__c) {
    const diffDias = Math.abs((new Date(comprovante.data) - new Date(despesa.Data_Vencimento__c)) / 86400000);
    if (diffDias <= 3) {
      score += 10;
      motivos.push('data: pagamento próximo ao vencimento (+10)');
    } else if (diffDias <= 10) {
      score += 5;
      motivos.push('data: pagamento no mesmo período do vencimento (+5)');
    }
  }

  const finalScore = Math.max(0, Math.min(100, score));
  let confianca = 'baixa';
  if (finalScore >= 70) confianca = 'alta';
  else if (finalScore >= 40) confianca = 'média';

  return { score: finalScore, confianca, motivos };
}
