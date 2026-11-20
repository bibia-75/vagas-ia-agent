# Segurança e LGPD

> Requisitos de segurança, fluxos de autenticação e adequação à Lei Geral de Proteção de Dados (Lei nº 13.709/2018).
> **Aviso:** este documento organiza requisitos técnicos e boas práticas. Termos de uso, política de privacidade, papéis de controlador e operador e prazos legais devem ser revisados por advogado antes do lançamento público.

## 1. Modelo de ameaças (resumo)

| Ameaça | Exemplo | Controles principais |
| --- | --- | --- |
| Acesso a dados de outro tenant | Recrutador da empresa A troca o ID na URL e vê candidatos da empresa B | Contexto na URL validado, repositories com dono obrigatório, RLS, testes de isolamento, 404 para recurso alheio |
| Roubo de conta | Senha vazada, força bruta | Argon2id, limites de tentativa, sessões revogáveis, aviso de novo login, MFA para equipe interna |
| Sequestro de sessão | XSS lendo token | Cookie HttpOnly, CSP restritiva, nada em `localStorage` |
| Ações forjadas | Site malicioso faz o navegador do usuário publicar vaga | SameSite=Lax + token CSRF |
| Arquivo malicioso | PDF com script, ZIP bomb, executável renomeado | Validação por assinatura, limites, quarentena, antivírus [D-08] |
| Vazamento de documentos | URL de currículo compartilhada | Bucket privado, URL assinada de 5 min, auditoria de downloads |
| Abuso de IA | Injeção de instruções em currículo; uso para gerar custo | Delimitação, saída só JSON, limites por plano e teto global |
| Fraude de empresa | Empresa falsa publicando vagas para coletar dados | Verificação de CNPJ, denúncia de vaga, moderação, limites antes da verificação |
| Webhook falso | Alguém simula pagamento aprovado | Assinatura HMAC + consulta do recurso na API do Mercado Pago |
| Abuso administrativo | Funcionário da plataforma lendo currículos | Acesso com justificativa, temporário, auditado e visível ao titular |
| Injeção SQL | Filtros de busca | SQLAlchemy com parâmetros; nenhuma concatenação de SQL com entrada |

Referência de verificação: OWASP ASVS nível 2.

## 2. Autenticação

### 2.1 Senhas

- Hash **Argon2id** (`argon2-cffi`), parâmetros iniciais: memória 64 MiB, 3 iterações, paralelismo 2; recalibrar para cerca de 250 ms no servidor de produção. Rehash automático no login quando os parâmetros mudarem.
- Mínimo de 10 caracteres, máximo de 128, sem regras de composição obrigatória; recusar senhas da lista das mais comuns e senhas que contenham o e-mail ou o nome.
- Comparações em tempo constante; mensagens genéricas para não revelar se o e-mail existe.

### 2.2 Sessões

Recomendação **[D-03]:** sessão opaca no servidor (não JWT).

| Item | Valor |
| --- | --- |
| Token | 32 bytes aleatórios (`secrets.token_urlsafe`), guardado só como SHA-256 em `user_sessions` |
| Cookie | `vagas_session`, `HttpOnly`, `Secure`, `SameSite=Lax`, `Path=/` |
| Expiração por inatividade | 12 horas (30 dias com "manter conectado") |
| Expiração absoluta | 30 dias |
| Renovação | `last_seen_at` atualizado no máximo a cada 5 min; novo token gerado após login e após troca de senha |
| Revogação | logout, logout de todos os dispositivos, troca e redefinição de senha, suspensão da conta, exclusão |
| Cache | sessão válida em cache no Key Value por 60 s para não consultar o banco a cada requisição |

### 2.3 Fluxos

```mermaid
sequenceDiagram
    participant U as Usuário
    participant W as Frontend
    participant A as API
    participant E as E-mail
    U->>W: Cadastro (nome, e-mail, senha, aceite)
    W->>A: POST /auth/signup
    A->>A: Argon2id, cria user, consents, auth_token
    A->>E: Link de verificação (24 h)
    A-->>W: 201
    U->>W: Clica no link
    W->>A: POST /auth/email/verify
    A-->>W: e-mail verificado
    U->>W: Login
    W->>A: POST /auth/login
    A->>A: limites, verifica hash, cria sessão
    A-->>W: Set-Cookie sessão + CSRF
```

| Fluxo | Regras |
| --- | --- |
| Cadastro | aceite de termos e privacidade obrigatório e registrado com versão, data e IP; e-mail de verificação válido por 24 h |
| Verificação de e-mail | token de uso único; reenvio no máximo 1 a cada 60 s; sem verificação, a conta existe mas não pode candidatar nem publicar |
| Login | 5 tentativas por minuto por IP + e-mail; após 10 falhas seguidas no mesmo e-mail, atraso progressivo e e-mail de alerta ao titular |
| Novo dispositivo | e-mail "novo acesso à sua conta" com opção de encerrar a sessão |
| Esqueci a senha | resposta sempre igual; link válido por 1 h, uso único; ao redefinir, todas as sessões são revogadas e o titular recebe aviso |
| Troca de e-mail | confirmação no novo endereço; aviso no antigo com link para reverter por 7 dias |
| Convite para empresa | link válido por 7 dias; só aceito por conta com o mesmo e-mail; quem não tem conta faz cadastro antes |
| MFA (TOTP) | obrigatório para `platform_role` diferente de `none` na Fase 7; opcional para os demais depois do MVP |
| Login social (Google, LinkedIn) | fora do MVP **[D-02]** |

