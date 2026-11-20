# Permissões e papéis

> Quem pode fazer o quê. Implementado em `backend/app/core/authz.py` e reforçado por RLS. A matriz por tabela e operação (SELECT, INSERT, UPDATE, DELETE) está em [DATABASE_DESIGN.md, seção 4.6](DATABASE_DESIGN.md#46-matriz-completa-de-acesso-por-tabela).

## 1. Três níveis de acesso

| Nível | Quem | Como é verificado |
| --- | --- | --- |
| **Pessoal** | Qualquer usuário autenticado sobre os próprios dados de candidato | `recurso.user_id == usuário da sessão` |
| **Organização** | Membro ativo de uma organização, conforme o papel | Papel do membro contém a permissão exigida pelo endpoint |
| **Plataforma** | Equipe do Vagas IA (`platform_role`) | `users.platform_role` + MFA + auditoria |

Uma mesma pessoa pode ser candidata e membro de várias organizações. As permissões de cada contexto são independentes: ser recrutador na empresa X não dá acesso a nada da empresa Y, e ser membro de uma empresa não dá acesso aos dados pessoais de candidato de outros membros.

## 2. Mapeamento dos perfis da especificação

| Perfil da especificação | Implementação |
| --- | --- |
| Visitante | Sem sessão; só rotas públicas |
| Candidato | Qualquer usuário autenticado (nível pessoal) |
| Administrador empresarial | Papéis `owner` e `admin` da organização |
| Empregador | Papel `hiring_manager` |
| Recrutador | Papel `recruiter` |
| (adicional) Leitor | Papel `viewer`, para gestores que só acompanham |
| Administrador geral | `platform_role = admin` |
| (adicional) Suporte | `platform_role = support`, leitura restrita sem dados privados |

## 3. Catálogo de permissões de organização

| Chave | Descrição |
| --- | --- |
| `org.profile.update` | Editar perfil institucional, logo e dados da empresa |
| `org.verification.submit` | Enviar dados para verificação de CNPJ |
| `org.members.view` | Ver a equipe |
| `org.members.invite` | Convidar membros |
| `org.members.manage` | Alterar papel, suspender, remover membros |
| `org.roles.manage` | Criar e editar papéis personalizados |
| `org.billing.view` | Ver plano, faturas e consumo |
| `org.billing.manage` | Assinar, trocar e cancelar plano |
| `org.delete` | Excluir a organização |
| `org.audit.view` | Ver trilha de auditoria da organização |
| `jobs.view` | Ver vagas da organização (respeitando `job_scope`) |
| `jobs.create` | Criar rascunhos, inclusive com o criador por IA |
| `jobs.update` | Editar vagas |
| `jobs.publish` | Publicar, pausar e reabrir vagas |
| `jobs.close` | Encerrar e arquivar vagas |
| `jobs.assign_team` | Atribuir recrutadores a vagas |
| `applications.view` | Ver candidaturas e currículos das vagas acessíveis, **sem** e-mail e telefone |
| `applications.view_contact` | Ver e-mail e telefone do candidato (lidos só pela função `application_contact`) |
| `applications.move` | Mover candidatos entre etapas |
| `applications.reject` | Reprovar candidatos |
| `applications.hire` | Marcar como contratado |
| `applications.review` | Registrar avaliações internas |
| `applications.ai_summary` | Gerar resumo e compatibilidade por IA |
| `candidates.search` | Buscar no banco de talentos (só perfis que autorizaram) |
| `documents.download` | Baixar arquivos anexados às candidaturas |
| `interviews.manage` | Agendar, remarcar e cancelar entrevistas |
| `messages.send` | Enviar mensagens a candidatos |
| `reports.view` | Ver relatórios de recrutamento |

## 4. Matriz dos papéis de sistema

✔ = tem a permissão · ◐ = só nas vagas atribuídas quando `job_scope = assigned_jobs` · em branco = não tem

| Permissão | owner | admin | hiring_manager | recruiter | viewer |
| --- | :-: | :-: | :-: | :-: | :-: |
| org.profile.update | ✔ | ✔ | | | |
| org.verification.submit | ✔ | ✔ | | | |
| org.members.view | ✔ | ✔ | ✔ | ✔ | ✔ |
| org.members.invite | ✔ | ✔ | | | |
| org.members.manage | ✔ | ✔ | | | |
| org.roles.manage | ✔ | ✔ | | | |
| org.billing.view | ✔ | ✔ | | | |
| org.billing.manage | ✔ | | | | |
| org.delete | ✔ | | | | |
| org.audit.view | ✔ | ✔ | | | |
| jobs.view | ✔ | ✔ | ✔ | ◐ | ✔ |
| jobs.create | ✔ | ✔ | ✔ | ✔ | |
| jobs.update | ✔ | ✔ | ✔ | ◐ | |
| jobs.publish | ✔ | ✔ | ✔ | | |
| jobs.close | ✔ | ✔ | ✔ | | |
| jobs.assign_team | ✔ | ✔ | ✔ | | |
| applications.view | ✔ | ✔ | ✔ | ◐ | ✔ |
| applications.view_contact | ✔ | ✔ | ✔ | ◐ | |
| applications.move | ✔ | ✔ | ✔ | ◐ | |
| applications.reject | ✔ | ✔ | ✔ | ◐ | |
| applications.hire | ✔ | ✔ | ✔ | | |
| applications.review | ✔ | ✔ | ✔ | ◐ | |
| applications.ai_summary | ✔ | ✔ | ✔ | ◐ | |
| candidates.search | ✔ | ✔ | ✔ | ✔ | |
| documents.download | ✔ | ✔ | ✔ | ◐ | |
| interviews.manage | ✔ | ✔ | ✔ | ◐ | |
| messages.send | ✔ | ✔ | ✔ | ◐ | |
| reports.view | ✔ | ✔ | ✔ | | ✔ |

Regras complementares:

- **`admin` não pode rebaixar, suspender, remover nem transferir a propriedade do `owner`**, nem promover alguém a `owner`. Só um `owner` altera vínculos com papel `owner`.
- Transferência de propriedade só pela função `org_transfer_ownership`, executada por um `owner`, com confirmação por senha.
- O último `owner` ativo não pode ser removido, rebaixado nem sair.
- Essas três regras valem na API **e** no banco (gatilho `organization_members_protect_owner`, DATABASE_DESIGN.md seção 3.5), para que um erro na API não consiga violá-las.
- **`viewer` tem acesso mínimo a dados pessoais:** vê o currículo e o resumo profissional das candidaturas, mas **não** vê e-mail nem telefone (`applications.view_contact`) e não baixa anexos (`documents.download`). O contato fica numa coluna sem privilégio de leitura para a aplicação, liberada só pela função que exige a permissão.
- Papéis personalizados (Fase 7, plano Business) são combinações do catálogo acima; nunca criam permissões novas.
- Um membro não pode conceder a outro uma permissão que ele mesmo não tem.

## 5. Permissões pessoais (candidato)

O candidato tem controle total sobre os próprios dados: perfil, documentos, currículos, candidaturas, conversas, preferências, consentimentos, exportação e exclusão. Ele **não** pode:

- Ver avaliações internas, notas de entrevista, compatibilidade calculada para a empresa ou nomes dos avaliadores.
- Alterar o conteúdo de uma candidatura depois de enviada (só retirar).
- Enviar mensagem a uma empresa sem candidatura ativa (RN-MSG-01).

O que a empresa vê do candidato:

| Situação | O que a empresa vê |
| --- | --- |
| Candidatura enviada | O `candidate_snapshot`, o currículo escolhido, respostas de triagem e as cópias dos anexos enviados; contato só para quem tem `applications.view_contact` |
| Banco de talentos (perfil `visible_to_companies`) | Título, resumo, competências, experiências e formação. **Sem** contato, sem documentos, até o candidato aceitar um convite ou se candidatar |
| Nenhuma das duas | Nada |

## 6. Permissões de plataforma

| Ação | support | admin |
| --- | :-: | :-: |
| Ver lista de usuários e empresas (dados de cadastro) | ✔ | ✔ |
| Ver indicadores, filas, erros, importações, consumo de IA | ✔ | ✔ |
| Suspender usuário ou empresa | | ✔ |
| Aprovar ou rejeitar verificação de empresa | | ✔ |
| Editar planos, preços e limites | | ✔ |
| Ver assinaturas e pagamentos | ✔ (sem dados de cobrança) | ✔ |
| Ativar e desativar fontes de vagas | | ✔ |
| **Acessar documento ou dado privado de usuário** | | ✔ com justificativa obrigatória (mínimo 20 caracteres), concessão em `admin_access_grants` de no máximo 30 minutos, auditada e visível ao titular no histórico de acessos |
| Ler a trilha de auditoria | | ✔ |
| Consultar `access_logs` (Marco Civil) | | ✔ só por função, com justificativa (ex.: ordem judicial) |
| Impersonar usuário | Não existe no MVP |

MFA obrigatório para qualquer `platform_role` diferente de `none`.

O papel de plataforma é **lido da tabela `users` pelo banco** (`app_platform_role()`), nunca de uma variável enviada pela aplicação. Uma variável forjada não concede acesso de administrador (testado no protótipo, T15b).

## 7. Implementação

```python
@router.patch("/orgs/{org_id}/applications/{application_id}/stage")
async def move_application(
    org_id: UUID,
    application_id: UUID,
    body: MoveStageIn,
    ctx: OrgContext = Depends(require_org_permission("applications.move")),
):
    ...
```

- `require_org_permission` carrega o membro ativo (com cache de 60 s no Key Value, invalidado em qualquer mudança de papel ou status), confere a permissão e, para permissões ◐, confere a atribuição à vaga dentro do service.
- Recurso de outra organização ou inexistente retorna **404**, nunca 403, para não revelar existência.
- Falta de permissão dentro da própria organização retorna **403** com a chave da permissão ausente.
- Toda negação é registrada em log de segurança; negações repetidas geram alerta.

## 8. Testes obrigatórios

Situação: os testes marcados ✅ foram comprovados no protótipo de RLS (`docs/prototypes/`); todos precisam ser reimplementados no pytest da fase indicada.

0. ✅ Isolamento na camada do banco para organização, membro removido, contexto forjado e papel de plataforma forjado (T05, T06, T07, T15b). Repetir no pytest na Fase 1.
1. Matriz completa: para cada endpoint de organização e cada papel de sistema, o resultado esperado (permitido, 403, 404) é testado automaticamente a partir de uma tabela declarativa.
2. Membro removido ou suspenso perde acesso na requisição seguinte.
3. Recrutador com `assigned_jobs` não vê candidaturas de vagas não atribuídas.
4. Usuário de outra organização recebe 404 em todos os recursos.
5. Escalada: membro tentando alterar o próprio papel ou conceder permissão que não tem recebe 403.
6. `admin` tentando rebaixar, remover ou transferir o `owner` recebe 403 na API **e** é recusado pelo gatilho do banco (Fase 2).
7. `viewer` não recebe e-mail e telefone em nenhuma resposta da API e a função `application_contact` recusa (Fase 5).
8. Auditoria: membro com `org.audit.view` lê só a própria organização; sem a permissão, nada (✅ T14 no protótipo; repetir na Fase 2).
