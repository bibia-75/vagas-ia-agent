# Especificação da API

> API REST do backend FastAPI. O contrato vivo é o OpenAPI gerado em `/api/v1/openapi.json`; este documento define as regras e o catálogo que o OpenAPI deve cumprir.
> Os tipos do frontend são gerados a partir do OpenAPI (`openapi-typescript`), nunca escritos à mão.

## 1. Convenções gerais

| Item | Regra |
| --- | --- |
| Base | `/api/v1` |
| Formato | JSON UTF-8; uploads por URL assinada (não pela API) |
| Nomes de campos | `snake_case` |
| Datas | ISO 8601 em UTC (`2026-11-20T20:32:00Z`); datas sem hora em `YYYY-MM-DD` |
| Dinheiro | inteiro em centavos + `currency` |
| IDs | UUID em texto |
| Autenticação | cookie `vagas_session` (HttpOnly, Secure, SameSite=Lax) |
| CSRF | cabeçalho `X-CSRF-Token` igual ao cookie `vagas_csrf` em `POST`, `PUT`, `PATCH`, `DELETE` |
| Idempotência | cabeçalho `Idempotency-Key` aceito (e exigido onde indicado) em criações sensíveis; resultado guardado por 24 h |
| Versionamento | quebra de contrato só em `/api/v2`; campos novos podem ser adicionados sem aviso |
| Rastreio | toda resposta traz `X-Request-Id` |

### 1.1 Paginação

Listas usam cursor:

```
GET /api/v1/me/applications?limit=20&cursor=eyJpZCI6...
```

```json
{
  "items": [ ... ],
  "next_cursor": "eyJpZCI6...",
  "has_more": true
}
```

`limit` padrão 20, máximo 100. Listas pequenas e fixas (ex.: etapas do pipeline) não são paginadas.

### 1.2 Erros

Formato `application/problem+json` (RFC 9457):

```json
{
  "type": "https://vagas-ia.app/erros/validacao",
  "title": "Dados inválidos",
  "status": 422,
  "code": "validation_error",
  "detail": "Alguns campos precisam de correção.",
  "errors": [
    { "field": "salary_max_cents", "code": "must_be_gte", "message": "O salário máximo deve ser maior ou igual ao mínimo." }
  ],
  "request_id": "01JD..."
}
```

| Status | Quando |
| --- | --- |
| 400 | Requisição malformada |
| 401 | Sem sessão ou sessão expirada (`code: not_authenticated`) |
| 403 | Autenticado, mas sem permissão no próprio contexto (`code: permission_denied`, `permission: "jobs.publish"`) |
| 404 | Não existe **ou** pertence a outro dono |
| 409 | Conflito de estado (ex.: candidatura duplicada, vaga encerrada) |
| 413 | Arquivo ou corpo grande demais |
| 422 | Validação de campos |
| 429 | Limite de requisições ou limite do plano (`code: rate_limited` ou `plan_limit_reached`, com `limit`, `used`, `resets_at`) |
| 503 | Dependência fora (IA, storage); `Retry-After` quando possível |

Mensagens de erro ao usuário em português; `code` estável em inglês para o frontend tratar.

### 1.3 Limites de requisição

| Grupo | Limite |
| --- | --- |
| `POST /auth/login` | 5 por minuto por IP + e-mail; 20 por hora por IP |
| `POST /auth/signup`, `/auth/password/forgot` | 5 por hora por IP |
| Rotas de IA síncronas | 10 por minuto por usuário (além do limite do plano) |
| Demais rotas autenticadas | 120 por minuto por usuário |
| Rotas públicas | 60 por minuto por IP |

Implementação com contador no Key Value.

## 2. Autenticação e sessão (`/auth`)

