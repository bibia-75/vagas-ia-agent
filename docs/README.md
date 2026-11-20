# Documentação do Vagas IA

Leia nesta ordem:

| # | Documento | Para que serve |
| --- | --- | --- |
| 1 | [MASTER_SPECIFICATION.md](MASTER_SPECIFICATION.md) | O que o produto deve fazer (visão oficial) |
| 2 | [CURRENT_STATE_ANALYSIS.md](CURRENT_STATE_ANALYSIS.md) | O que já existe no repositório e o que será reaproveitado |
| 3 | [DECISIONS.md](DECISIONS.md) | Decisões aprovadas, recomendadas e em aberto |
| 4 | [SYSTEM_ARCHITECTURE.md](SYSTEM_ARCHITECTURE.md) | Componentes, estrutura do repositório, filas, documentos, busca, ambientes, CI e operação |
| 5 | [DATABASE_DESIGN.md](DATABASE_DESIGN.md) | Tabelas, campos, relacionamentos, índices, RLS e retenção |
| 6 | [PERMISSIONS.md](PERMISSIONS.md) | Papéis, permissões e quem vê o quê |
| 7 | [API_SPECIFICATION.md](API_SPECIFICATION.md) | Convenções, endpoints, contratos e validações |
| 8 | [AI_SYSTEM_DESIGN.md](AI_SYSTEM_DESIGN.md) | Agentes, provedores, prompts, custos, erros e avaliação |
| 9 | [SECURITY_AND_LGPD.md](SECURITY_AND_LGPD.md) | Autenticação, ameaças, proteções, LGPD e auditoria |
| 10 | [BUSINESS_RULES.md](BUSINESS_RULES.md) | Regras numeradas (RN-XXX-NN), estados, planos e limites |
| 11 | [UI_UX_GUIDELINES.md](UI_UX_GUIDELINES.md) | Identidade visual, navegação, telas, responsividade e acessibilidade |
| 12 | [DEVELOPMENT_ROADMAP.md](DEVELOPMENT_ROADMAP.md) | Fases, plano detalhado da Fase 1 e modelo de relatório |
| 13 | [prototypes/README.md](prototypes/README.md) | Protótipo de RLS testado no PostgreSQL 16 (referência, não é código de produção) |

Regras para quem desenvolve (pessoas ou Claude Code): [CLAUDE.md](../CLAUDE.md).

## Como manter

- Mudou uma regra, tabela ou endpoint? Atualize o documento no mesmo PR do código.
- Decisão nova? Registre em DECISIONS.md antes de implementar.
- Relatórios de fase ficam em `docs/reports/`.
