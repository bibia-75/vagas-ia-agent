# Vagas IA: Especificação oficial do projeto

> Documento principal do produto. Descreve **o que** o Vagas IA deve fazer.
> O **como** está nos documentos técnicos complementares listados em [README.md](README.md).
> Em caso de conflito, as decisões registradas em [DECISIONS.md](DECISIONS.md) prevalecem sobre este texto.

**O futuro do recrutamento começa aqui.**

Uma plataforma inteligente que conecta empresas e profissionais, simplificando todo o processo de contratação por meio da inteligência artificial.

Multiusuário · Multiempresa · Inteligência artificial · Marketplace de empregos · SaaS

## 1. Conceito do produto

O Vagas IA será uma plataforma SaaS de recrutamento e empregabilidade, com dois públicos principais:

**Candidatos:** pessoas que desejam encontrar emprego, organizar suas qualificações, criar currículos e acompanhar candidaturas.

**Empresas:** organizações que desejam publicar vagas, receber currículos, encontrar profissionais e gerenciar processos seletivos.

A plataforma terá inteligência artificial integrada aos dois ambientes.

O grande diferencial será a simplicidade: o usuário cadastra suas informações uma única vez e a plataforma reutiliza esses dados sempre que necessário.

**Princípio do produto: menos formulários, menos burocracia e mais automação.**

## 2. Tipos de usuários e contas

O sistema deverá possuir autenticação multiusuário.

| Perfil                    | Funcionalidades                   |
| ------------------------- | --------------------------------- |
| Visitante                 | Conhecer a plataforma e os planos |
| Candidato                 | Currículos, vagas e candidaturas  |
| Empregador                | Publicar vagas e contratar        |
| Recrutador                | Gerenciar candidatos e processos  |
| Administrador empresarial | Gerenciar empresa e equipe        |
| Administrador geral       | Gerenciar toda a plataforma       |

Uma mesma conta poderá ter perfil de candidato e participar de uma ou mais empresas como recrutador.

Cada organização terá seus próprios dados, funcionários, vagas e candidaturas.

## 3. Ambiente do candidato

O candidato terá acesso a:

- Dashboard pessoal.
- Perfil profissional.
- Cofre profissional de documentos.
- Upload múltiplo de currículos e certificados.
- Extração automática de informações por IA.
- Organização de experiências e cursos.
- Criação e edição de currículos.
- Análise ATS.
- Busca inteligente de vagas.
- Compatibilidade com oportunidades.
- Candidaturas simplificadas.
- Vagas salvas.
- Histórico de processos seletivos.
- Comunicação com empresas.
- Notificações.
- Preparação para entrevistas.

### Cadastro inteligente

O candidato poderá enviar 23 certificados de uma só vez, por exemplo.

A IA deverá identificar:

- Nome do curso.
- Instituição.
- Carga horária.
- Data de conclusão.
- Competências adquiridas.

As informações serão organizadas automaticamente e apresentadas para conferência.

O usuário não deverá cadastrar cada certificado manualmente.

### Candidatura simplificada

Ao encontrar uma oportunidade, o candidato poderá utilizar seu perfil já preenchido.

A plataforma deverá:

1. Selecionar o currículo adequado.
2. Recuperar as informações cadastradas.
3. Personalizar o currículo para a oportunidade.
4. Identificar informações faltantes.
5. Solicitar somente o que for necessário.
6. Mostrar uma revisão final.
7. Registrar a candidatura.

## 4. Ambiente do empregador

Cada empresa poderá:

- Criar seu perfil empresarial.
- Cadastrar CNPJ e informações institucionais.
- Adicionar logotipo.
- Criar equipes de recrutamento.
- Definir permissões dos funcionários.
- Publicar oportunidades.
- Editar e encerrar vagas.
- Receber candidaturas.
- Visualizar currículos.
- Analisar compatibilidade.
- Filtrar candidatos.
- Gerenciar entrevistas.
- Enviar mensagens.
- Acompanhar contratações.
- Gerar relatórios.

### Criador inteligente de vagas

A empresa não precisará escrever uma descrição completa.

Ela responderá perguntas objetivas, como:

1. Qual cargo deseja contratar?
2. Quantas pessoas?
3. Qual modalidade de trabalho?
4. Qual cidade?
5. Qual salário?
6. Quais atividades serão realizadas?
7. Quais requisitos são obrigatórios?
8. Quais ferramentas o profissional deverá conhecer?
9. Quais benefícios serão oferecidos?
10. Como será o processo seletivo?

A IA produzirá automaticamente:

- Título da oportunidade.
- Descrição profissional.
- Responsabilidades.
- Requisitos.
- Competências.
- Benefícios informados.
- Informações contratuais.

A empresa poderá editar e aprovar antes de publicar.

### Gestão de candidatos

Cada vaga terá um painel próprio, mostrando:

- Total de candidaturas.
- Candidatos em análise.
- Candidatos pré-selecionados.
- Entrevistas agendadas.
- Contratados.
- Reprovados.