## 3. Autorização

Ver [PERMISSIONS.md](PERMISSIONS.md). Resumo: permissão verificada no backend em todo endpoint; recurso de outro dono retorna 404; RLS como segunda barreira.

## 4. Proteções da aplicação web

| Controle | Configuração |
| --- | --- |
| HTTPS | obrigatório (Render fornece TLS); `Strict-Transport-Security: max-age=31536000; includeSubDomains` |
| CSP | `default-src 'self'`; scripts só próprios (com nonce); imagens próprias e do storage; `frame-ancestors 'none'` |
| Cabeçalhos | `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` restritiva |
| CSRF | token duplo em métodos que alteram estado |
| CORS | desligado (mesma origem via proxy); se necessário, lista fixa de origens |
| Entrada | validação Pydantic com tamanhos máximos em todo campo de texto |
| Saída | React escapa por padrão; proibido `dangerouslySetInnerHTML` sem sanitização (descrições de vaga em Markdown são renderizadas com sanitizador) |
| Redirecionamentos | só para caminhos internos ou lista permitida |
| Dependências | `pip-audit`, `npm audit` e Dependabot; atualização de segurança em até 7 dias para falhas críticas |
| Segredos | só em variáveis de ambiente do Render; `.env` no `.gitignore`; varredura com gitleaks no CI |

## 5. Arquivos

Ver SYSTEM_ARCHITECTURE.md, seções 7 e 8. Pontos obrigatórios: validação por assinatura do arquivo, quarentena, bucket privado, nome aleatório no storage, URL assinada de 5 minutos, auditoria de download por terceiros, exclusão real ao apagar.

## 6. LGPD

### 6.1 Papéis

| Situação | Controlador | Operador |
| --- | --- | --- |
| Conta, perfil, documentos e currículos do candidato | Vagas IA | Provedores (Render, storage, IA, e-mail) |
| Candidatura recebida por uma empresa | Empresa (decide sobre o processo seletivo) | Vagas IA, para os dados tratados em nome da empresa |
| Dados da equipe da empresa (membros) | Empresa e Vagas IA, cada um na sua finalidade | |
| Pagamentos | Vagas IA | Mercado Pago (também controlador para fins próprios) |

Esses papéis precisam constar nos termos de uso para empresas e em um acordo de tratamento de dados (DPA) aceito na criação da organização. **Revisão jurídica obrigatória [D-21].**

### 6.2 Dados tratados, finalidades e bases legais

| Dado | Finalidade | Base legal (art. 7º) |
| --- | --- | --- |
| Nome, e-mail, senha (hash), telefone | Criar e manter a conta | Execução de contrato |
| Perfil, experiências, formação, certificados, currículos | Prestar o serviço ao candidato | Execução de contrato |
| Envio da candidatura a uma empresa | Participar do processo seletivo | Consentimento específico por candidatura (registrado em `consents`) e execução de contrato |
| Visibilidade no banco de talentos | Ser encontrado por empresas | Consentimento (desligado por padrão) |
| Processamento de documentos por IA | Extrair dados automaticamente | Execução de contrato, com informação clara; alternativa manual sempre disponível |
| Logs de acesso e segurança | Segurança e obrigação legal | Cumprimento de obrigação legal (Marco Civil, art. 15) e legítimo interesse |
| Dados de pagamento (sem cartão) | Cobrança | Execução de contrato e obrigação legal |
| E-mails de novidades | Marketing | Consentimento (desligado por padrão) |

### 6.3 Dados que o Vagas IA **não** coleta

Raça ou cor, religião, opinião política, filiação sindical, saúde, vida sexual, dados genéticos ou biométricos, data de nascimento, gênero, estado civil, foto obrigatória, CPF e endereço completo, salvo decisão futura documentada.

Exceção a avaliar **[D-22]:** vagas afirmativas (por exemplo, para pessoas com deficiência) podem exigir dado sensível. Se adotado: campo opcional, consentimento específico e destacado, visível só para a empresa da vaga afirmativa, nunca usado pela IA.

Se um documento enviado contiver dado sensível (ex.: atestado, RG com foto), ele fica no cofre do titular e **não** é enviado à empresa nem usado na extração além do necessário.

### 6.4 Direitos do titular (art. 18) e como atender

| Direito | Implementação |
| --- | --- |
| Confirmação e acesso | Todas as informações visíveis no perfil e no cofre; exportação completa |
| Correção | Edição direta de todos os campos |
| Portabilidade e cópia | `POST /me/data-requests {type: export}` gera ZIP com JSON e arquivos originais, disponível por 7 dias |
| Eliminação | Exclusão de conta com carência de 7 dias; depois, apagamento de perfil, documentos e currículos; candidaturas em andamento são anonimizadas na visão da empresa |
| Informação sobre compartilhamento | Tela "Com quem compartilhei" lista empresas que receberam candidaturas e acessos a documentos |
| Revogação do consentimento | Desligar banco de talentos e marketing a qualquer momento; retirar candidatura |
| Revisão de decisão automatizada (art. 20) | Não há reprovação automática; canal de contato para dúvidas |

