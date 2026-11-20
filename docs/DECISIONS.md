# Registro de decisões

> Toda decisão importante fica aqui, com as alternativas consideradas e a recomendação.
> Status possíveis: **Aprovada**, **Recomendada (aguardando aprovação)**, **Em aberto**, **Substituída**.
> Nenhuma decisão "Recomendada" é implementada antes de ser aprovada. Ao aprovar, mude o status e registre a data.

## Já aprovadas (definidas na especificação ou na conversa de 20/11/2026)

| ID | Decisão | Status |
| --- | --- | --- |
| A-01 | Frontend: Next.js + React + TypeScript + Tailwind CSS | Aprovada |
| A-02 | Backend: Python + FastAPI + SQLAlchemy + Alembic | Aprovada |
| A-03 | Banco: PostgreSQL | Aprovada |
| A-04 | Hospedagem: Render como primeira opção | Aprovada |
| A-05 | Pagamentos: Mercado Pago, com assinaturas e webhooks | Aprovada |
| A-06 | IA independente de fornecedor | Aprovada |
| A-07 | Repositório central: `bibia-75/vagas-ia-agent` (privado) | Aprovada |
| A-08 | Fase 0 (documentação) neste ambiente; desenvolvimento e testes no Claude Code do computador da responsável pelo projeto | Aprovada |
| A-09 | Sem implementação antes da aprovação da Fase 0 | Aprovada |
| A-10 | Senhas com Argon2id | Aprovada |
| A-11 | IA nunca reprova candidatos automaticamente | Aprovada |
| A-12 | Integrações externas só por API, parceria ou mecanismo autorizado | Aprovada |
| A-13 | Nenhuma infraestrutura ou serviço pago é contratado sem estimativa de custo e autorização prévia (ver D-24) | Aprovada em 20/11/2026 |

## Resumo das aprovações de 20/11/2026 (decisões técnicas da Fase 1)

| ID | Decisão | Status | Condições registradas na aprovação |
| --- | --- | --- | --- |
| D-01 | Preservar o painel antigo em `legacy/` | Aprovada | Continuidade testada antes e depois da mudança, variáveis de ambiente preservadas, plano de volta (ver D-01) |
| D-03 | Sessões no servidor com cookie seguro | Aprovada | |
| D-04 | PostgreSQL compartilhado com RLS | Aprovada | Papel do banco usado pela aplicação sem `SUPERUSER` nem `BYPASSRLS`; testes de isolamento com esse mesmo papel (ver D-04) |
| D-05 | Celery para tarefas em segundo plano | Aprovada | |
| D-06 | Cloudflare R2 para armazenamento | Aprovada | Conta só é criada após estimativa de custo aprovada (D-24); desenvolvimento usa MinIO local |
| D-10 | Proxy do Next.js para o FastAPI | Aprovada | |
| D-16 | Render na região Virginia | Aprovada com ressalva | Implementar garantias jurídicas reais de transferência internacional, não apenas informar na política (ver D-16) |
| D-18 | Código em inglês e interface em português | Aprovada | |
| D-19 | Sentry para monitoramento | Aprovada | Plano gratuito; qualquer plano pago passa por D-24 |

Continuam pendentes, para as fases indicadas: decisões comerciais (D-13, D-20, D-21), visuais (D-17), fornecedor de IA (D-11) e as demais listadas abaixo.

## Decisões técnicas da Fase 1

Aprovadas em 20/11/2026 (resumo no topo). O texto de cada uma é mantido para registro das alternativas consideradas.

### D-01: O que fazer com o código atual

**Contexto:** o repositório tem um painel pessoal (`app.py`, `static/`) publicado no Render. O novo sistema é um produto diferente (multiusuário).

| Opção | Prós | Contras |
| --- | --- | --- |
| A. Mover para `legacy/` e manter no ar até o novo sistema substituir | Nada se perde; painel continua útil; histórico do Git preservado | Precisa ajustar o `render.yaml` do serviço antigo para apontar para `legacy/` |
| B. Apagar o código atual e começar limpo | Repositório mais simples | Perde o painel que está em uso |
| C. Criar um repositório novo para o SaaS | Separação total | Contraria a decisão A-07 |

