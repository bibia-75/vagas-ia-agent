# Plano de desenvolvimento

> Ordem de construção, entregas e critérios de pronto de cada fase.
> Regra geral: **uma fase só começa depois que a anterior estiver testada e aprovada.**

## Visão geral

| Fase | Nome | Entrega principal | Depende de |
| --- | --- | --- | --- |
| 0 | Documentação técnica | Esta pasta `docs/` aprovada | n/a |
| 1 | Fundação multiusuário e multiempresa | Estrutura do monorepo, banco com RLS, núcleo de identidade e organizações, testes de isolamento, CI | D-01, D-03, D-04, D-05, D-06, D-10, D-16, D-18, D-19 (aprovadas em 20/11/2026) |
| 2 | Autenticação e organizações | Cadastro, login, sessões, recuperação de senha, perfis, criação de empresas, convites, papéis | Fase 1, D-12, D-15, D-17 |
| 3 | Perfil profissional e documentos | Perfil completo, upload múltiplo, leitura por IA, cofre, revisão em lote, currículos básicos | Fase 2, D-07, D-11 |
| 4 | Sistema de vagas | Vagas manuais, criador por IA, publicação, busca, vagas externas autorizadas | Fase 3, D-14 |
| 5 | Candidaturas e recrutamento | Candidatura simplificada, pipeline Kanban, painel da vaga, entrevistas, mensagens, resumos de IA | Fase 4 |
| 6 | IA avançada | ATS, personalização de currículo, compatibilidade, preparação para entrevistas, painel de custos | Fase 5, D-09 |
| 7 | Monetização e administração | Planos, Mercado Pago, limites, painel administrativo, MFA da equipe | Fase 6, D-13, D-20, D-21 |
| 8 | Testes e lançamento | Segurança, carga, monitoramento, runbooks, documentos legais, piloto | Fase 7, D-08, D-21, D-23 |

O **MVP** (checklist da MASTER_SPECIFICATION.md, seção 15) fica completo ao final da Fase 5 + partes essenciais das Fases 7 e 8 (privacidade, exclusão de dados, monitoramento). Cobrança pode entrar depois do piloto gratuito, se preferir validar o produto primeiro.

## Fase 1: Fundação multiusuário e multiempresa (detalhada)

### Objetivo

Deixar pronta a base sobre a qual tudo será construído: estrutura do projeto, ambiente local completo, banco com migrações e isolamento por RLS funcionando e testado, núcleo de usuários e organizações no banco, padrões de API, erros, logs e CI. **Sem telas de produto e sem endpoints de login** (isso é Fase 2).

### Pré-requisitos no computador

- Git, Docker Desktop, Node.js 22 LTS, Python 3.12, `uv`.
- Claude Code com acesso ao repositório clonado.
- Ler `CLAUDE.md` e esta pasta `docs/`.

### Tarefas

