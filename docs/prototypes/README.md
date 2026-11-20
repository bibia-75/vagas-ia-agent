# Protótipo de RLS da Fase 0

> **Não é código de produção nem migração.** É uma prova, num PostgreSQL real, de que o desenho de isolamento de [DATABASE_DESIGN.md, seção 4](../DATABASE_DESIGN.md#4-isolamento-e-row-level-security) funciona. A Fase 1 implementa o modelo completo com Alembic e deve **repetir e ampliar** estes testes no pytest.

| Arquivo | Conteúdo |
| --- | --- |
| `rls_prototype.sql` | Papéis, tabelas mínimas, funções de contexto, de autenticação e de status da conta, políticas RLS, privilégios (inclusive por coluna), gatilho da auditoria |
| `rls_prototype_seed.sql` | Dados fictícios (`@exemplo.invalid`) |
| `rls_prototype_tests.sql` | Testes T01 a T20, T23 e T24, executados **conectado como `vagas_app`** |
| `run_prototype.sh` | Sobe um PostgreSQL descartável, aplica tudo, roda os testes e os testes extras (T21 com o dono das tabelas e com superusuário; T22 com `vagas_worker`) |
| `run_mutations.sh` | Testes de mutação: aplica um erro proposital por vez numa cópia descartável e confere se os testes detectam |

## Execução registrada

- Data: 20/11/2026 (terceira revisão, após as correções B1, B2, B3 e `pg_temp`)
- PostgreSQL 16.15 (Ubuntu 24.04), cluster descartável local, autenticação `trust` só para o teste
- Comandos: `bash run_prototype.sh` e `bash run_mutations.sh`
- Resultado: **24 grupos de testes passaram (T01 a T24)** e **9 de 9 mutações se comportaram como esperado**

| Teste | Papel | O que comprova |
| --- | --- | --- |
| T01 | `vagas_app` | Papel da aplicação sem `SUPERUSER` e sem `BYPASSRLS` |
| T02 | `vagas_app` | Depois de uma transação com `set_config(..., true)`, a variável vira texto vazio; o helper com `nullif` devolve NULL e nada vaza |
| T03, T04 | `vagas_app` | Usuário não lê, altera, apaga nem cria dados em nome de outro |
| T05, T06, T07 | `vagas_app` | Recrutador isolado na própria organização; contexto de organização forjado não dá acesso; membro removido perde acesso |
| T08 | `vagas_app` | Candidatura só em vaga publicada, em nome próprio e na organização da vaga |
| T09 | `vagas_app` | Candidato vê a própria candidatura e entrevista; outro candidato não |
| T10 | `vagas_app` | Empresa vê o anexo enviado na candidatura, mas não o cofre pessoal do candidato; outra empresa não vê |
| T11, T12 | `vagas_app` | Login e sessão por funções `SECURITY DEFINER` com validação de entrada; `users` e `user_sessions` fechadas sem contexto |
| T13 | `vagas_app` | Cadastro: devolve o id criado; **e-mail duplicado (inclusive com outra caixa) devolve NULL e não cria nada**; parâmetros nulos e hash fora do padrão recusados; sem `INSERT` direto em `users` |
| T14 | `vagas_app` | Auditoria: aplicação grava e não altera nem apaga; leitura por organização com `org.audit.view`, pelo titular e pelo administrador |
| T15 | `vagas_app` | Administrador só vê documento privado com concessão vigente; variável `app.platform_role` forjada não vale (papel lido do banco) |
| T16 | `vagas_app` | Candidato não altera status da candidatura; só retira pela função, e só a própria |
| T17 | `vagas_app` | Diretório da equipe só para membros ativos |
| T18 | `vagas_app` | `access_logs`: aplicação só grava, não lê |
| T19 | `vagas_app` | As 12 funções `SECURITY DEFINER` têm `search_path` fixo **terminando em `pg_temp`**, dono sem login, sem superusuário e sem `BYPASSRLS`, e **nenhuma é executável por `PUBLIC`** |
| T20 | `vagas_app` | Visitante vê só vagas publicadas |
| T21 | `vagas_owner` e superusuário | Dono das tabelas (sob RLS forçada) não altera auditoria; gatilho bloqueia `UPDATE` e `DELETE` até para superusuário |
| T22 | `vagas_worker` | Worker lê e aplica retenção em `access_logs` |
| T23a | `vagas_app` | `UPDATE` direto de `users.status`, `users.platform_role` e `users.email` recusado por privilégio de coluna; nome continua editável |
| T23b | `vagas_app` (titular) | Pedido de exclusão: status `pending_deletion`, sessões revogadas, auditoria visível ao titular; pedido repetido recusado; cancelamento volta a `active`, com auditoria |
| T23c | `vagas_app` | Único owner de organização com equipe é bloqueado (RN-ACC-07); owner sem equipe pode pedir; sem usuário no contexto, as funções recusam |
| T23d | `vagas_app` (admin) | Suspensão e reativação pelo admin; sessão do suspenso deixa de valer; auditoria com a justificativa; suspensão repetida recusada |
| T23e | `vagas_app` (admin) | Justificativa curta, status fora da lista, alvo nulo e suspender a si mesmo são recusados |
| T23f | `vagas_app` (não admin, com `app.platform_role` forjado) | Quem não é admin no banco não altera status de terceiros |
| T24 | `vagas_app` | Ataque de sombra: o atacante cria uma tabela temporária `users` com dados falsos e libera leitura a todos; a função de login continua lendo só a tabela real |

### Testes de mutação (os testes detectam erros de verdade?)

`bash run_mutations.sh`, 20/11/2026:

| Mutação | Esperado | Resultado |
| --- | --- | --- |
| M1: cadastro na versão antiga (devolve o id mesmo com e-mail duplicado) | detectar | **Detectada** pelo T13: "duplicado devolveu id de usuário inexistente" |
| M2: suspensão sem exigir administrador | detectar | **Detectada** pelo T23f |
| M3: exclusão de conta sem a regra do único owner | detectar | **Detectada** pelo T23c |
| M4: aplicação com `UPDATE` em todas as colunas de `users` | detectar | **Detectada** pelo T23a |
| M5: login com tabela sem esquema e `search_path` **sem** `pg_temp` por último (T19 retirado só nesta mutação, para isolar o T24) | detectar | **Detectada** pelo T24: a função leu a tabela do atacante |
| M6 (controle): tabela sem esquema, **com** `pg_temp` por último (T19 retirado) | passar | **Passou**: `pg_temp` por último bloqueia o ataque sozinho |
| M7: função de contexto sem `nullif` | detectar | **Detectada**: `invalid input syntax for type uuid: ""` |
| M8: candidatura sem exigir "em nome próprio" | detectar | **Detectada** pelo T08 |
| M9: permissão sem amarrar à organização do contexto | detectar | **Detectada** pelo T06 |

Ocorrências registradas durante esta revisão, sem esconder:

1. Na primeira execução, todas as mutações apareceram como "não detectadas", inclusive o controle. A causa era o próprio script: a pasta temporária era criada só com acesso do root e o usuário `postgres` não lia os arquivos. Corrigido no script; os testes do protótipo não mudaram por isso.
2. Na segunda execução, o M5 falhou com "permission denied for table users" em vez de devolver os dados falsos: a função **já estava lendo a tabela do atacante**, mas o teste modelava um atacante que não liberava leitura da própria tabela temporária. Um atacante real libera (ele é o dono). O T24 foi fortalecido com `GRANT SELECT ... TO PUBLIC` e então o M5 passou a demonstrar o ataque completo.
3. Uma mutação registrada na revisão anterior ("candidatura sem exigir vaga publicada") não é detectada por nenhum teste isolado, porque a segunda barreira (subconsulta que só enxerga vagas publicadas) continua bloqueando. Defesa em profundidade; não foi incluída no `run_mutations.sh`.

## Limitações (o que este protótipo NÃO comprova)

1. **Render:** não foi testado se o Render Postgres permite criar os papéis `vagas_owner`, `vagas_app`, `vagas_worker` e os papéis sem login das funções. O desenho evita exigir superusuário e `BYPASSRLS`, mas a criação de papéis precisa ser confirmada (DEVELOPMENT_ROADMAP.md, tarefa 1.7).
2. **Modelo parcial:** só 13 tabelas, com colunas mínimas. A matriz completa (DATABASE_DESIGN.md, seção 4.6) cobre todas as tabelas e precisa de testes equivalentes na Fase 1.
3. **Regras da API:** escopo de vaga atribuída (`job_scope = assigned_jobs`), mascaramento de contato para `viewer` e omissão de notas internas para o candidato são regras da API, não da RLS; não foram testadas aqui.
4. **Pool de conexões real** (SQLAlchemy + driver assíncrono) não foi testado; T02 simula a reutilização de conexão na mesma sessão do psql.
5. **Desempenho** das políticas com funções em tabelas grandes não foi medido.
6. Autenticação `trust` é só para o cluster descartável; nunca em ambiente real.
7. **Fluxos de e-mail** (aviso de tentativa de cadastro, confirmação e cancelamento de exclusão, aviso de suspensão) e a **resposta idêntica do endpoint de cadastro** são da API e só podem ser testados na Fase 2.
8. **Funções da Fase 2 em diante** listadas em DATABASE_DESIGN.md 4.3 e 4.4 (convites, tokens, exclusão final, banco de talentos etc.) ainda não existem no protótipo.