| Método | Rota | Descrição |
| --- | --- | --- |
| POST | `/auth/signup` | Cria conta; envia e-mail de verificação |
| POST | `/auth/email/verify` | Confirma e-mail com token |
| POST | `/auth/email/resend` | Reenvia verificação (resposta sempre 202) |
| POST | `/auth/login` | Cria sessão |
| POST | `/auth/logout` | Encerra a sessão atual |
| POST | `/auth/logout-all` | Encerra todas as sessões do usuário |
| POST | `/auth/password/forgot` | Envia link de redefinição (resposta sempre 202) |
| POST | `/auth/password/reset` | Redefine com token; revoga todas as sessões |
| POST | `/auth/password/change` | Troca de senha logado (exige senha atual) |
| GET | `/auth/session` | Usuário atual, contextos disponíveis e token CSRF |
| GET | `/auth/sessions` | Sessões ativas (dispositivos) |
| DELETE | `/auth/sessions/{id}` | Encerra uma sessão específica |

### Contrato: `POST /auth/signup`

Entrada:

```json
{
  "full_name": "Maria Exemplo",
  "email": "maria@exemplo.invalid",
  "password": "uma-senha-longa-e-unica",
  "accept_terms_version": "2026-12-01",
  "accept_privacy_version": "2026-12-01"
}
```

Validações:

- `full_name`: 2 a 160 caracteres, sem só espaços.
- `email`: formato válido, até 254 caracteres, normalizado em minúsculas.
- `password`: 10 a 128 caracteres; recusada se estiver na lista de senhas comuns ou contiver o e-mail.
- Versões aceitas devem ser as vigentes em `legal_documents`.

Saída `202` (sempre a mesma, exista ou não o e-mail):

```json
{ "email_verification_required": true }
```

A resposta **não** inclui `user_id`: com e-mail já cadastrado não existe um id novo para devolver, e incluir um id só no caso de sucesso revelaria quem tem conta. Internamente, `auth_register_user` devolve o id criado ou NULL (DATABASE_DESIGN.md, seção 4.4). No NULL, a API não grava consentimentos nem tokens e só envia ao dono do e-mail um aviso de tentativa de cadastro. Tempo de resposta semelhante nos dois casos (o hash Argon2id é calculado sempre, antes da chamada).

### Contrato: `POST /auth/login`

Entrada: `{ "email": "...", "password": "...", "remember_me": true }`

Saída `200`: define os cookies `vagas_session` e `vagas_csrf` e retorna o mesmo corpo de `GET /auth/session`. Credenciais erradas: `401` com mensagem genérica "E-mail ou senha incorretos." E-mail não verificado: login permitido, mas ações que expõem o usuário a terceiros (candidatar, publicar vaga) exigem verificação (`403`, `code: email_not_verified`).

### Contrato: `GET /auth/session`

```json
{
  "user": { "id": "…", "full_name": "…", "email": "…", "email_verified": true, "platform_role": "none" },
  "contexts": {
    "candidate": true,
    "organizations": [
      { "id": "…", "slug": "loja-exemplo", "name": "Loja Exemplo", "role": "recruiter", "permissions": ["jobs.view", "applications.view"] }
    ]
  },
  "csrf_token": "…"
}
```

## 3. Conta, consentimentos e LGPD (`/me`)

| Método | Rota | Descrição |
| --- | --- | --- |
| GET / PATCH | `/me/account` | Nome, telefone, fuso |
| POST | `/me/account/email-change` | Inicia troca de e-mail (confirmação no novo endereço) |
| GET / PATCH | `/me/preferences` | Notificações e preferências |
| GET | `/me/consents` | Consentimentos vigentes e históricos |
| POST | `/me/consents` | Concede consentimento (`purpose`) |
| DELETE | `/me/consents/{purpose}` | Revoga consentimento |
| POST | `/me/data-requests` | Pede exportação ou exclusão (`type`) |
| GET | `/me/data-requests` | Acompanha pedidos |
| GET | `/me/access-history` | Quem acessou seus documentos (empresas e administração) |
| DELETE | `/me/account` | Exclusão da conta (exige senha; carência de 7 dias, ver RN-ACC-06); usa `account_request_deletion()`; resposta `409 sole_owner` quando bloqueada por RN-ACC-07 |

## 4. Perfil profissional (`/me/profile`)