| # | Tarefa | Detalhes | Resultado verificável |
| --- | --- | --- | --- |
| 1.1 | Preservar o painel atual (D-01) | **Envolve uma ação manual no painel do Render, feita pela responsável pelo projeto e só com a autorização dela; o Claude Code não acessa o Render e não deve tentar.** O Claude Code prepara o PR e um passo a passo; ela registra a configuração atual, ajusta o diretório raiz e o auto-deploy no Render e confirma os testes. Seguir as 6 condições da D-01: registrar configuração atual do serviço (sem valores de segredos), testar antes, PR separado só com a mudança para `legacy/` (`rootDir: legacy`, mesmo nome, comandos e variáveis), cuidar do auto-deploy, testar depois, reverter se falhar. Workflow de validação aponta para `legacy/` | Testes de antes e depois registrados no relatório; painel respondendo em `/api/health`, login e listagem funcionando; busca agendada ainda funcionando |
| 1.2 | Ambiente local | `docker-compose.yml` com PostgreSQL 16 (imagem com pgvector), Valkey, MinIO (com criação automática do bucket) e Mailpit; `.env.example` completo e comentado | `docker compose up` sobe tudo; serviços saudáveis |
| 1.3 | Esqueleto do backend | `backend/pyproject.toml` (uv), estrutura de pastas da SYSTEM_ARCHITECTURE.md seção 4, `app/main.py` com fábrica da aplicação, `core/config.py` (pydantic-settings, falha se faltar variável obrigatória), `core/logging.py` (JSON com `request_id`), `core/errors.py` (problem+json), `core/db.py` (SQLAlchemy async, sessão por requisição) | `GET /api/health` e `/api/health/ready` respondem; erros saem no formato padrão |
| 1.4 | Migrações | Alembic configurado com convenção de nomes de índices e restrições; migração 0001: extensões (`citext`, `pg_trgm`, `unaccent`), tipos enum base, funções de contexto (`app_current_user_id()`, `app_current_org_id()`, `app_is_active_member()`) | `alembic upgrade head` e `downgrade base` funcionam em banco vazio |
| 1.5 | Núcleo de identidade e organizações | Migração 0002 com `users`, `user_sessions`, `auth_tokens`, `login_attempts`, `organizations`, `company_profiles`, `permissions`, `organization_roles`, `role_permissions`, `organization_members` (com o gatilho de proteção do `owner`), `organization_invitations`, `audit_logs` (com `subject_user_id` e gatilho de imutabilidade), `access_logs`, `admin_access_grants`, `storage_deletion_queue`, `legal_documents`, `consents`, conforme DATABASE_DESIGN.md; semente de permissões e papéis de sistema (PERMISSIONS.md) | Tabelas criadas; `alembic check` sem diferenças |
| 1.6 | RLS | Funções de contexto com `nullif` (DATABASE_DESIGN.md 4.3), funções de autenticação (4.4) e de organização necessárias à fase, todas seguindo as regras de `SECURITY DEFINER` (4.5); políticas das tabelas da 1.5 exatamente como na matriz (4.6); `FORCE ROW LEVEL SECURITY`; contexto por transação (`set_config(..., true)`) aplicado automaticamente na sessão do SQLAlchemy. Usar `docs/prototypes/rls_prototype.sql` como referência testada, reescrevendo em Alembic | Testes da 1.10 passam |
| 1.7 | Papéis do banco (condições da D-04) | Papéis `vagas_owner` (migrações), `vagas_app` (API), `vagas_worker` (tarefas de sistema), `vagas_ctx_definer`, `vagas_auth_definer` e `vagas_account_definer` (sem login, donos das funções), conforme DATABASE_DESIGN.md 4.2. A verificação de que o Render permite criar esses papéis é feita **pela documentação oficial do Render**; se não for conclusiva, por teste com banco gratuito temporário, sem dados reais, **só com autorização prévia** e sem criar nada pago. Papel `vagas_app` **sem `SUPERUSER` e sem `BYPASSRLS`**; em `audit_logs`, `INSERT` e `SELECT` (leitura filtrada pela RLS: organização com `org.audit.view`, titular e administrador), **sem `UPDATE` e sem `DELETE`**; em `access_logs`, só `INSERT`; em `users`, só `SELECT` e `UPDATE` de `full_name` e `password_hash`. Verificação na inicialização: a API consulta `pg_roles` e se recusa a subir se o próprio papel tiver `rolsuper` ou `rolbypassrls`. Localmente os seis papéis são criados pelo script de inicialização do Docker. Se o Render não permitir, parar e levar a alternativa para aprovação | Teste da recusa de inicialização com papel privilegiado; teste de que `UPDATE` e `DELETE` em `audit_logs` falham com `vagas_app` |
| 1.8 | Autorização (núcleo) | `core/authz.py` com `require_org_permission` e resolução de membro + permissões, ainda sem login (usado nos testes com usuário injetado) | Testes unitários da matriz de PERMISSIONS.md para os papéis de sistema |
| 1.9 | Serviços de apoio | `storage/` (cliente S3, URL assinada de upload e download, testado contra MinIO); `workers/` (app Celery, tarefa `ping` com teste); rate limiting no Key Value; `audit/` com função `record()` | Testes de integração passam com a stack local |
| 1.10 | Testes de isolamento | Portar para o pytest os testes T01 a T24 do protótipo (`docs/prototypes/`) e as 9 mutações de `run_mutations.sh`, e acrescentar os das demais tabelas da fase, conforme DATABASE_DESIGN.md 4.7. Pasta `tests/isolation/` com fixtures que criam dois usuários e duas organizações (dados preparados com `vagas_owner`); **as verificações conectam com `vagas_app`, o mesmo papel da aplicação**, e um teste falha se a conexão de teste tiver `BYPASSRLS` ou `SUPERUSER`. Casos: usuário A não lê, não altera, não apaga dados de B; membro de X não vê Y; membro removido perde acesso | Todos verdes; a falta de qualquer política faz um teste falhar |
| 1.11 | Esqueleto do frontend | `frontend/` com Next.js (App Router, TypeScript estrito), Tailwind, tokens de cor como variáveis CSS, shadcn/ui inicializado com Button e Card, proxy `/api/*` para o backend (D-10) com a cadeia de confiança do IP (descarta `X-Vagas-Client-IP` vindo do navegador e envia o seu, assinado com HMAC; SECURITY_AND_LGPD.md 4.1) e validação correspondente no middleware da API, cliente da API com tipos gerados do OpenAPI (`npm run gen:api`) | Página `/status` mostra o resultado real de `/api/health/ready`; nenhum botão sem ação |
| 1.12 | Qualidade | ruff, mypy (modo estrito em `core/`), pytest com cobertura; eslint, prettier, `tsc --noEmit`; Playwright com um teste da página `/status` em 390 px e 1280 px | Comandos documentados no README passam localmente |
| 1.13 | CI | `ci.yml` (backend com serviço PostgreSQL e Valkey, migrações, testes; frontend lint, tipos, build), `e2e.yml`, `security.yml` (pip-audit, npm audit, gitleaks) | CI verde no PR da Fase 1 |
| 1.14 | Blueprint do Render e custos (D-24) | `render.yaml` com os serviços da SYSTEM_ARCHITECTURE.md seção 10.1 para **homologação**, **sem aplicar no Render**; `docs/INFRA_COSTS.md` com estimativa mensal por serviço (Render, R2, Sentry, e-mail), preços consultados nas páginas oficiais e data da consulta | Arquivo validado e estimativa entregue; nenhuma conta ou serviço pago criado |
| 1.15 | Documentação | README com: requisitos, como subir o ambiente, comandos de teste, estrutura; atualização de DATABASE_DESIGN.md e DECISIONS.md se algo mudar | README permite subir o projeto do zero seguindo os passos |