Também haverá um Kanban para movimentar candidatos pelas etapas do processo seletivo.

### Inteligência artificial para recrutamento

A IA poderá ler os currículos recebidos, comparar experiências e requisitos, identificar competências e produzir resumos para o recrutador.

A classificação deverá ser explicável e servir como apoio à decisão humana, nunca como rejeição automática de candidatos.

## 5. Busca de empregos e integrações

O Vagas IA terá um mecanismo de busca de oportunidades com filtros:

- Cargo.
- Área profissional.
- Localização.
- Trabalho remoto, híbrido ou presencial.
- Salário.
- CLT, PJ, estágio e aprendiz.
- Experiência.
- Escolaridade.
- Data de publicação.

Fontes desejadas:

- Gupy.
- LinkedIn.
- Indeed.
- InfoJobs.
- Catho.
- Vagas.com.

Também existirão vagas publicadas diretamente pelas empresas dentro do Vagas IA.

As integrações externas deverão utilizar APIs, parcerias ou mecanismos expressamente autorizados por cada plataforma. Não devemos presumir que todas permitem busca e candidatura automatizadas.

> Situação real de cada fonte em novembro de 2026: ver [SYSTEM_ARCHITECTURE.md, seção 9](SYSTEM_ARCHITECTURE.md#9-busca-de-vagas-e-integrações-externas).

## 6. Inteligência artificial

A IA será dividida em serviços especializados:

| Serviço         | Função                         |
| --------------- | ------------------------------ |
| CV Agent        | Interpretar currículos         |
| Document Agent  | Ler certificados e diplomas    |
| ATS Agent       | Analisar currículos            |
| Job Creator     | Criar descrições de vagas      |
| Job Finder      | Buscar oportunidades           |
| Match Agent     | Comparar profissionais e vagas |
| Resume Agent    | Personalizar currículos        |
| Recruiter Agent | Auxiliar empresas na triagem   |
| Interview Agent | Preparar entrevistas           |
| Career Agent    | Orientar candidatos            |

Todos os serviços deverão utilizar dados autorizados, ter controle de custos e registrar operações.

A IA deverá ser independente do fornecedor de modelo, permitindo trocar a API futuramente.

## 7. Arquitetura tecnológica

| Camada         | Tecnologia                         |
| -------------- | ---------------------------------- |
| Frontend       | Next.js + React + TypeScript       |
| Backend        | Python + FastAPI                   |
| Banco de dados | PostgreSQL                         |
| IA             | Modelos de linguagem               |
| Assíncrono     | Redis + Workers                    |
| Arquivos       | Object Storage privado             |
| Hospedagem     | Render                             |

| Tecnologia    | Utilização          |
| ------------- | ------------------- |
| Next.js       | Interface web       |
| TypeScript    | Tipagem             |
| Tailwind CSS  | Design              |
| FastAPI       | APIs                |
| Python        | Lógica de negócio   |
| PostgreSQL    | Banco de dados      |
| SQLAlchemy    | ORM                 |
| Alembic       | Migrações           |
| Redis         | Filas e cache       |
| Celery ou RQ  | Tarefas assíncronas |
| S3 compatível | Armazenamento       |
| Pytest        | Testes backend      |
| Playwright    | Testes frontend     |
| GitHub        | Versionamento       |
| Render        | Hospedagem          |

## 8. Banco de dados

O banco deverá ser projetado desde o início para usuários e organizações independentes.

Principais entidades:

| Grupo        | Tabelas                                               |
| ------------ | ----------------------------------------------------- |
| Usuários     | users, user_profiles, user_preferences                |
| Empresas     | organizations, company_profiles, organization_members |
| Permissões   | organization_roles, permissions                       |
| Currículos   | resumes, resume_versions                              |
| Documentos   | documents, certificates, education                    |
| Experiências | experiences, skills                                   |
| Vagas        | jobs, job_postings, job_requirements                  |
| Candidaturas | applications, application_status_history              |
| Recrutamento | candidate_reviews, interview_schedules                |
| Comunicação  | messages, notifications                               |
| IA           | ai_interactions, ai_usage                             |
| Monetização  | subscriptions, payments                               |
| Auditoria    | audit_logs                                            |

As vagas externas e as vagas criadas pelas empresas deverão ter estruturas diferenciadas.

O banco deverá implementar isolamento por usuário e organização, controle de propriedade dos registros e, quando aplicável, Row Level Security.

> Modelo completo: [DATABASE_DESIGN.md](DATABASE_DESIGN.md).

## 9. Segurança e LGPD

Requisitos obrigatórios:

- Senhas protegidas com Argon2id.
- Autenticação segura.
- Controle de permissões.
- HTTPS.
- Proteção contra acesso indevido.
- Validação de arquivos.
- Armazenamento privado de documentos.
- Links temporários para downloads.
- Backups.
- Logs de segurança.
- Controle de sessões.
- Exportação e exclusão de dados.
- Gestão de consentimentos e bases legais.
- Política de privacidade.
- Termos de uso.
- Controle de retenção de currículos.

Dados de candidatos e empresas nunca poderão ser misturados ou disponibilizados sem autorização.

## 10. Painel administrativo geral

O administrador do Vagas IA terá acesso a:

- Usuários cadastrados.
- Empresas cadastradas.
- Empresas verificadas.
- Vagas publicadas.
- Candidaturas.
- Assinaturas.
- Pagamentos.
- Consumo de IA.
- Integrações.
- Erros.
- Logs.
- Indicadores gerais.

O acesso aos documentos privados deverá ser restrito, justificado e auditável.

## 11. Monetização

O produto será freemium, com planos para candidatos e empresas.

Valores iniciais para validação comercial:

| Plano            | Preço sugerido |
| ---------------- | -------------- |
| Candidato Free   | R$ 0           |
| Candidato Pro    | R$ 29,90/mês   |
| Empresa Start    | R$ 79,90/mês   |
| Empresa Pro      | R$ 149,90/mês  |
| Empresa Business | R$ 299,90/mês  |

O administrador poderá alterar limites e preços.

Gateway de pagamento: Mercado Pago (decisão registrada em [DECISIONS.md](DECISIONS.md)), com webhooks para assinaturas e pagamentos.

## 12. Roadmap de desenvolvimento

1. **Fundação e arquitetura:** repositório, frontend e backend, PostgreSQL, estrutura de pastas, variáveis de ambiente, migrações e testes.
2. **Autenticação e multiusuário:** cadastro e login, recuperação de senha, perfil de candidato, perfil empresarial, equipes, permissões e isolamento de dados.
3. **Perfil profissional e documentos:** upload múltiplo, leitura de currículos e certificados, cofre profissional, organização automática, revisão e edição.
4. **Sistema de vagas:** cadastro manual, criador de vagas por IA, edição e publicação, busca e filtros, vagas próprias e externas.
5. **Candidaturas e recrutamento:** candidatura simplificada, painel de candidatos, visualização de currículos, compatibilidade, Kanban, entrevistas e mensagens.
6. **Inteligência artificial:** análise ATS, personalização de currículos, análise de candidatos, recomendações, preparação para entrevistas e controle de custos de IA.
7. **Monetização e administração:** planos, assinaturas, pagamentos, painel administrativo e controle de limites.
8. **Testes e lançamento:** segurança, testes de isolamento, testes de carga, monitoramento, correção de erros e lançamento piloto.

> Detalhamento de cada fase: [DEVELOPMENT_ROADMAP.md](DEVELOPMENT_ROADMAP.md).

## 13. Estrutura do repositório

Ver [SYSTEM_ARCHITECTURE.md, seção 4](SYSTEM_ARCHITECTURE.md#4-estrutura-do-repositório).

## 14. Método de desenvolvimento (regras para o Claude Code)

Trabalhar por fases. Antes de programar: arquitetura, estrutura do repositório, modelo de dados, permissões, contratos das APIs e planejamento técnico. Depois implementar a primeira fase.

- Não avançar para outra fase sem testar a anterior.
- Não simular funcionalidades reais.
- Não criar botões sem ações funcionais.
- Não utilizar dados fictícios como dados reais.
- Não deixar credenciais no código.
- Não alterar o banco sem migrações.
- Não remover funcionalidades sem avaliar dependências.

Ao concluir cada fase, informar: arquivos criados, funcionalidades implementadas, migrações realizadas, testes executados, resultados, pendências e próxima etapa.

> Regras operacionais completas: [CLAUDE.md](../CLAUDE.md) na raiz do repositório.

## 15. Critério de pronto do MVP (primeiro lançamento)

- [ ] Cadastro, login e recuperação de senha funcionando.
- [ ] Perfil de candidato e perfil empresarial.
- [ ] Organizações e permissões de recrutadores.
- [ ] Upload múltiplo e leitura de currículos e certificados.
- [ ] Cofre profissional e revisão dos dados extraídos.
- [ ] Criador de vagas por IA.
- [ ] Publicação e busca de vagas.
- [ ] Candidatura simplificada.
- [ ] Painel empresarial com candidatos e currículos.
- [ ] Pipeline de recrutamento.
- [ ] Isolamento de dados testado entre usuários e empresas.
- [ ] Política de privacidade, exclusão de dados e monitoramento.

## Recomendação de produto

Desenvolver o Vagas IA como um produto único, com dois ambientes integrados, e não como dois sites separados. Começar pelo MVP, validar o fluxo de contratação entre empresas e candidatos e só depois investir nas integrações externas e automações mais complexas. Primeiro fazer a arquitetura funcionar localmente, depois configurar banco, produção e custos de IA.

O sucesso do Vagas IA não será medido pela quantidade de funcionalidades, mas pelo quanto ele simplifica a vida de quem procura emprego e de quem precisa contratar.