**Recomendação: A.** No primeiro commit da Fase 1, mover para `legacy/`, ajustar o serviço antigo no Render (diretório raiz `legacy`) e confirmar que ele continua funcionando. Desligar quando o novo sistema cobrir busca de vagas e currículo direcionado. Dados pessoais atuais (perfil, currículo, respostas salvas) podem ser migrados manualmente para a conta dela no novo sistema.

**Condições da aprovação:**

1. Antes de mover qualquer arquivo, registrar o estado atual do serviço no Render: URL, comando de build e start, variáveis de ambiente existentes (só os nomes, nunca os valores), se usa `DATABASE_URL` e se o auto-deploy está ligado.
2. Testar o painel antes da mudança (`/api/health`, login, listagem de vagas) e guardar o resultado.
3. A mudança para `legacy/` vai em um PR separado e pequeno, antes de qualquer código novo. O `render.yaml` do serviço antigo passa a usar `rootDir: legacy`, mantendo nome do serviço, comandos e variáveis.
4. Se o auto-deploy estiver ligado, desligar temporariamente durante a mudança, ajustar o diretório raiz no painel do Render e só então reativar.
5. Repetir os testes do item 2 depois do deploy. Se algo falhar, reverter o PR (plano de volta) antes de seguir.
6. O workflow agendado (`scheduled-search.yml`) continua funcionando apontando para a mesma URL.

**Status:** Aprovada em 20/11/2026, com as condições acima

### D-03: Sessão no servidor ou JWT

| Opção | Prós | Contras |
| --- | --- | --- |
| A. Sessão opaca em cookie, guardada no banco com cache no Key Value | Revogação imediata (logout, suspensão, troca de senha); simples e segura | Uma consulta ao cache por requisição |
| B. JWT de curta duração + refresh token | Sem consulta por requisição | Revogação complexa; mais pontos de erro; pouca vantagem com frontend e API na mesma origem |

**Recomendação: A.**
**Status:** Aprovada em 20/11/2026

### D-04: Estratégia multiempresa

| Opção | Prós | Contras |
| --- | --- | --- |
| A. Banco e esquema compartilhados, coluna de dono + RLS | Simples de operar, uma migração para todos, custo baixo | Exige disciplina e testes de isolamento (já previstos) |
| B. Um esquema por organização | Isolamento forte | Migrações multiplicadas; inviável com milhares de empresas pequenas |
| C. Um banco por organização | Isolamento máximo | Caro e complexo; desproporcional para o produto |

**Recomendação: A**, com as três barreiras descritas em DATABASE_DESIGN.md, seção 4.
**Condições da aprovação:**

1. A aplicação (API e workers) conecta com um papel **sem** `SUPERUSER` e **sem** `BYPASSRLS`, diferente do papel dono das tabelas usado nas migrações.
2. Todas as tabelas com dono usam `ENABLE` e `FORCE ROW LEVEL SECURITY`.
3. Os testes de isolamento conectam com **o mesmo papel** da aplicação, nunca com o papel de migração.
4. Na inicialização, a API verifica o próprio papel (`rolsuper` e `rolbypassrls` em `pg_roles`) e **se recusa a subir** se algum for verdadeiro. Um teste cobre essa verificação.
5. Se o Render Postgres não permitir criar um papel separado, a Fase 1 para e a alternativa é levada para aprovação antes de seguir.

**Status:** Aprovada em 20/11/2026, com as condições acima

### D-05: Fila de tarefas

| Opção | Prós | Contras |
| --- | --- | --- |
| A. Celery | Maduro, novas tentativas, limites de taxa, filas separadas, grupos de tarefas (útil para lotes de documentos) | Configuração mais extensa |
| B. RQ | Muito simples | Menos recursos para lotes, prioridades e limites |
| C. Dramatiq ou arq | Modernos | Comunidade menor; menos material de referência |