| Método | Rota | Descrição |
| --- | --- | --- |
| GET / PATCH | `/me/profile` | Dados do perfil e completude |
| GET / POST | `/me/experiences` | Listar e criar |
| PATCH / DELETE | `/me/experiences/{id}` | Editar e excluir |
| PUT | `/me/experiences/order` | Reordenar |
| GET / POST / PATCH / DELETE | `/me/education[/{id}]` | Formação |
| GET / POST / PATCH / DELETE | `/me/certificates[/{id}]` | Cursos e certificados |
| GET / PUT | `/me/skills` | Substitui a lista de competências |
| GET | `/skills/search?q=` | Autocompletar do catálogo |
| GET / PUT | `/me/languages` | Idiomas |
| GET / POST / PATCH / DELETE | `/me/saved-answers[/{id}]` | Respostas reutilizáveis |

Validações relevantes: datas não futuras para conclusão; `end_date >= start_date`; URLs `https://`; carga horária entre 0,5 e 10.000 horas.

## 5. Documentos e cofre (`/me/documents`)

| Método | Rota | Descrição |
| --- | --- | --- |
| POST | `/me/upload-batches` | Cria lote e devolve URLs assinadas de upload |
| POST | `/me/upload-batches/{id}/complete` | Confirma que os arquivos foram enviados; inicia processamento |
| GET | `/me/upload-batches/{id}` | Progresso do lote (por arquivo) |
| GET | `/me/documents` | Cofre: lista com filtros por tipo e status |
| GET | `/me/documents/{id}` | Detalhes e extração |
| GET | `/me/documents/{id}/download` | Devolve URL assinada (5 min) |
| PATCH | `/me/documents/{id}` | Corrigir tipo (ex.: certificado classificado como "outro") |
| DELETE | `/me/documents/{id}` | Excluir (remove do storage) |
| POST | `/me/documents/{id}/reprocess` | Reprocessar documento com falha |
| GET | `/me/extractions/pending` | Itens aguardando revisão |
| POST | `/me/extractions/review` | Aceitar, editar ou descartar em lote |

### Contrato: `POST /me/upload-batches`

Entrada:

```json
{
  "files": [
    { "client_ref": "a1", "filename": "certificado-excel.pdf", "size_bytes": 482113, "declared_type": "application/pdf" },
    { "client_ref": "a2", "filename": "certificados.zip", "size_bytes": 9123456, "declared_type": "application/zip" }
  ],
  "hint": "certificates"
}
```

Validações: 1 a 30 arquivos; tamanhos dentro dos limites (SYSTEM_ARCHITECTURE.md, seção 7.1); extensões permitidas; limite do plano (`documents.processed` do mês).

Saída `201`:

```json
{
  "batch_id": "…",
  "uploads": [
    { "client_ref": "a1", "document_id": "…", "upload_url": "https://…", "method": "PUT", "headers": { "Content-Type": "application/pdf" }, "expires_at": "…" }
  ]
}
```

### Contrato: `GET /me/upload-batches/{id}`

```json
{
  "id": "…",
  "status": "processing",
  "total_files": 23,
  "processed_files": 17,
  "failed_files": 1,
  "documents": [
    { "id": "…", "filename": "certificado-excel.pdf", "status": "needs_review", "kind": "certificate" },
    { "id": "…", "filename": "foto.png", "status": "rejected", "error_code": "unreadable_image", "error_message": "Não foi possível ler o texto desta imagem." }
  ]
}
```

### Contrato: `POST /me/extractions/review`

```json
{
  "items": [
    { "extraction_id": "…", "action": "accept", "data": { "course_name": "Excel Avançado", "institution": "Escola Exemplo", "workload_hours": 40, "completed_on": "2025-08-10", "skills": ["Excel", "Tabela dinâmica"] } },
    { "extraction_id": "…", "action": "discard" }
  ]
}
```

`data` substitui os valores sugeridos pela IA (o usuário pode editar antes de aceitar). Resposta lista os registros criados (`certificate_id`, `education_id`, etc.).

## 6. Currículos e ATS (`/me/resumes`)

