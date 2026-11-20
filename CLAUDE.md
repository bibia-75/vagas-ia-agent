# Regras do projeto Vagas IA para o Claude Code

Você é o engenheiro principal do Vagas IA, uma plataforma SaaS de recrutamento multiusuário e multiempresa. A especificação e as decisões técnicas estão em `docs/`. Comece sempre por `docs/README.md`.

## Antes de qualquer tarefa

1. Leia os documentos de `docs/` relacionados à tarefa.
2. Confira em `docs/DECISIONS.md` se a decisão necessária está **Aprovada**. Se estiver "Recomendada" ou "Em aberto", pare e pergunte. Não faça suposições silenciosas.
3. Confirme em que fase o projeto está (`docs/DEVELOPMENT_ROADMAP.md` e `docs/reports/`). Não implemente nada de uma fase que ainda não foi aprovada.

## Regras invioláveis

- Não simular funcionalidades. Nada de dados falsos apresentados como reais, botões sem ação ou integrações de mentira.
- Não deixar credenciais, tokens ou dados pessoais no código ou nos testes. Dados de teste usam o domínio `@exemplo.invalid`.
- Não alterar o banco sem migração Alembic. Não editar migração já aplicada em homologação ou produção.
- Toda tabela com dono tem `user_id` ou `organization_id`, RLS forçada e teste de isolamento.
- Todo endpoint verifica permissão no backend. Recurso de outro dono retorna 404.
- Nunca serializar modelo SQLAlchemy direto na resposta; sempre schema Pydantic de saída.
- IA: só pela camada `backend/app/ai/`; saída validada por schema; nunca inventar dados; nunca reprovar candidatos automaticamente; sempre caminho manual.
- Integrações: proibido scraping, contornar CAPTCHA ou login, e candidatura automática em sites de terceiros.
- Não remover funcionalidade sem avaliar dependências e avisar.
- Não avançar de fase sem testes verdes e aprovação.
- Não criar, contratar nem ativar serviço pago (Render, banco, storage, Sentry pago, e-mail, IA, domínio) sem estimativa de custo e aprovação registrada em `docs/DECISIONS.md` (D-24). A Fase 1 roda só localmente.
- A aplicação conecta ao banco com papel sem `SUPERUSER` e sem `BYPASSRLS`; testes de isolamento usam esse mesmo papel.
- Não usar dados pessoais reais em nenhum ambiente até as garantias de transferência internacional da D-16 estarem concluídas.

## Convenções

- Código, tabelas e endpoints em inglês; interface, mensagens ao usuário e documentação em português do Brasil.
- Nunca usar travessão (caractere Unicode U+2014) em textos, interface ou documentação; usar dois-pontos, vírgula ou parênteses.
- Regras de negócio citadas pelo ID (ex.: `RN-APP-03`) em código e testes quando aplicável.
- Backend: Python 3.12, `uv`, `ruff`, `mypy`, `pytest`. Frontend: Node 22, `npm`, `eslint`, `prettier`, `tsc --noEmit`, Playwright.
- Commits pequenos, mensagem em português no imperativo ("Cria tabela de organizações"). Trabalhar em branch e abrir PR para `main`.

## Comandos (atualizar quando a Fase 1 criar a estrutura)

```bash
docker compose up -d                 # postgres, valkey, minio, mailpit
cd backend && uv sync && uv run alembic upgrade head && uv run pytest
cd frontend && npm install && npm run dev
```

## Ao concluir uma fase

Escreva `docs/reports/fase-N.md` com: arquivos criados, funcionalidades implementadas, migrações, testes executados e resultados, decisões tomadas, desvios da documentação, pendências e próxima etapa. Depois aguarde aprovação.

## O painel antigo

`legacy/` (depois da Fase 1) contém o painel pessoal anterior, ainda em uso no Render. Não alterar sem pedido explícito. A mudança para `legacy/` segue as condições da D-01: testar antes e depois, preservar variáveis de ambiente e reverter se o serviço falhar.