### Fora do escopo da Fase 1

Telas de cadastro e login, envio de e-mail real, IA, upload de documentos pela interface, vagas, pagamentos.

### Critérios de pronto

- [ ] `docker compose up` + comandos do README sobem backend, frontend e worker localmente.
- [ ] Migrações sobem e descem em banco vazio; `alembic check` limpo.
- [ ] Todas as tabelas com dono têm RLS forçada e teste de isolamento.
- [ ] Matriz de permissões dos papéis de sistema testada.
- [ ] Logs em JSON com `request_id`; erros em problem+json.
- [ ] Nenhum segredo no repositório (gitleaks limpo).
- [ ] CI verde.
- [ ] Painel antigo continua funcionando em `legacy/`, com testes de antes e depois registrados.
- [ ] API e testes de isolamento usam papel sem `SUPERUSER` e sem `BYPASSRLS`; a API recusa subir com papel privilegiado.
- [ ] Nenhum serviço pago criado; estimativa de custos entregue em `docs/INFRA_COSTS.md`.
- [ ] **Pool de conexões real testado:** com o SQLAlchemy assíncrono e o mesmo driver da produção, um pool de tamanho 1 (forçando reutilização da conexão) e requisições concorrentes alternando usuários e organizações; nenhuma requisição enxerga o contexto (`app.user_id`, `app.org_id`) da anterior, inclusive depois de erro e de rollback no meio da transação.
- [ ] **Render verificado pela documentação oficial** (ou por teste autorizado, sem dados reais e sem nada pago): criação dos papéis da D-04, TLS nas conexões internas e método de senha. Resultado registrado no relatório e em `docs/DECISIONS.md`; se algo não for possível, a fase para para aprovação.
- [ ] **Conexões com o banco:** `docker compose` local com SCRAM-SHA-256 e sem `trust`; a API e o worker recusam iniciar em homologação ou produção sem TLS na URL de conexão (teste automatizado); `trust` só no protótipo descartável (SECURITY_AND_LGPD.md, seção 4.3).
- [ ] Relatório da fase entregue (modelo abaixo).