| Método | Rota | Descrição |
| --- | --- | --- |
| GET / POST | `/me/resumes` | Listar e criar (vazio, a partir do perfil ou de documento) |
| GET / PATCH / DELETE | `/me/resumes/{id}` | Título, arquivar, excluir |
| GET | `/me/resumes/{id}/versions` | Histórico |
| POST | `/me/resumes/{id}/versions` | Salvar nova versão (conteúdo estruturado) |
| GET | `/me/resumes/{id}/versions/{vid}` | Ver versão |
| POST | `/me/resumes/{id}/versions/{vid}/render` | Gerar PDF ou DOCX (assíncrono, devolve `document_id`) |
| POST | `/me/resumes/{id}/tailor` | Personalizar para uma vaga (IA, assíncrono, cria versão nova) |
| POST | `/me/ats-analyses` | Análise ATS de uma versão, opcionalmente contra uma vaga |
| GET | `/me/ats-analyses/{id}` | Resultado |

## 7. Vagas: busca pública e candidato

| Método | Rota | Descrição |
| --- | --- | --- |
| GET | `/jobs/search` | Busca unificada (próprias + externas) |
| GET | `/jobs/{type}/{id}` | Detalhe (`type` = `internal` ou `external`) |
| GET | `/companies/{slug}` | Página pública da empresa e vagas abertas |
| GET / POST / DELETE | `/me/saved-jobs[/{id}]` | Vagas salvas |
| GET | `/me/job-matches/{type}/{id}` | Compatibilidade do meu perfil com a vaga |
| GET / POST | `/me/job-alerts` | Alertas de vagas (Fase 6) |

### Contrato: `GET /jobs/search`

Parâmetros (todos opcionais):

| Parâmetro | Tipo | Exemplo |
| --- | --- | --- |
| `q` | texto | `analista marketplace` |
| `area` | texto | `marketing` |
| `city`, `state` | texto, UF | `Goiânia`, `GO` |
| `work_mode` | lista | `remote,hybrid` |
| `contract_type` | lista | `clt,pj,internship,apprentice` |
| `salary_min` | inteiro em reais | `3500` |
| `seniority` | lista | `junior,mid` |
| `education_level` | enum | `superior` |
| `posted_within_days` | inteiro | `7` |
| `source` | lista | `internal,jobicy` |
| `sort` | enum | `relevance` (padrão), `recent`, `salary`, `match` |
| `limit`, `cursor` | | |

Item de resposta:

```json
{
  "type": "internal",
  "id": "…",
  "title": "Analista de Marketplace",
  "company": { "name": "Loja Exemplo", "slug": "loja-exemplo", "verified": true, "logo_url": "…" },
  "location": { "work_mode": "hybrid", "city": "Goiânia", "state": "GO" },
  "contract_type": "clt",
  "salary": { "min_cents": 350000, "max_cents": 450000, "period": "month", "currency": "BRL" },
  "posted_at": "2026-11-18T12:00:00Z",
  "source": { "key": "internal", "attribution": null },
  "apply_mode": "internal",
  "match_score": 78
}
```

`apply_mode`: `internal` (candidatura simplificada) ou `external_link` (abre a vaga original). `match_score` só aparece para usuário logado com perfil suficiente.

## 8. Candidaturas do candidato (`/me/applications`)

| Método | Rota | Descrição |
| --- | --- | --- |
| POST | `/me/applications/prepare` | Inicia a candidatura simplificada: escolhe currículo, aponta dados faltantes |
| POST | `/me/applications` | Envia candidatura (**exige `Idempotency-Key`**) |
| GET | `/me/applications` | Histórico com status |
| GET | `/me/applications/{id}` | Detalhe, linha do tempo visível ao candidato, entrevistas |
| POST | `/me/applications/{id}/withdraw` | Retira candidatura |
| POST | `/me/interviews/{id}/respond` | Confirmar ou pedir remarcação |
| GET / POST / PATCH | `/me/external-applications[/{id}]` | Acompanhamento de candidaturas externas |

### Contrato: `POST /me/applications/prepare`

Entrada: `{ "job_posting_id": "…" }`

Saída `200`:

```json
{
  "job_posting_id": "…",
  "suggested_resume": { "resume_id": "…", "version_id": "…", "reason": "Versão base mais recente" },
  "can_tailor": true,
  "missing_fields": [
    { "field": "phone", "label": "Telefone", "required": true }
  ],
  "screening_questions": [
    { "id": "…", "question": "Você tem experiência com Mercado Livre?", "answer_type": "yes_no", "required": true, "suggested_answer": "sim", "suggestion_source": "saved_answer" }
  ],
  "share_preview": { "name": "…", "email": "…", "summary": "…", "experiences": 4, "education": 2, "certificates": 23 },
  "consent_required": { "purpose": "share_with_company", "organization_name": "Loja Exemplo" }
}
```

