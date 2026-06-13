//
//  LegalDocuments.swift
//  NeuroFlow
//
//  Termos de Uso e Política de Privacidade (versão 1.0 — 2026-06-13).
//  Conformidade: LGPD (Lei nº 13.709/2018), CFM Resolução 2.314/2022,
//  CRP Resolução 11/2018.
//

import Foundation

// MARK: - Policy version

enum LegalVersion {
    /// Increment whenever ToS or Privacy Policy content changes.
    /// This value is compared against the persisted user acceptance version
    /// to detect when re-acceptance is required after a policy update.
    static let current = "1.0"
    static let effectiveDate = "13 de junho de 2026"
}

// MARK: - Terms of Use

let neuroFlowTermsOfUse = """
TERMOS DE USO — NEUROFLOW
Versão \(LegalVersion.current) | Em vigor a partir de \(LegalVersion.effectiveDate)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. NATUREZA DO SERVIÇO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
O NeuroFlow é um aplicativo de apoio ao monitoramento de saúde mental. Ele permite que pacientes registrem diariamente humor, sono, ansiedade e outros indicadores clínicos, e que profissionais de saúde autorizados acompanhem esses dados de forma segura.

O NeuroFlow NÃO é um serviço de emergência, NÃO substitui consulta médica, psicológica ou psiquiátrica, e NÃO deve ser utilizado em situações de risco imediato de vida.

Em caso de crise ou risco imediato, ligue imediatamente para:
• CVVB (Centro de Valorização da Vida): 188 (24h, gratuito)
• SAMU: 192
• Bombeiros: 193

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
2. ELEGIBILIDADE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
O uso do NeuroFlow é permitido a:
(a) Pacientes com 18 anos ou mais, ou menores com autorização e supervisão de responsável legal;
(b) Profissionais de saúde devidamente habilitados (médicos psiquiatras, psicólogos) cadastrados pelo operador da plataforma.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
3. CADASTRO E SEGURANÇA
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Você é responsável pela confidencialidade de sua senha e das suas credenciais de acesso.
• Em caso de acesso não autorizado suspeito, comunique imediatamente pelo suporte.
• Dados de login são armazenados de forma criptografada. Senhas nunca são armazenadas em texto simples.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
4. USO ACEITÁVEL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
É vedado:
(a) Fornecer informações falsas ou de terceiros sem autorização;
(b) Utilizar o aplicativo para fins não clínicos, comerciais ou de pesquisa sem aprovação prévia;
(c) Tentar acessar dados de outros usuários ou sistemas;
(d) Engenharia reversa, decompilação ou modificação não autorizada do aplicativo.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
5. LIMITAÇÃO DE RESPONSABILIDADE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
O NeuroFlow fornece ferramentas de apoio baseadas em algoritmos. As análises automáticas de risco são orientativas e não constituem diagnóstico médico. O profissional de saúde é o único responsável pelo diagnóstico e tratamento.

O operador não se responsabiliza por danos decorrentes de:
• Uso inadequado do aplicativo;
• Interpretação equivocada de resultados automáticos;
• Falhas de conectividade ou indisponibilidade temporária do serviço.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
6. PROPRIEDADE INTELECTUAL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Todo o código, design, conteúdo e marcas do NeuroFlow são propriedade do operador ou de seus licenciantes. Os dados clínicos inseridos pelo usuário permanecem de titularidade do próprio usuário.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
7. MODIFICAÇÕES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Estes Termos podem ser atualizados periodicamente. Em caso de mudanças materiais, o usuário será notificado no aplicativo e deverá aceitar os novos termos para continuar utilizando o serviço.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
8. LEI APLICÁVEL E FORO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Estes Termos são regidos pelas leis do Brasil. Eventuais litígios serão submetidos ao foro da comarca da sede do operador.
"""

// MARK: - Privacy Policy