**Recomendação: A (Celery)** com Render Key Value como broker. Tarefas agendadas pelos Cron Jobs do Render, sem Celery Beat.
**Status:** Aprovada em 20/11/2026

### D-06: Armazenamento de arquivos (o Render não oferece storage de objetos)

| Opção | Prós | Contras |
| --- | --- | --- |
| A. Cloudflare R2 | Compatível com S3, sem custo de saída de dados, preço baixo, URLs assinadas | Mais um fornecedor e painel |
| B. AWS S3 (região São Paulo) | Dados no Brasil, muito maduro | Custo de saída de dados; console mais complexo |
| C. Backblaze B2 | Barato | Menos integrações |
| D. Disco persistente do Render | Sem fornecedor extra | Não escala, sem URLs assinadas, prende a um serviço; desaconselhado |

**Recomendação: A (R2)** pelo custo e simplicidade; o código usa a API S3 genérica, então trocar para B depois é só configuração. Em desenvolvimento local, MinIO.
**Status:** Aprovada em 20/11/2026. A conta no R2 só é criada após estimativa de custo aprovada (D-24); até lá, MinIO local

### D-10: Comunicação entre frontend e backend

| Opção | Prós | Contras |
| --- | --- | --- |
| A. Next.js encaminha `/api/*` para o FastAPI (mesma origem) | Cookies simples, sem CORS, CSRF direto | Uma camada a mais de rede |
| B. Subdomínios (`app.` e `api.`) com cookies no domínio pai | Serviços independentes | Exige domínio próprio desde o início, CORS e configuração de cookies mais delicada |

**Recomendação: A.**
**Complemento da revisão técnica (20/11/2026):** com o proxy, a API recebe o IP do servidor do Next. A cadeia de confiança do IP (SECURITY_AND_LGPD.md, 4.1) passa a fazer parte desta decisão. Recomendado também que a API seja um serviço privado do Render; como pode ter custo, isso entra na estimativa da D-24.

**Status:** Aprovada em 20/11/2026

### D-16: Região do Render

O Render não tem região no Brasil. Opções: Virginia (EUA leste), Ohio, Oregon, Frankfurt, Singapura.

**Recomendação:** Virginia, pela menor latência até o Brasil entre as opções; banco, API, worker e Key Value na mesma região. A transferência internacional fica declarada na política de privacidade.
**Ressalva da aprovação:** informar a transferência internacional na política de privacidade não basta. Antes de tratar dados reais de usuários em produção, é preciso:

1. Mapear todos os fornecedores que recebem dados pessoais e onde processam (Render, R2, Sentry, provedor de e-mail, provedor de IA, Mercado Pago).
2. Para cada um, adotar um mecanismo de transferência válido pela LGPD (art. 33) e pela regulamentação da ANPD sobre transferência internacional (Resolução CD/ANPD nº 19/2024): em regra, cláusulas-padrão contratuais aprovadas pela ANPD incorporadas ao contrato ou DPA do fornecedor; outros mecanismos só com orientação jurídica.
3. Guardar os contratos, DPAs e a análise de cada fornecedor em local controlado (fora do repositório público; no repositório só a lista e o status).
4. Descrever a transferência na política de privacidade e no registro de operações de tratamento.
5. Revisão por advogado (D-21) antes do lançamento piloto com dados reais.

Isso não bloqueia o desenvolvimento com dados fictícios nas Fases 1 a 7, mas bloqueia a entrada de dados reais.

**Status:** Aprovada em 20/11/2026, com a ressalva acima

### D-18: Convenções de código

**Recomendação:** código, tabelas e endpoints em inglês; interface e documentação em português. Gerenciador de pacotes `npm` no frontend (menos atrito) e `uv` no backend (instalação rápida, arquivo de trava). Formatação: `ruff` (Python) e `prettier` + `eslint` (TypeScript). Python 3.12.
**Status:** Aprovada em 20/11/2026