### Contrato: `POST /me/applications`

```json
{
  "job_posting_id": "…",
  "resume_version_id": "…",
  "screening_answers": [ { "question_id": "…", "answer": "sim" } ],
  "missing_fields": { "phone": "+5500000000000" },
  "cover_letter": null,
  "consent": { "purpose": "share_with_company", "granted": true },
  "save_answers": true
}
```

Regras: vaga `published`; candidatura única por vaga (409 `already_applied`); consentimento obrigatório; e-mail verificado; campos obrigatórios completos. Saída `201` com `application_id` e status `submitted`.

## 9. Organizações (`/orgs`)

| Método | Rota | Permissão |
| --- | --- | --- |
| POST | `/orgs` | autenticado com e-mail verificado (cria e vira `owner`) |
| GET | `/orgs/{org_id}` | membro |
| PATCH | `/orgs/{org_id}` | `org.profile.update` |
| GET / PATCH | `/orgs/{org_id}/profile` | membro / `org.profile.update` |
| POST | `/orgs/{org_id}/logo` | `org.profile.update` (URL assinada) |
| POST | `/orgs/{org_id}/verification` | `org.verification.submit` |
| GET | `/orgs/{org_id}/members` | `org.members.view` |
| PATCH / DELETE | `/orgs/{org_id}/members/{member_id}` | `org.members.manage` |
| POST | `/orgs/{org_id}/invitations` | `org.members.invite` |
| DELETE | `/orgs/{org_id}/invitations/{id}` | `org.members.invite` |
| POST | `/invitations/{token}/accept` | autenticado, com o mesmo e-mail do convite |
| GET / POST / PATCH | `/orgs/{org_id}/roles[/{id}]` | `org.roles.manage` |
| POST | `/orgs/{org_id}/leave` | membro (exceto último owner) |
| DELETE | `/orgs/{org_id}` | `org.delete` (inicia o procedimento de 30 dias; DATABASE_DESIGN.md 5.2) |
| POST | `/orgs/{org_id}/transfer-ownership` | só `owner` (exige senha) |
| GET | `/orgs/{org_id}/audit-logs` | `org.audit.view` |

`POST /orgs` com CNPJ: valida dígitos verificadores; se o CNPJ já pertencer a outra organização, retorna 409 e orienta pedir convite ao administrador dela.

## 10. Vagas da organização (`/orgs/{org_id}/jobs`)

| Método | Rota | Permissão |
| --- | --- | --- |
| GET | `/orgs/{org_id}/jobs` | `jobs.view` |
| POST | `/orgs/{org_id}/jobs` | `jobs.create` (rascunho manual) |
| GET / PATCH | `/orgs/{org_id}/jobs/{job_id}` | `jobs.view` / `jobs.update` |
| POST | `/orgs/{org_id}/jobs/{job_id}/publish` | `jobs.publish` |
| POST | `/orgs/{org_id}/jobs/{job_id}/pause` | `jobs.publish` |
| POST | `/orgs/{org_id}/jobs/{job_id}/close` | `jobs.close` |
| POST | `/orgs/{org_id}/jobs/{job_id}/duplicate` | `jobs.create` |
| PUT | `/orgs/{org_id}/jobs/{job_id}/requirements` | `jobs.update` |
| PUT | `/orgs/{org_id}/jobs/{job_id}/screening-questions` | `jobs.update` |
| PUT | `/orgs/{org_id}/jobs/{job_id}/stages` | `jobs.update` |
| PUT | `/orgs/{org_id}/jobs/{job_id}/team` | `jobs.assign_team` |
| POST | `/orgs/{org_id}/job-drafts` | `jobs.create` (inicia criador por IA) |
| PATCH | `/orgs/{org_id}/job-drafts/{id}` | `jobs.create` (envia respostas) |
| POST | `/orgs/{org_id}/job-drafts/{id}/generate` | `jobs.create` (gera texto, assíncrono) |
| POST | `/orgs/{org_id}/job-drafts/{id}/convert` | `jobs.create` (vira `job_posting` em rascunho) |

