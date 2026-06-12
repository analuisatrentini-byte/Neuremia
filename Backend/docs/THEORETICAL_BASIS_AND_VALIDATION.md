# NeuroFlow: embasamento teorico e plano de validacao

Este documento descreve a base teorica do NeuroFlow e o que precisa ser validado antes de qualquer uso clinico formal. O sistema deve ser tratado como apoio ao monitoramento e a decisao clinica, nao como diagnostico automatico.

## 1. Escalas clinicas

O app separa escalas validadas do score proprietario NeuroFlow.

- PHQ-9: instrumento breve para rastreio e gravidade de sintomas depressivos, originalmente validado por Kroenke, Spitzer e Williams.
- GAD-7: instrumento breve para ansiedade, validado por Spitzer, Kroenke, Williams e Lowe.
- YMRS: escala de mania de 11 itens descrita por Young, Biggs, Ziegler e Meyer.

Regra de produto: PHQ-9, GAD-7 e YMRS devem permanecer como resultados proprios. O NeuroFlow Risk Signature pode usar esses resultados como sinais auxiliares, mas nao deve alterar a pontuacao oficial das escalas.

## 2. Fenotipagem digital

A proposta do NeuroFlow se apoia no conceito de fenotipagem digital: combinar autorrelato, sensores, padroes de interacao e dados longitudinais para acompanhar estados comportamentais e fisiologicos ao longo do tempo.

No app, isso inclui:

- diario subjetivo;
- sintomas diarios;
- adesao medicamentosa;
- gatilhos;
- escalas;
- sono, passos e frequencia cardiaca via Apple Health;
- PPG pela camera;
- metadados de voz sem armazenar conteudo;
- velocidade de digitacao e latencia dentro do app.

Limite importante: esses sinais sao correlatos indiretos. Eles nao detectam humor, diagnostico ou risco suicida de forma direta.

## 3. NeuroFlow Risk Signature

O NeuroFlow Risk Signature e um score proprietario experimental de 0 a 100.

Entradas atuais:

- humor, ansiedade, energia, irritabilidade e sono;
- adesao medicamentosa;
- gatilhos;
- tendencia longitudinal;
- desvio do basal individual;
- padroes semelhantes antes de dias ruins;
- resultados de escalas;
- texto do diario;
- PPG, voz e digitacao quando disponiveis.

O score muda conforme o foco clinico:

- Bipolaridade: maior peso para sono, virada de humor e adesao.
- Depressao: maior peso para queda de humor e seguranca.
- Ansiedade: maior peso para ansiedade, sono e gatilhos.
- Borderline: maior peso para gatilhos interpessoais e intensidade emocional.
- Burnout: maior peso para sono, energia e recuperacao.
- TDAH: maior peso para adesao, sono e funcionamento.
- Pos-parto: maior peso para sono, humor, ansiedade e rede de apoio.

O score e heuristico ate passar por validacao clinica.

## 4. PPG, voz e digitacao

PPG por camera pode estimar variacoes de fluxo sanguineo e derivar frequencia cardiaca. HRV, respiracao indireta e perfusao exigem sinal limpo, janela suficiente e comparacao com referencia externa.

Voz e digitacao devem ser usados apenas como metadados:

- intensidade media;
- pausas;
- ritmo;
- velocidade de digitacao;
- latencia de resposta.

O app nao deve gravar conteudo de voz para esse uso.

## 5. Protocolo minimo de validacao

Antes de chamar o produto de clinicamente validado:

1. Validacao tecnica dos sensores
   - Comparar PPG com Apple Watch, oximetro ou cinta cardiaca.
   - Medir erro medio de frequencia cardiaca.
   - Medir qualidade do sinal e taxa de leituras descartadas.

2. Validacao do score
   - Comparar NeuroFlow Risk Signature com PHQ-9, GAD-7, YMRS e avaliacao clinica.
   - Medir sensibilidade, especificidade, VPP e VPN.
   - Medir falsos positivos e falsos negativos.

3. Validacao longitudinal
   - Verificar se o app detecta piora antes da consulta ou crise.
   - Medir antecedencia media dos alertas.
   - Comparar periodos com e sem uso do app.

4. Validacao de seguranca
   - Revisar protocolo de risco suicida com profissionais.
   - Testar se mensagens sao claras e nao substituem atendimento.
   - Registrar auditoria de alertas e acoes.

5. Estudo de efetividade
   - Medir adesao ao diario.
   - Medir adesao medicamentosa.
   - Medir qualidade do resumo pre-consulta.
   - Avaliar se medico e paciente consideram os alertas uteis.

## 6. Fontes iniciais

- Kroenke K, Spitzer RL, Williams JBW. The PHQ-9: Validity of a Brief Depression Severity Measure. Journal of General Internal Medicine, 2001.
- Spitzer RL, Kroenke K, Williams JBW, Lowe B. A Brief Measure for Assessing Generalized Anxiety Disorder: The GAD-7. Archives of Internal Medicine, 2006.
- Young RC, Biggs JT, Ziegler VE, Meyer DA. A Rating Scale for Mania: Reliability, Validity and Sensitivity. British Journal of Psychiatry, 1978.
- Huckvale K et al. Toward clinical digital phenotyping: a timely opportunity to consider purpose, quality, and safety. npj Digital Medicine, 2019.
- Torous J et al. Digital phenotyping and mobile sensing approaches in mental health research: literature on opportunities, quality and safety.
- Literature on smartphone PPG shows feasibility for heart-rate estimation, but HRV and respiratory inference require validation against reliable reference devices.