## Decisões necessárias até a fase indicada

### D-02: Login social (Google, LinkedIn) · até a Fase 2

**Recomendação:** fora do MVP. Só e-mail e senha. Reavaliar com dados de uso; Google costuma ser o mais pedido.
**Status:** Recomendada (aguardando aprovação)

### D-07: OCR para documentos escaneados e fotos · até a Fase 3

| Opção | Prós | Contras |
| --- | --- | --- |
| A. Modelo de IA com visão (mesmo fornecedor do D-11) | Melhor em certificados com layout decorado; extrai e estrutura em um passo | Custo por página |
| B. Tesseract no worker | Sem custo por uso | Precisão menor; imagem do worker maior |
| C. Serviço de OCR na nuvem (Google Document AI, AWS Textract) | Precisão alta | Mais um fornecedor e contrato |

**Recomendação: A**, com B como alternativa configurável se o custo ficar alto.
**Status:** Recomendada (aguardando aprovação)

### D-08: Antivírus nos uploads · até o lançamento piloto

**Recomendação:** no MVP fechado, validação estrita de tipo e quarentena; antes do lançamento público, ClamAV em um serviço privado do Render ou serviço de varredura do próprio provedor de storage, se disponível.
**Status:** Recomendada (aguardando aprovação)

### D-09: Busca semântica (pgvector) · até a Fase 6

**Recomendação:** MVP com busca textual do PostgreSQL; pgvector na Fase 6, se o Render Postgres do plano escolhido oferecer a extensão (conferir na criação do banco).
**Status:** Recomendada (aguardando aprovação)

### D-11: Primeiro fornecedor de IA · até a Fase 3

A arquitetura permite trocar depois. Critérios para escolher: qualidade em português, saída estruturada confiável (JSON com schema), leitura de PDF e imagem, custo por token, contrato sem uso dos dados para treinamento, DPA disponível.

| Opção | Observação |
| --- | --- |
| Anthropic (Claude) | Saída estruturada, PDF e imagem nativos |
| OpenAI | Saída estruturada, PDF e imagem |
| Google (Gemini) | Saída estruturada, PDF e imagem, preços competitivos em modelos rápidos |

**Recomendação:** escolher um como principal e manter um segundo adaptador pronto para fallback. Fazer uma prova rápida na Fase 3 com 20 certificados e 10 currículos fictícios nos três, medindo acerto e custo, e decidir com dados.
**Status:** Em aberto

### D-12: Provedor de e-mail transacional · até a Fase 2

Opções: Resend, Amazon SES, Brevo, Postmark. Critérios: entregabilidade, preço inicial, painel simples, DPA.
**Recomendação:** Resend ou Brevo pelo plano gratuito e simplicidade; em desenvolvimento, Mailpit local.
**Status:** Em aberto

### D-13: Cobrança de upgrade no meio do mês · até a Fase 7

| Opção | Prós | Contras |
| --- | --- | --- |
| A. Upgrade imediato, nova assinatura começa no dia do upgrade e a antiga é cancelada | Simples com a API do Mercado Pago | O cliente paga um período "sobreposto" sem desconto |
| B. Cobrar diferença proporcional e manter a data | Mais justo | Mais complexo; conferir suporte da API de Assinaturas |

**Recomendação:** A no lançamento, com crédito manual pelo administrador em casos excepcionais; avaliar B depois.
**Status:** Recomendada (aguardando aprovação)

### D-14: Fontes externas no MVP · até a Fase 4

**Recomendação:** MVP com vagas próprias + Jobicy e Remotive, **somente após** ler e registrar os termos de uso de cada uma (atribuição, frequência permitida, uso comercial). Se algum termo proibir uso comercial, a fonte fica desligada. Gupy, LinkedIn, Indeed, InfoJobs, Catho e Vagas.com dependem de contato comercial (ver SYSTEM_ARCHITECTURE.md, seção 9.1).
**Status:** Recomendada (aguardando aprovação)