Publicar exige: organização ativa, e-mail do usuário verificado, campos obrigatórios completos, limite de vagas ativas do plano, e (se configurado pelo administrador) organização verificada.

### Contrato: `PATCH /orgs/{org_id}/job-drafts/{id}`

```json
{
  "answers": {
    "role": "Assistente de e-commerce",
    "openings": 2,
    "work_mode": "hybrid",
    "city": "Goiânia",
    "state": "GO",
    "salary": { "min_cents": 220000, "max_cents": 260000, "period": "month", "show": true },
    "contract_type": "clt",
    "activities": "Cadastrar produtos, responder clientes, acompanhar pedidos",
    "required": ["Ensino médio completo", "Experiência com atendimento"],
    "tools": ["Excel", "Mercado Livre"],
    "benefits": ["Vale-transporte", "Vale-refeição"],
    "selection_process": "Triagem de currículo, entrevista presencial"
  }
}
```

Resposta inclui `next_questions`: perguntas adaptativas que faltam (ex.: se `work_mode = hybrid`, pergunta quantos dias presenciais). O texto gerado nunca inclui informação que não esteja em `answers` (RN-IA-03).

## 11. Recrutamento (`/orgs/{org_id}/...`)

| Método | Rota | Permissão |
| --- | --- | --- |
| GET | `/orgs/{org_id}/jobs/{job_id}/pipeline` | `applications.view` (contagens por etapa + cartões) |
| GET | `/orgs/{org_id}/applications` | `applications.view` (filtros: vaga, etapa, status, texto, nota) |
| GET | `/orgs/{org_id}/applications/{id}` | `applications.view` |
| PATCH | `/orgs/{org_id}/applications/{id}/stage` | `applications.move` |
| POST | `/orgs/{org_id}/applications/{id}/reject` | `applications.reject` (motivo interno + mensagem opcional ao candidato) |
| POST | `/orgs/{org_id}/applications/{id}/hire` | `applications.hire` |
| GET / POST | `/orgs/{org_id}/applications/{id}/reviews` | `applications.review` |
| POST | `/orgs/{org_id}/applications/{id}/ai-summary` | `applications.ai_summary` |
| GET | `/orgs/{org_id}/applications/{id}/contact` | `applications.view_contact` (e-mail e telefone; auditado) |
| GET | `/orgs/{org_id}/applications/{id}/attachments/{att_id}/download` | `documents.download` (cópia enviada na candidatura; auditado) |
| GET / POST | `/orgs/{org_id}/applications/{id}/interviews` | `interviews.manage` |
| PATCH | `/orgs/{org_id}/interviews/{id}` | `interviews.manage` |
| GET | `/orgs/{org_id}/talent-search` | `candidates.search` |
| POST | `/orgs/{org_id}/talent-search/{user_ref}/invite` | `candidates.search` (convida para se candidatar a uma vaga) |
| GET | `/orgs/{org_id}/reports/overview` | `reports.view` |
| GET | `/orgs/{org_id}/reports/jobs/{job_id}` | `reports.view` |

### Contrato: `PATCH /orgs/{org_id}/applications/{id}/stage`

```json
{ "to_stage_id": "…", "reason": "Perfil aderente", "notify_candidate": true, "expected_current_stage_id": "…" }
```

`expected_current_stage_id` evita conflito quando dois recrutadores movem o mesmo cartão ao mesmo tempo (409 `stage_conflict`). Mover para etapa do tipo `rejected` ou `hired` exige as permissões respectivas.

## 12. Mensagens e notificações

| Método | Rota | Quem |
| --- | --- | --- |
| GET | `/me/conversations` | candidato |
| GET / POST | `/me/conversations/{id}/messages` | candidato |
| GET | `/orgs/{org_id}/conversations` | `messages.send` ou `applications.view` |
| GET / POST | `/orgs/{org_id}/conversations/{id}/messages` | `messages.send` para enviar |
| POST | `/conversations/{id}/read` | participante |
| GET | `/me/notifications` | usuário |
| POST | `/me/notifications/read` | usuário (lista de IDs ou `all`) |