let neuroFlowPrivacyPolicy = """
POLÍTICA DE PRIVACIDADE — NEUROFLOW
Versão \(LegalVersion.current) | Em vigor a partir de \(LegalVersion.effectiveDate)

Base legal: Lei nº 13.709/2018 (LGPD)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. CONTROLADOR DE DADOS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
O operador da plataforma NeuroFlow atua como Controlador dos dados pessoais coletados conforme descrito nesta Política. Para questões de privacidade, entre em contato pelo suporte do aplicativo.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
2. DADOS COLETADOS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
2.1 Dados de identificação
  • Nome completo, endereço de e-mail.

2.2 Dados clínicos (dados sensíveis — art. 11 LGPD)
  • Humor, ansiedade, energia, sono, apetite, libido (escalas numéricas);
  • Registro de medicação e efeitos colaterais;
  • Textos livres: diário, pensamentos automáticos;
  • Indicadores de segurança (incluindo ideação suicida);
  • Resultados de escalas validadas (PHQ-9, GAD-7, YMRS);
  • Sinais biométricos opcionais (PPG via câmera, análise de voz) — apenas com consentimento específico.

2.3 Dados de dispositivo e uso
  • Token APNs para notificações push;
  • Logs de acesso e auditoria (ações realizadas na plataforma).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
3. FINALIDADES E BASE LEGAL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Finalidade                       | Base Legal (LGPD)
─────────────────────────────────|──────────────────────────────
Prestação do serviço clínico     | Consentimento (art. 7, I + art. 11, I)
Compartilhamento com profissional| Consentimento específico (art. 11, I)
Segurança e prevenção de fraude  | Legítimo interesse (art. 7, IX)
Cumprimento de obrigação legal   | Obrigação legal (art. 7, II)
Pesquisa anônima (opcional)      | Consentimento específico (art. 7, I)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
4. COMPARTILHAMENTO DE DADOS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Dados clínicos são compartilhados SOMENTE com:
• Profissionais de saúde vinculados pelo próprio paciente (mediante aceite explícito do convite);
• Cuidadores designados pelo paciente (com consentimento granular);
• Autoridades competentes, exclusivamente quando exigido por lei.

Não vendemos, alugamos ou compartilhamos dados com terceiros para fins comerciais.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
5. SEGURANÇA E CRIPTOGRAFIA
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Dados em trânsito: TLS 1.2+ com certificate pinning no app iOS.
• Dados em repouso (app): AES-256-GCM para rascunhos clínicos; chave no Keychain do dispositivo.
• Dados em repouso (servidor): criptografia a nível de campo (AES-256 via Fernet) para textos sensíveis.
• Credenciais: armazenadas com hash bcrypt; tokens JWT com revogação por epoch.
• Trilha de auditoria: imutável, com registro de todas as ações de acesso a dados clínicos.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
6. SEUS DIREITOS (ART. 18 LGPD)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Você tem direito a:
• Acesso: exportar todos os seus dados (Configurações → Privacidade e Dados → Exportar minha conta).
• Retificação: corrigir dados incorretos.
• Exclusão: apagar dados clínicos antigos ou toda a conta (Configurações → Privacidade e Dados).
• Portabilidade: exportar no formato JSON estruturado.
• Revogação do consentimento: cancelar o acesso de qualquer profissional a qualquer momento.
• Informação: receber informações sobre o uso dos seus dados (trilha de auditoria disponível no app).

Para exercer outros direitos não cobertos pelo app, entre em contato pelo suporte.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
7. RETENÇÃO DE DADOS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Dados clínicos: retidos pelo período de uso ativo + prazo legal de guarda de prontuários (mínimo 20 anos, conforme CFM).
• Logs de auditoria: retidos por 5 anos conforme recomendação ANPD.
• Após exclusão da conta: dados são removidos dos servidores em até 30 dias, salvo obrigação legal de retenção.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
8. DADOS DE MENORES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
O tratamento de dados de menores de 18 anos exige consentimento expresso do responsável legal, conforme art. 14 da LGPD.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
9. COOKIES E RASTREAMENTO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
O NeuroFlow não utiliza cookies de rastreamento de terceiros, SDKs de analytics, ou qualquer tecnologia de monitoramento comportamental para fins publicitários.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
10. ATUALIZAÇÕES DESTA POLÍTICA
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Em caso de alterações materiais, o usuário será notificado e deverá confirmar o novo consentimento antes de continuar usando o serviço.
"""