### D-15: Verificação de empresas · até a Fase 2

| Opção | Observação |
| --- | --- |
| A. Consulta automática de CNPJ em base pública (ex.: BrasilAPI) + e-mail de domínio ou documento + aprovação manual quando necessário | Equilíbrio entre automação e segurança |
| B. Só aprovação manual | Simples, não escala |
| C. Serviço pago de verificação | Mais confiável, custo por consulta |

**Recomendação: A.** Conferir disponibilidade, limites e termos da base de CNPJ escolhida na Fase 2.
**Status:** Recomendada (aguardando aprovação)

### D-17: Identidade visual e sistema de design · até a Fase 2

**Recomendação:** shadcn/ui sobre Tailwind e a paleta proposta em UI_UX_GUIDELINES.md, seção 2 (azul-petróleo e coral). Alternativa: manter os tons de marrom do painel atual.
**Status:** Em aberto (preferência visual da responsável pelo projeto)

### D-19: Monitoramento de erros · até a Fase 1

**Recomendação:** Sentry (plano gratuito no início), com remoção de dados pessoais antes do envio; monitor de disponibilidade gratuito (ex.: UptimeRobot ou Better Stack).
**Status:** Aprovada em 20/11/2026 (plano gratuito; plano pago só via D-24)

### D-20: Limites dos planos e plano gratuito para empresas · até a Fase 7

A tabela proposta está em BUSINESS_RULES.md, seção 9.1. Inclui a sugestão de um plano **Empresa Gratuito** (não previsto na especificação) para permitir teste.
**Status:** Em aberto (decisão comercial)

### D-21: Questões jurídicas e fiscais · antes de cobrar qualquer cliente e antes do lançamento público

Pontos que precisam de advogado e contador:

1. **Quem é a pessoa jurídica** que opera e recebe pelo Vagas IA (CNPJ próprio, MEI, outra empresa). Afeta conta do Mercado Pago, termos de uso, papel de controlador na LGPD e emissão de nota fiscal.
2. Termos de uso, política de privacidade e acordo de tratamento de dados (DPA) para empresas.
3. Enquadramento como agente de pequeno porte e indicação de encarregado (DPO).
4. Emissão de nota fiscal de serviço nas assinaturas.
5. Prazos de retenção de pagamentos e candidaturas.
6. Registro da marca "Vagas IA" no INPI (verificar disponibilidade).

**Status:** Em aberto (não bloqueia as Fases 1 a 6)

### D-22: Dados sensíveis em vagas afirmativas · até a Fase 5

**Recomendação:** fora do MVP. Se adotado depois, seguir SECURITY_AND_LGPD.md, seção 6.3.
**Status:** Recomendada (aguardando aprovação)

### D-23: Domínio · até a Fase 8

O sistema funciona com o domínio do Render (`*.onrender.com`) durante o desenvolvimento. Para o lançamento, registrar um domínio próprio (ex.: `.com.br`). Verificar disponibilidade junto com a marca (D-21, item 6).
**Status:** Em aberto

### D-24: Custos e contratação de infraestrutura · antes de qualquer contratação

**Regra (aprovada como A-13):** nenhum serviço pago é criado ou contratado (Render pago, banco, Key Value, R2, Sentry pago, provedor de e-mail pago, provedor de IA, domínio) sem:

1. Estimativa de custo mensal por serviço e por ambiente, com preços consultados nas páginas oficiais na data da estimativa.
2. Cenários: desenvolvimento (só local, custo zero), homologação mínima e produção piloto.
3. Limites de gasto e alertas configurados no fornecedor, quando ele oferecer.
4. Aprovação explícita registrada aqui, com data e valor aprovado.

A estimativa fica em `docs/INFRA_COSTS.md`, criada antes da primeira implantação em homologação (tarefa 1.14 do roadmap). A Fase 1 inteira roda localmente, sem custo.

**Status:** Em aberto (aguardando a estimativa)