## 13. Planos e cobrança

| Método | Rota | Descrição |
| --- | --- | --- |
| GET | `/plans?audience=` | Planos ativos e limites (público) |
| GET | `/me/subscription` | Assinatura e consumo do candidato |
| POST | `/me/subscription/checkout` | Cria assinatura no Mercado Pago, devolve `checkout_url` (**exige `Idempotency-Key`**) |
| POST | `/me/subscription/cancel` | Cancela ao fim do período |
| GET | `/orgs/{org_id}/subscription` | `org.billing.view` |
| POST | `/orgs/{org_id}/subscription/checkout` | `org.billing.manage` |
| POST | `/orgs/{org_id}/subscription/cancel` | `org.billing.manage` |
| GET | `/orgs/{org_id}/usage` | `org.billing.view` |
| POST | `/webhooks/mercadopago` | Público (entra pelo proxy do Next em `/api/webhooks/mercadopago`), validado por assinatura |

### Webhook do Mercado Pago

1. Validar `x-signature` (HMAC com o segredo da aplicação, usando `x-request-id` e `data.id`). Inválido: `401` e registro com `signature_valid = false`.
2. Gravar em `webhook_events` (único por evento; repetido retorna `200` sem reprocessar).
3. Responder `200` imediatamente e processar em tarefa assíncrona.
4. A tarefa **consulta o recurso na API do Mercado Pago** (assinatura ou pagamento) e só confia nesse resultado, nunca no corpo do webhook.
5. Atualiza `subscriptions` e `payments` conforme BUSINESS_RULES.md, seção 9.

Tópicos usados: assinaturas (`subscription_preapproval`), pagamentos recorrentes (`subscription_authorized_payment`) e pagamentos (`payment`).

## 14. Administração (`/admin`)

Todas exigem `platform_role` adequado e MFA.

| Método | Rota | Descrição |
| --- | --- | --- |
| GET | `/admin/overview` | Indicadores gerais |
| GET | `/admin/users`, `/admin/users/{id}` | Busca e detalhe (dados de cadastro) |
| POST | `/admin/users/{id}/suspend`, `/reactivate` | Suspensão e reativação (admin), com `reason` obrigatório (10 a 500 caracteres); usa `admin_set_user_status()` |
| GET | `/admin/organizations`, `/admin/organizations/{id}` | Empresas |
| POST | `/admin/organizations/{id}/verification/decide` | Aprovar ou rejeitar verificação |
| GET | `/admin/jobs`, `/admin/applications` | Visão agregada (sem conteúdo de currículos) |
| GET / POST / PATCH | `/admin/plans[/{id}]` | Planos, preços e limites |
| GET | `/admin/subscriptions`, `/admin/payments` | Cobrança |
| GET | `/admin/ai-usage` | Consumo por dia, agente, modelo, cliente |
| GET / PATCH | `/admin/settings/ai` | Tetos de custo, modelo por agente, interruptor geral |
| GET / PATCH | `/admin/job-sources[/{id}]` | Fontes externas e execuções |
| GET | `/admin/queues`, `/admin/errors` | Operação |
| GET | `/admin/audit-logs` | Auditoria |
| POST | `/admin/access-grants` | Acesso temporário a dado privado com justificativa |
| GET | `/admin/data-requests` | Pedidos LGPD |

## 15. Saúde

| Rota | Descrição |
| --- | --- |
| `GET /api/health` | Processo vivo (sem dependências) |
| `GET /api/health/ready` | Banco, Key Value e storage respondendo |

## 16. Regras de implementação

1. Todo endpoint tem schema Pydantic de entrada e de saída; nada de `dict` livre na resposta.
2. Campos de saída explicitamente listados: modelos SQLAlchemy nunca são serializados diretamente.
3. Todo endpoint tem pelo menos: teste de sucesso, teste de validação, teste sem sessão (401) e, se for de organização, teste de outro tenant (404).
4. Endpoints que disparam IA ou processamento pesado respondem `202 Accepted` com o ID do recurso e o frontend consulta o status.
5. Mudanças de contrato atualizam este documento no mesmo PR.
