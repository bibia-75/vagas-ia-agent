# Protótipo de RLS da Fase 0

> **Não é código de produção nem migração.** É uma prova, num PostgreSQL real, de que o desenho de isolamento de [DATABASE_DESIGN.md, seção 4](../DATABASE_DESIGN.md#4-isolamento-e-row-level-security) funciona. A Fase 1 implementa o modelo completo com Alembic e deve **repetir e ampliar** estes testes no pytest.

| Arquivo | Conteúdo |
| --- | --- |
| `rls_prototype.sql` | Papéis, tabelas mínimas, funções de contexto e de autenticação, políticas RLS, privilégios, gatilho da auditoria |
| `rls_prototype_seed.sql` | Dados fictícios (`@exemplo.invalid`) |
| `rls_prototype_tests.sql` | 20 grupos de testes executados **conectado como `vagas_app`** |
| `run_prototype.sh` | Sobe um PostgreSQL descartável, aplica tudo, roda os testes e os testes extras (T21 e T22) |

## Execução registrada

- Data: 20/11/2026
- PostgreSQL 16.15 (Ubuntu 24.04), cluster descartável local, autenticação `trust` só para o teste
- Resultado: **todos os testes passaram** (T01 a T22, 31 verificações)

| Teste | O que comprova |
| --- | --- |
| T01 | Papel da aplicação sem `SUPERUSER` e sem `BYPASSRLS` |
| T02 | Depois de uma transação com `set_config(..., true)`, a variável vira texto vazio; o helper com `nullif` devolve NULL e nada vaza |
| T03, T04 | Usuário não lê, altera, apaga nem cria dados em nome de outro |
| T05, T06, T07 | Recrutador isolado na própria organização; contexto de organização forjado não dá acesso; membro removido perde acesso |
| T08 | Candidatura só em vaga publicada, em nome próprio e na organização da vaga |
| T09 | Candidato vê a própria candidatura e entrevista; outro candidato não |
| T10 | Empresa vê o anexo enviado na candidatura, mas não o cofre pessoal do candidato; outra empresa não vê |
| T11, T12, T13 | Login, sessão e cadastro por funções `SECURITY DEFINER` com validação de entrada; tabelas `users` e `user_sessions` fechadas sem contexto |
| T14 | Auditoria: aplicação grava e não altera nem apaga; leitura por organização com `org.audit.view`, pelo titular e pelo administrador |
| T15 | Administrador só vê documento privado com concessão vigente; variável `app.platform_role` forjada não vale (papel lido do banco) |
| T16 | Candidato não altera status da candidatura; só retira pela função, e só a própria |
| T17 | Diretório da equipe só para membros ativos |
| T18 | `access_logs`: aplicação só grava, não lê |
| T19 | Toda função `SECURITY DEFINER` tem `search_path` fixo e dono sem login, sem superusuário e sem `BYPASSRLS` |
| T20 | Visitante vê só vagas publicadas |
| T21 | Dono das tabelas (sob RLS forçada) não altera auditoria; gatilho bloqueia `UPDATE` e `DELETE` até para superusuário |
| T22 | Papel do worker lê e aplica retenção em `access_logs` |

### Testes de mutação (os testes detectam erros de verdade?)

Rodamos versões propositalmente quebradas do protótipo:

| Mutação | Resultado |
| --- | --- |
| Helper sem `nullif` | Detectada: erro `invalid input syntax for type uuid: ""` |
| Política de candidatura sem exigir "em nome próprio" | Detectada pelo T08 |
| Permissão sem amarrar ao contexto da organização | Detectada pelo T06 |
| Política de candidatura sem exigir vaga publicada | **Não detectada, e corretamente:** a segunda barreira (o candidato só enxerga vagas publicadas na subconsulta) continua bloqueando o rascunho. Defesa em profundidade confirmada |

## Limitações (o que este protótipo NÃO comprova)

1. **Render:** não foi testado se o Render Postgres permite criar os papéis `vagas_owner`, `vagas_app`, `vagas_worker` e os papéis sem login das funções. O desenho evita exigir superusuário e `BYPASSRLS`, mas a criação de papéis precisa ser confirmada (DEVELOPMENT_ROADMAP.md, tarefa 1.7).
2. **Modelo parcial:** só 13 tabelas, com colunas mínimas. A matriz completa (DATABASE_DESIGN.md, seção 4.6) cobre todas as tabelas e precisa de testes equivalentes na Fase 1.
3. **Escopo de vaga atribuída** (`job_scope = assigned_jobs`), mascaramento de contato para `viewer` e omissão de notas internas para o candidato são regras da API, não da RLS; não foram testadas aqui.
4. **Pool de conexões real** (SQLAlchemy + driver assíncrono) não foi testado; T02 simula a reutilização de conexão na mesma sessão do psql.
5. **Desempenho** das políticas com funções em tabelas grandes não foi medido.
6. Autenticação `trust` é só para o cluster descartável; nunca em ambiente real.