### Testes esperados ao fim da Fase 1

| Grupo | Exemplos |
| --- | --- |
| Configuração | aplicação não sobe sem `DATABASE_URL`; variáveis com valores inválidos geram erro claro |
| Saúde | `/api/health` 200 sempre; `/api/health/ready` 503 quando o banco está fora |
| Erros | validação devolve 422 em problem+json com lista de campos; erro inesperado devolve 500 sem detalhes internos e com `request_id` |
| Banco | restrições `CHECK` e únicas de `users`, `organizations`, `organization_members` |
| RLS | leitura, escrita e exclusão cruzadas bloqueadas entre usuários e entre organizações, sempre conectando com `vagas_app`; contexto não vaza entre transações no mesmo pool; API não sobe com papel `SUPERUSER` ou `BYPASSRLS` |
| Permissões | cada papel de sistema contra cada permissão do catálogo |
| Auditoria | `record()` grava; `UPDATE` e `DELETE` em `audit_logs` falham (privilégio e gatilho); leitura por organização com permissão, titular e admin |
| Proprietário | `admin` não altera vínculo de `owner`; o último `owner` não sai (gatilho) |
| Proxy | `X-Forwarded-For` e `X-Vagas-Client-IP` forjados são ignorados pela API; assinatura válida é aceita |
| Storage | URL de upload e download assinadas expiram; objeto em `quarantine/` não é baixável pela rota de download |
| Worker | tarefa `ping` executa e devolve resultado |
| Frontend | página `/status` renderiza o estado real em celular e desktop |

## Fases 2 a 8 (resumo de entregas e critérios)

### Fase 2: Autenticação e organizações

Entregas: endpoints e telas de cadastro, verificação de e-mail, login, logout, sessões e dispositivos, recuperação e troca de senha, troca de e-mail; aceite de termos com versão; perfil básico de candidato; criação de organização com CNPJ validado, perfil da empresa e logo; convites e aceite; gestão de membros e papéis; verificação de empresa (D-15); seletor de contexto; e-mails transacionais (D-12).
Critérios (todos obrigatórios para concluir a fase):
- Fluxos de SECURITY_AND_LGPD.md seção 2.3 testados ponta a ponta no Playwright; limites de tentativa testados; matriz de permissões testada nos endpoints reais; isolamento testado em todas as rotas `/me` e `/orgs`.
- **Sem descoberta de contas** em `POST /auth/signup`, `/auth/password/forgot` e `/auth/email/resend`: para e-mail novo e já cadastrado, mesmo status, corpo e cabeçalhos e nenhum cookie; exatamente uma tarefa enfileirada em cada caso e nenhum e-mail enviado durante a requisição (provedor de e-mail falso que falha se for chamado fora do worker); no worker, verificação para conta nova e aviso para e-mail existente, limitado a 1 por endereço a cada 24 h; diferença entre as medianas de tempo dos dois casos menor que 50 ms em 100 requisições de cada, no ambiente local.
- **Exclusão de conta completa testada:** pedido e cancelamento (já comprovados no banco pelo T23), `account_delete_finalize` numa única transação (falha simulada no meio desfaz tudo), anonimização das candidaturas e mensagens, arquivos na fila de exclusão, e-mail original liberado e **novo cadastro com o mesmo e-mail funcionando**, registros legais mantidos apontando para o registro anonimizado.

### Fase 3: Perfil profissional e documentos

