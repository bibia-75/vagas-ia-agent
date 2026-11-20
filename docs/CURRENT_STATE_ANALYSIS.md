# Análise do repositório atual

> Situação do repositório `bibia-75/vagas-ia-agent` em 20/11/2026 (commit `48569f0`, branch `main`), antes da Fase 0.

## 1. O que existe hoje

O repositório contém um **painel pessoal de busca de vagas**, de uma única usuária, já publicado no Render (`vagas-ia-agent.onrender.com`).

| Arquivo | Conteúdo |
| --- | --- |
| `app.py` (486 linhas) | Toda a aplicação FastAPI: modelos SQLAlchemy, "migrações" manuais, autenticação, busca, pontuação, análise e geração de currículo |
| `static/index.html` (49 linhas) | Interface única em HTML e JavaScript puro |
| `requirements.txt` | FastAPI 0.115, SQLAlchemy 2.0, psycopg 3, pypdf, python-docx, reportlab, langdetect, httpx |
| `render.yaml` | Um web service no plano gratuito, variáveis `APP_USER`, `APP_PASSWORD`, `DATABASE_URL` |
| `.github/workflows/validate.yml` | Instala dependências e roda `py_compile` (não há testes) |
| `.github/workflows/scheduled-search.yml` | Chama `POST /api/search` de hora em hora entre 08h e 17h (Brasília) |
| `README.md` | Documentação honesta das funcionalidades e limitações |

### Funcionalidades implementadas

1. Login por HTTP Basic Auth com um único usuário e senha vindos de variáveis de ambiente.
2. Perfil profissional único (tabela `profile` com `id = 1`).
3. Upload de currículo em PDF (até 8 MB), extração do texto com `pypdf` e armazenamento do PDF **dentro do banco** (`LargeBinary`).
4. Busca de vagas remotas em duas fontes públicas: **Jobicy** e **Remotive**.
5. Filtros: idioma português (via `langdetect`), modalidade remota ou híbrida, restrições geográficas, salário mínimo em BRL, exclusão de vagas bilíngues em espanhol ou com inglês fluente obrigatório.
6. Pontuação heurística de compatibilidade (0 a 100) por palavras-chave.
7. Status manual das vagas e exportação CSV.
8. Análise de termos em comum e lacunas entre vaga e currículo (heurística).
9. Geração de currículo direcionado em DOCX, PDF ou TXT, **reorganizando apenas texto já existente** (sem inventar).
10. Banco de respostas salvas para perguntas de candidatura.
11. Checklist de onboarding do perfil.

## 2. O que vale reaproveitar

| Item | Como reaproveitar no novo sistema |
| --- | --- |
| Princípio "não inventar dados" na personalização | Vira regra de negócio (RN-IA-02) e requisito dos prompts do Resume Agent |
| Princípio "não contornar CAPTCHA, login ou anti-bot" | Vira regra de integrações (RN-INT-01) |
| Registro de candidatura externa só com confirmação do usuário | Vira o fluxo de "candidatura externa acompanhada" (`external_application_trackers`) |
| Coletores Jobicy e Remotive | Viram os dois primeiros conectores de `external_job_sources`, desde que os termos de uso sejam conferidos (ver DECISIONS.md, D-14) |
| Parser de salário em BRL e filtros de localização | Viram funções utilitárias testadas em `backend/app/jobs/external/normalizers.py` |
| Banco de respostas salvas | Vira `saved_answers` por usuário, usado na candidatura simplificada para "solicitar somente o que for necessário" |
| Checklist de onboarding | Vira o indicador de completude do perfil no dashboard do candidato |
| Geração de DOCX e PDF | A lógica de renderização é reaproveitável no serviço de exportação de currículos |
| `render.yaml` e workflow de validação | Base para o Blueprint multi-serviço e para o CI completo |

## 3. O que não serve para o produto SaaS (e por quê)

| Problema | Impacto | Tratamento no novo sistema |
| --- | --- | --- |
| Usuário único e Basic Auth | Impossível ter candidatos e empresas | Autenticação própria com sessões, Argon2id e organizações |
| Tabela `profile` com `id = 1` | Não existe conceito de dono do dado | Todas as tabelas com `user_id` ou `organization_id` e RLS |
| Dados pessoais da usuária como valores padrão no código (cargos, competências, salário) | Mistura dado pessoal com código; vazaria para todos os usuários | Nenhum dado pessoal no código; perfis vazios por padrão |
| "Migrações" com `ALTER TABLE` manuais na inicialização | Frágil, não versionado, diferente entre SQLite e PostgreSQL | Alembic obrigatório |
| PDF salvo dentro do banco | Banco cresce rápido, backup pesado, sem link temporário | Object storage privado com URLs assinadas |
| SQLite em `/tmp` como fallback | Perda de dados a cada reinício no Render | Somente PostgreSQL, inclusive no desenvolvimento (Docker) |
| Tudo em um arquivo | Difícil testar e evoluir | Módulos por domínio (ver SYSTEM_ARCHITECTURE.md) |
| Sem testes automatizados | Regressões silenciosas | Pytest e Playwright desde a Fase 1 |
| Busca agendada via GitHub Actions chamando endpoint público | Depende de senha em secrets e do serviço acordado | Cron job do próprio Render chamando a tarefa internamente |
| Filtro "só vagas em português" rígido | Faz sentido para uso pessoal, não para todos os usuários | Idioma vira filtro escolhido pelo usuário |
| Heurística por lista fixa de palavras (marketplace, Shopee etc.) | Viés para um perfil profissional específico | Compatibilidade baseada no perfil de cada usuário (ver AI_SYSTEM_DESIGN.md) |

## 4. Riscos imediatos encontrados

1. **O serviço atual está no ar.** Qualquer mudança em `main` dispara deploy no Render (se o auto-deploy estiver ligado). A Fase 0 não altera `app.py`, `static/` nem `render.yaml`.
2. **Persistência:** se a variável `DATABASE_URL` não foi configurada no Render, os dados do painel atual são apagados a cada reinício. Vale conferir no painel do Render.
3. **Banco gratuito do Render:** bancos PostgreSQL do plano gratuito expiram após um período e não têm recuperação. Se o painel atual usa um, convém exportar os dados que importam.
4. **Workflow agendado:** continua rodando de hora em hora enquanto os secrets existirem. Não causa dano, mas consome minutos do GitHub Actions.

## 5. Decisão necessária sobre o código atual

Ver [DECISIONS.md, D-01](DECISIONS.md#d-01-o-que-fazer-com-o-código-atual). Recomendação: mover o código atual para `legacy/` no início da Fase 1, manter o serviço atual funcionando no Render até o novo sistema ter as mesmas funções, e só então desligá-lo.