Prazo interno de atendimento: imediato para ações de autoatendimento; até 15 dias para pedidos pelo canal do encarregado.

### 6.5 Encarregado (DPO) e canal

- Canal de contato público (e-mail dedicado) na política de privacidade.
- Agentes de pequeno porte podem ter dispensa da indicação formal de encarregado pela regulamentação da ANPD, mas o canal de atendimento continua obrigatório. **Confirmar enquadramento com advogado [D-21].**

### 6.6 Transferência internacional

Render (região Virginia, EUA), R2, Sentry, provedor de IA e de e-mail podem processar dados no exterior. **Informar na política de privacidade não é suficiente.** Antes de tratar dados reais (condição da aprovação da D-16):

| Passo | Entrega |
| --- | --- |
| 1. Mapa de fornecedores | Lista com cada fornecedor, dados que recebe, finalidade e país de processamento (em `docs/INFRA_COSTS.md` ou documento próprio) |
| 2. Mecanismo de transferência | Para cada fornecedor, um mecanismo válido pelo art. 33 da LGPD e pela Resolução CD/ANPD nº 19/2024; em regra, cláusulas-padrão contratuais da ANPD incorporadas ao contrato ou DPA |
| 3. Guarda de evidências | Contratos, DPAs e análises guardados fora do repositório, com acesso restrito |
| 4. Transparência | Política de privacidade e registro de operações (art. 37) descrevem a transferência |
| 5. Revisão jurídica | Advogado valida antes do piloto com dados reais (D-21) |

Preferir fornecedores que ofereçam DPA, proibição de uso dos dados para treinamento e aceitem as cláusulas-padrão. Desenvolvimento e homologação usam apenas dados fictícios até esses passos estarem concluídos.

### 6.7 Retenção

Ver DATABASE_DESIGN.md, seção 5. Tarefas diárias de manutenção aplicam a retenção automaticamente e registram o que foi apagado (contagens, sem conteúdo).

### 6.8 Incidentes de segurança

1. Conter, investigar e registrar (roteiro em `docs/runbooks/incidente-dados.md`, Fase 8).
2. Avaliar risco ou dano relevante aos titulares.
3. Se houver, comunicar a ANPD e os titulares no prazo da regulamentação vigente (Resolução CD/ANPD nº 15/2024 estabelece 3 dias úteis; **confirmar com advogado**).
4. Manter registro de todos os incidentes, mesmo os não comunicados.

### 6.9 Documentos legais necessários antes do lançamento

- Termos de uso (candidatos e empresas).
- Política de privacidade.
- Acordo de tratamento de dados para empresas (DPA).
- Política de cookies (só cookies essenciais no MVP; sem rastreadores de publicidade).
- Registro das operações de tratamento (art. 37), mantido internamente.

## 7. Auditoria

Eventos sempre registrados em `audit_logs`:

- Login, logout, falhas repetidas, troca e redefinição de senha, troca de e-mail.
- Criação de organização, convites, mudanças de papel, remoção de membros.
- Publicação, encerramento e exclusão de vagas.
- Movimentação, reprovação e contratação de candidatos.
- Download de documento de candidato por membro de empresa.
- Qualquer acesso administrativo a dado privado (com justificativa).
- Alteração de planos, preços, limites e configurações de IA.
- Pedidos LGPD e sua execução.
- Eventos de cobrança relevantes (assinatura criada, cancelada, inadimplente).

A trilha é só de inserção, com retenção de 5 anos para eventos administrativos e de segurança. O titular vê, em "Histórico de acessos", os acessos de empresas e da administração aos seus documentos.

## 8. Testes de segurança obrigatórios

| Teste | Fase | Automação |
| --- | --- | --- |
| Isolamento entre usuários (todas as rotas `/me`) | 2 em diante | pytest, a cada PR |
| Isolamento entre organizações (todas as rotas `/orgs`) | 2 em diante | pytest, a cada PR |
| RLS direto no banco com papel `vagas_app` | 1 em diante | pytest, a cada PR |
| Matriz de permissões por papel | 2 em diante | pytest declarativo |
| CSRF, cookies e cabeçalhos | 2 | pytest + Playwright |
| Limites de tentativa de login | 2 | pytest |
| Upload malicioso (extensão falsa, ZIP bomb, path traversal, PDF com JS) | 3 | pytest com arquivos de teste |
| Injeção de instruções em documento | 3 e 6 | conjunto de avaliação de IA |
| Webhook com assinatura inválida e repetido | 7 | pytest |
| Varredura de dependências e segredos | 1 em diante | CI semanal |
| Teste de carga (busca, login, pipeline) | 8 | k6 ou Locust em homologação |
| Revisão manual guiada pela OWASP ASVS nível 2 | 8 | checklist em `docs/security-review.md` |