Entregas: CRUD de experiências, formação, certificados, competências, idiomas e respostas salvas; upload em lote com URLs assinadas; validação de arquivos e ZIP; extração de texto e OCR (D-07); Document Agent e CV Agent (D-11); tela de revisão em lote; cofre; currículo base a partir do perfil com exportação PDF e DOCX.
Critérios: enviar 23 certificados fictícios de layouts variados e revisar tudo em uma tela; arquivos maliciosos rejeitados; métricas mínimas de extração do AI_SYSTEM_DESIGN.md seção 8 atingidas no conjunto de avaliação.

### Fase 4: Sistema de vagas

Entregas: vagas manuais com requisitos, perguntas de triagem e etapas; criador por IA com perguntas adaptativas; publicação, pausa, encerramento, expiração; página pública da vaga e da empresa; busca unificada com filtros; conectores Jobicy e Remotive após revisão de termos (D-14); deduplicação e expiração; vagas salvas.
Critérios: criador por IA não inventa informação (testes com o provedor falso e conjunto de avaliação); busca responde em menos de 300 ms com 50 mil vagas em homologação; vagas externas com atribuição.

### Fase 5: Candidaturas e recrutamento

Entregas: candidatura simplificada em até 3 passos; consentimento por candidatura; histórico do candidato; acompanhamento de candidaturas externas; painel da vaga com os indicadores da especificação; Kanban com arrastar e soltar e alternativa acessível; reprovação com motivo; contratação; avaliações internas; entrevistas; mensagens; notificações; resumo e compatibilidade por IA para recrutador; relatórios básicos.
Critérios: fluxo completo empresa ↔ candidato no Playwright; conflito de movimentação concorrente tratado; nenhum caminho de reprovação automática; checklist do MVP coberto exceto itens das Fases 7 e 8.

### Fase 6: IA avançada

Entregas: ATS, personalização de currículo com diferença visível, preparação para entrevistas, compatibilidade na busca, busca semântica (D-09), painel de custos de IA e medição de custo por operação (AI_SYSTEM_DESIGN.md seção 6.2).
Critérios: zero invenções no conjunto de avaliação do Resume Agent; teste de viés aprovado; custo por operação medido e limites revisados (RN-BIL-09).

### Fase 7: Monetização e administração

Entregas: planos configuráveis; checkout e assinaturas no Mercado Pago; webhooks idempotentes com validação de assinatura; carência, expiração e volta ao plano gratuito; reconciliação diária; contadores e bloqueio por limite; painel administrativo completo; MFA para a equipe; acesso administrativo justificado.
Critérios (todos obrigatórios para concluir a fase):
- Testes com credenciais de teste do Mercado Pago cobrindo aprovação, recusa, inadimplência, cancelamento e webhook repetido ou falso.
- **Exclusão de organização completa testada:** pedido e cancelamento pelo `owner`, `org_delete_finalize` numa única transação (falha simulada no meio desfaz tudo), candidaturas reduzidas ao mínimo e preservadas no histórico do candidato, vagas mantidas como registro encerrado, membros removidos, arquivos na fila de exclusão, CNPJ liberado para novo cadastro, pagamentos e auditoria mantidos, chaves estrangeiras válidas ao final.

### Fase 8: Testes e lançamento

Entregas: revisão OWASP ASVS nível 2; teste de carga; antivírus (D-08); monitoramento e alertas; teste de restauração de backup; runbooks; termos, privacidade e DPA revisados por advogado (D-21); domínio (D-23); produção no Render; piloto com um grupo pequeno de empresas e candidatos.
Critérios: checklist do MVP 100%; restauração testada; alertas disparando em teste; documentos legais publicados.

## Modelo de relatório ao fim de cada fase

```markdown
# Relatório da Fase N: <nome>

## Arquivos criados e alterados
## Funcionalidades implementadas
## Migrações realizadas (com descrição)
## Testes executados (comandos) e resultados (quantidade, cobertura)
## Decisões tomadas durante a fase (e atualização do DECISIONS.md)
## Desvios em relação à documentação (e por quê)
## Pendências e riscos
## Próxima etapa proposta
```

O relatório fica em `docs/reports/fase-N.md` e é apresentado antes de pedir aprovação para a fase seguinte.
