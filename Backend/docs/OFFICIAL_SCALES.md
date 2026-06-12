# NeuroFlow - Escalas Oficiais e Licencas

O app implementa pontuacao e faixas operacionais para PHQ-9, GAD-7 e YMRS, mas os textos em portugues no codigo devem ser tratados como adaptacoes ate a revisao/licenca formal.

## Antes de uso real

- Confirmar permissao de uso de cada instrumento.
- Substituir textos adaptados por versoes oficiais/validadas quando aplicavel.
- Registrar fonte, idioma, versao e data de revisao.
- Manter equivalencia exata entre itens, opcoes de resposta e pontuacao.
- Validar interpretacao com profissional habilitado.

## Status no projeto

- PHQ-9: 9 itens, soma 0-27, faixas usuais implementadas.
- GAD-7: 7 itens, soma 0-21, faixas usuais implementadas.
- YMRS: 11 itens, itens com faixas 0-4 e 0-8, total 0-60, faixas operacionais implementadas.

## Pendencia critica

Nao publicar como escala oficial em portugues sem autorizacao/licenca/fonte validada. Quando a versao oficial for obtida, substituir os textos em `ClinicalModels.swift` preservando os testes de contagem e pontuacao.
