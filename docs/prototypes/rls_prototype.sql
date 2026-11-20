-- Vagas IA: protótipo de RLS da Fase 0
--
-- ATENÇÃO: isto NÃO é migração e NÃO é código de produção.
-- Serve para comprovar, num PostgreSQL 16 real, que o desenho de
-- DATABASE_DESIGN.md (seção 4) funciona. As tabelas têm só as colunas
-- necessárias ao teste. A implementação real (Fase 1) usa Alembic e o
-- modelo completo, e deve repetir estes testes.
--
-- Executar como superusuário num banco vazio:
--   psql -v ON_ERROR_STOP=1 -f rls_prototype.sql
-- Depois rodar rls_prototype_tests.sql conectado como vagas_app.

-- ---------------------------------------------------------------
-- 1. Papéis
-- ---------------------------------------------------------------
CREATE ROLE vagas_owner  LOGIN NOSUPERUSER NOBYPASSRLS;      -- migrações
CREATE ROLE vagas_app    LOGIN NOSUPERUSER NOBYPASSRLS;      -- API
CREATE ROLE vagas_worker LOGIN NOSUPERUSER NOBYPASSRLS;      -- tarefas de sistema
CREATE ROLE vagas_auth_definer NOLOGIN NOSUPERUSER NOBYPASSRLS; -- dono das funções de autenticação
CREATE ROLE vagas_ctx_definer  NOLOGIN NOSUPERUSER NOBYPASSRLS; -- dono das funções de contexto

GRANT CREATE ON SCHEMA public TO vagas_owner;
SET ROLE vagas_owner;

-- ---------------------------------------------------------------
-- 2. Tabelas mínimas
-- ---------------------------------------------------------------
CREATE TABLE users (
  id uuid PRIMARY KEY,
  email text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  full_name text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  platform_role text NOT NULL DEFAULT 'none'
);
CREATE TABLE user_sessions (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash bytea NOT NULL UNIQUE,
  absolute_expires_at timestamptz NOT NULL,
  revoked_at timestamptz
);
CREATE TABLE organizations (
  id uuid PRIMARY KEY,
  name text NOT NULL,
  status text NOT NULL DEFAULT 'active'
);
CREATE TABLE role_permissions (
  role_key text NOT NULL,
  permission_key text NOT NULL,
  PRIMARY KEY (role_key, permission_key)
);
CREATE TABLE organization_members (
  id uuid PRIMARY KEY,
  organization_id uuid NOT NULL REFERENCES organizations(id),
  user_id uuid NOT NULL REFERENCES users(id),
  role_key text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  UNIQUE (organization_id, user_id)
);
CREATE TABLE documents (
  id uuid PRIMARY KEY,
  owner_user_id uuid REFERENCES users(id),
  organization_id uuid REFERENCES organizations(id),
  original_filename text NOT NULL,
  CHECK ((owner_user_id IS NULL) <> (organization_id IS NULL))
);
CREATE TABLE job_postings (
  id uuid PRIMARY KEY,
  organization_id uuid NOT NULL REFERENCES organizations(id),
  title text NOT NULL,
  status text NOT NULL DEFAULT 'draft'
);
CREATE TABLE applications (
  id uuid PRIMARY KEY,
  job_posting_id uuid NOT NULL REFERENCES job_postings(id),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  candidate_user_id uuid REFERENCES users(id),
  status text NOT NULL DEFAULT 'submitted',
  UNIQUE (job_posting_id, candidate_user_id)
);
CREATE TABLE application_attachments (
  id uuid PRIMARY KEY,
  application_id uuid NOT NULL REFERENCES applications(id),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  storage_key text NOT NULL
);
CREATE TABLE interview_schedules (
  id uuid PRIMARY KEY,
  application_id uuid NOT NULL REFERENCES applications(id),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  notes_internal text
);
CREATE TABLE admin_access_grants (
  id uuid PRIMARY KEY,
  admin_user_id uuid NOT NULL REFERENCES users(id),
  target_user_id uuid NOT NULL REFERENCES users(id),
  justification text NOT NULL CHECK (length(justification) >= 20),
  expires_at timestamptz NOT NULL
);
CREATE TABLE audit_logs (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  actor_user_id uuid,
  organization_id uuid,
  subject_user_id uuid,
  visible_to_subject boolean NOT NULL DEFAULT false,
  action text NOT NULL
);
CREATE TABLE access_logs (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  user_id uuid,
  ip_address inet NOT NULL,
  event text NOT NULL
);

-- ---------------------------------------------------------------
-- 3. Funções de contexto (sempre nullif: valor vazio vira NULL)
-- ---------------------------------------------------------------
CREATE FUNCTION app_current_user_id() RETURNS uuid
LANGUAGE sql STABLE SET search_path = pg_catalog
AS $$ SELECT nullif(current_setting('app.user_id', true), '')::uuid $$;

CREATE FUNCTION app_current_org_id() RETURNS uuid
LANGUAGE sql STABLE SET search_path = pg_catalog
AS $$ SELECT nullif(current_setting('app.org_id', true), '')::uuid $$;

RESET ROLE;
-- Funções SECURITY DEFINER pertencem a papéis sem login e com o mínimo de privilégio.
GRANT USAGE ON SCHEMA public TO vagas_ctx_definer, vagas_auth_definer;
GRANT SELECT ON organization_members, role_permissions, users, admin_access_grants TO vagas_ctx_definer;
GRANT SELECT, INSERT ON users TO vagas_auth_definer;
GRANT SELECT ON user_sessions TO vagas_auth_definer;
SET ROLE vagas_owner;

-- Papel de plataforma lido do BANCO (nunca de variável enviada pela aplicação).
CREATE FUNCTION app_platform_role() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$ SELECT coalesce((SELECT u.platform_role FROM public.users u
                       WHERE u.id = public.app_current_user_id() AND u.status = 'active'), 'none') $$;

CREATE FUNCTION app_is_active_member(p_org uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$ SELECT p_org IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.organization_members m
        WHERE m.organization_id = p_org
          AND m.user_id = public.app_current_user_id()
          AND m.status = 'active') $$;

-- Membro ativo, organização do contexto atual e permissão do papel.
CREATE FUNCTION app_has_org_permission(p_org uuid, p_perm text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$ SELECT p_org IS NOT NULL
        AND p_org = public.app_current_org_id()
        AND p_perm ~ '^[a-z_]+(\.[a-z_]+)+$'
        AND EXISTS (
          SELECT 1 FROM public.organization_members m
          JOIN public.role_permissions rp ON rp.role_key = m.role_key
          WHERE m.organization_id = p_org
            AND m.user_id = public.app_current_user_id()
            AND m.status = 'active'
            AND rp.permission_key = p_perm) $$;

CREATE FUNCTION app_admin_can_access_user(p_target uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$ SELECT public.app_platform_role() = 'admin' AND EXISTS (
        SELECT 1 FROM public.admin_access_grants g
        WHERE g.admin_user_id = public.app_current_user_id()
          AND g.target_user_id = p_target
          AND g.expires_at > now()) $$;

-- Diretório da equipe: só nome e e-mail dos colegas, só para membro ativo.
CREATE FUNCTION org_member_directory(p_org uuid)
RETURNS TABLE (user_id uuid, full_name text, role_key text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$ SELECT u.id, u.full_name, m.role_key
      FROM public.organization_members m JOIN public.users u ON u.id = m.user_id
      WHERE m.organization_id = p_org AND m.status = 'active'
        AND public.app_is_active_member(p_org) $$;

RESET ROLE;
ALTER FUNCTION app_platform_role() OWNER TO vagas_ctx_definer;
ALTER FUNCTION app_is_active_member(uuid) OWNER TO vagas_ctx_definer;
ALTER FUNCTION app_has_org_permission(uuid, text) OWNER TO vagas_ctx_definer;
ALTER FUNCTION app_admin_can_access_user(uuid) OWNER TO vagas_ctx_definer;
ALTER FUNCTION org_member_directory(uuid) OWNER TO vagas_ctx_definer;
GRANT EXECUTE ON FUNCTION app_current_user_id(), app_current_org_id() TO vagas_ctx_definer;

-- ---------------------------------------------------------------
-- 4. Funções de autenticação (antes de existir contexto de usuário)
-- ---------------------------------------------------------------
SET ROLE vagas_owner;
CREATE FUNCTION auth_lookup_login(p_email text)
RETURNS TABLE (user_id uuid, password_hash text, status text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  IF p_email IS NULL OR length(p_email) > 254 OR p_email !~ '^[^@\s]+@[^@\s]+$' THEN
    RETURN;  -- entrada inválida: nenhum resultado, sem erro revelador
  END IF;
  RETURN QUERY SELECT u.id, u.password_hash, u.status
               FROM public.users u WHERE u.email = lower(p_email);
END $$;

CREATE FUNCTION auth_resolve_session(p_token_hash bytea)
RETURNS TABLE (session_id uuid, user_id uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  IF p_token_hash IS NULL OR length(p_token_hash) <> 32 THEN
    RETURN;
  END IF;
  RETURN QUERY SELECT s.id, s.user_id
               FROM public.user_sessions s JOIN public.users u ON u.id = s.user_id
               WHERE s.token_hash = p_token_hash
                 AND s.revoked_at IS NULL
                 AND s.absolute_expires_at > now()
                 AND u.status = 'active';
END $$;

CREATE FUNCTION auth_register_user(p_id uuid, p_email text, p_password_hash text, p_full_name text)
RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  IF p_email !~ '^[^@\s]+@[^@\s]+$' OR length(p_email) > 254
     OR p_password_hash !~ '^\$argon2id\$' OR length(trim(p_full_name)) < 2 THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.users (id, email, password_hash, full_name)
  VALUES (p_id, lower(p_email), p_password_hash, trim(p_full_name))
  ON CONFLICT (email) DO NOTHING;
  RETURN p_id;
END $$;
RESET ROLE;
ALTER FUNCTION auth_lookup_login(text) OWNER TO vagas_auth_definer;
ALTER FUNCTION auth_resolve_session(bytea) OWNER TO vagas_auth_definer;
ALTER FUNCTION auth_register_user(uuid, text, text, text) OWNER TO vagas_auth_definer;

-- ---------------------------------------------------------------
-- 5. Ações do candidato que mudam só um campo (sem UPDATE direto)
-- ---------------------------------------------------------------
GRANT SELECT, UPDATE ON applications TO vagas_ctx_definer;
SET ROLE vagas_owner;
CREATE FUNCTION candidate_withdraw_application(p_application uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE v_count int;
BEGIN
  UPDATE public.applications SET status = 'withdrawn'
  WHERE id = p_application
    AND candidate_user_id = public.app_current_user_id()
    AND status NOT IN ('hired', 'withdrawn');
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count = 1;
END $$;
RESET ROLE;
ALTER FUNCTION candidate_withdraw_application(uuid) OWNER TO vagas_ctx_definer;

-- Ninguém além dos papéis certos executa funções privilegiadas.
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app_current_user_id(), app_current_org_id(), app_platform_role(),
  app_is_active_member(uuid), app_has_org_permission(uuid, text), app_admin_can_access_user(uuid),
  org_member_directory(uuid), auth_lookup_login(text), auth_resolve_session(bytea),
  auth_register_user(uuid, text, text, text), candidate_withdraw_application(uuid)
  TO vagas_app;
GRANT EXECUTE ON FUNCTION app_current_user_id(), app_current_org_id() TO vagas_worker;

-- ---------------------------------------------------------------
-- 6. Privilégios de tabela
-- ---------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO vagas_app, vagas_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON users, user_sessions, organizations, organization_members,
  documents, job_postings, applications, application_attachments, interview_schedules,
  admin_access_grants TO vagas_app;
GRANT SELECT ON role_permissions TO vagas_app;
GRANT SELECT, INSERT ON audit_logs TO vagas_app;          -- sem UPDATE/DELETE
GRANT INSERT ON access_logs TO vagas_app;                 -- só gravação
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO vagas_app;
GRANT SELECT, DELETE ON access_logs TO vagas_worker;      -- retenção
GRANT SELECT, UPDATE ON job_postings TO vagas_worker;     -- expiração de vagas

-- Bloqueio adicional: nem o dono das tabelas altera auditoria.
SET ROLE vagas_owner;
CREATE FUNCTION audit_logs_block_change() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog
AS $$ BEGIN RAISE EXCEPTION 'audit_logs is append-only'; END $$;
CREATE TRIGGER audit_logs_append_only BEFORE UPDATE OR DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION audit_logs_block_change();

-- ---------------------------------------------------------------
-- 7. RLS
-- ---------------------------------------------------------------
ALTER TABLE users ENABLE ROW LEVEL SECURITY;               ALTER TABLE users FORCE ROW LEVEL SECURITY;
ALTER TABLE user_sessions ENABLE ROW LEVEL SECURITY;       ALTER TABLE user_sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;       ALTER TABLE organizations FORCE ROW LEVEL SECURITY;
ALTER TABLE organization_members ENABLE ROW LEVEL SECURITY; ALTER TABLE organization_members FORCE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;           ALTER TABLE documents FORCE ROW LEVEL SECURITY;
ALTER TABLE job_postings ENABLE ROW LEVEL SECURITY;        ALTER TABLE job_postings FORCE ROW LEVEL SECURITY;
ALTER TABLE applications ENABLE ROW LEVEL SECURITY;        ALTER TABLE applications FORCE ROW LEVEL SECURITY;
ALTER TABLE application_attachments ENABLE ROW LEVEL SECURITY; ALTER TABLE application_attachments FORCE ROW LEVEL SECURITY;
ALTER TABLE interview_schedules ENABLE ROW LEVEL SECURITY; ALTER TABLE interview_schedules FORCE ROW LEVEL SECURITY;
ALTER TABLE admin_access_grants ENABLE ROW LEVEL SECURITY; ALTER TABLE admin_access_grants FORCE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;          ALTER TABLE audit_logs FORCE ROW LEVEL SECURITY;
ALTER TABLE access_logs ENABLE ROW LEVEL SECURITY;         ALTER TABLE access_logs FORCE ROW LEVEL SECURITY;

-- Papéis donos das funções SECURITY DEFINER: leitura irrestrita SÓ nas tabelas que
-- precisam, por política dirigida ao papel (dispensa BYPASSRLS e superusuário).
-- Sem isso, app_is_active_member() leria organization_members sob a própria política
-- que a chama (recursão infinita).
CREATE POLICY definer_ctx_members ON organization_members FOR SELECT TO vagas_ctx_definer USING (true);
CREATE POLICY definer_ctx_users ON users FOR SELECT TO vagas_ctx_definer USING (true);
CREATE POLICY definer_ctx_grants ON admin_access_grants FOR SELECT TO vagas_ctx_definer USING (true);
CREATE POLICY definer_ctx_apps ON applications FOR ALL TO vagas_ctx_definer USING (true) WITH CHECK (true);
CREATE POLICY definer_auth_users ON users FOR ALL TO vagas_auth_definer USING (true) WITH CHECK (true);
CREATE POLICY definer_auth_sessions ON user_sessions FOR SELECT TO vagas_auth_definer USING (true);

-- users: só a própria linha. Cadastro e login por funções de autenticação.
CREATE POLICY users_self_select ON users FOR SELECT USING (id = app_current_user_id());
CREATE POLICY users_self_update ON users FOR UPDATE
  USING (id = app_current_user_id()) WITH CHECK (id = app_current_user_id());

-- user_sessions: o próprio usuário cria, vê e revoga as próprias sessões.
CREATE POLICY sessions_self ON user_sessions
  USING (user_id = app_current_user_id()) WITH CHECK (user_id = app_current_user_id());

-- organizations: membros leem; público lê empresas ativas (campos públicos via API).
CREATE POLICY orgs_member_select ON organizations FOR SELECT USING (app_is_active_member(id));
CREATE POLICY orgs_public_select ON organizations FOR SELECT USING (status = 'active');
CREATE POLICY orgs_member_update ON organizations FOR UPDATE
  USING (app_has_org_permission(id, 'org.profile.update'))
  WITH CHECK (app_has_org_permission(id, 'org.profile.update'));

-- organization_members: membro vê a equipe; gestão exige permissão.
CREATE POLICY members_select ON organization_members FOR SELECT
  USING (user_id = app_current_user_id() OR app_is_active_member(organization_id));
CREATE POLICY members_manage ON organization_members FOR UPDATE
  USING (app_has_org_permission(organization_id, 'org.members.manage'))
  WITH CHECK (app_has_org_permission(organization_id, 'org.members.manage'));

-- documents: dono pessoal; documento de organização para membros; admin com acesso concedido.
CREATE POLICY documents_owner ON documents
  USING (owner_user_id = app_current_user_id())
  WITH CHECK (owner_user_id = app_current_user_id());
CREATE POLICY documents_org ON documents
  USING (organization_id = app_current_org_id() AND app_is_active_member(organization_id))
  WITH CHECK (organization_id = app_current_org_id() AND app_is_active_member(organization_id));
CREATE POLICY documents_admin_grant ON documents FOR SELECT
  USING (owner_user_id IS NOT NULL AND app_admin_can_access_user(owner_user_id));

-- job_postings: público lê publicadas; organização gerencia as suas; sistema expira.
CREATE POLICY jobs_public_select ON job_postings FOR SELECT USING (status = 'published');
CREATE POLICY jobs_org_select ON job_postings FOR SELECT
  USING (app_has_org_permission(organization_id, 'jobs.view'));
CREATE POLICY jobs_org_insert ON job_postings FOR INSERT
  WITH CHECK (app_has_org_permission(organization_id, 'jobs.create'));
CREATE POLICY jobs_org_update ON job_postings FOR UPDATE
  USING (app_has_org_permission(organization_id, 'jobs.update'))
  WITH CHECK (app_has_org_permission(organization_id, 'jobs.update'));
CREATE POLICY jobs_worker ON job_postings FOR ALL TO vagas_worker USING (true) WITH CHECK (true);

-- applications: candidato lê as suas e cria em vaga publicada; organização trabalha nas suas.
CREATE POLICY apps_candidate_select ON applications FOR SELECT
  USING (candidate_user_id = app_current_user_id());
CREATE POLICY apps_candidate_insert ON applications FOR INSERT
  WITH CHECK (
    candidate_user_id = app_current_user_id()
    AND status = 'submitted'
    AND EXISTS (SELECT 1 FROM job_postings j
                WHERE j.id = job_posting_id
                  AND j.organization_id = applications.organization_id
                  AND j.status = 'published'));
CREATE POLICY apps_org_select ON applications FOR SELECT
  USING (app_has_org_permission(organization_id, 'applications.view'));
CREATE POLICY apps_org_update ON applications FOR UPDATE
  USING (app_has_org_permission(organization_id, 'applications.move'))
  WITH CHECK (app_has_org_permission(organization_id, 'applications.move'));

-- application_attachments: cópia imutável enviada com a candidatura.
CREATE POLICY att_candidate_select ON application_attachments FOR SELECT
  USING (EXISTS (SELECT 1 FROM applications a
                 WHERE a.id = application_id AND a.candidate_user_id = app_current_user_id()));
CREATE POLICY att_candidate_insert ON application_attachments FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM applications a
                      WHERE a.id = application_id
                        AND a.organization_id = application_attachments.organization_id
                        AND a.candidate_user_id = app_current_user_id()
                        AND a.status = 'submitted'));
CREATE POLICY att_org_select ON application_attachments FOR SELECT
  USING (app_has_org_permission(organization_id, 'applications.view'));

-- interview_schedules: organização gerencia; candidato lê as da própria candidatura.
-- (notas internas são omitidas pela API/visão do candidato, não pela RLS)
CREATE POLICY int_org ON interview_schedules
  USING (app_has_org_permission(organization_id, 'interviews.manage'))
  WITH CHECK (app_has_org_permission(organization_id, 'interviews.manage'));
CREATE POLICY int_candidate_select ON interview_schedules FOR SELECT
  USING (EXISTS (SELECT 1 FROM applications a
                 WHERE a.id = application_id AND a.candidate_user_id = app_current_user_id()));

-- admin_access_grants: só administrador cria e vê.
CREATE POLICY grants_admin ON admin_access_grants
  USING (app_platform_role() = 'admin')
  WITH CHECK (app_platform_role() = 'admin' AND admin_user_id = app_current_user_id());

-- audit_logs: inserção pela aplicação; leitura por organização, titular ou admin.
CREATE POLICY audit_insert ON audit_logs FOR INSERT TO vagas_app WITH CHECK (true);
CREATE POLICY audit_org_select ON audit_logs FOR SELECT
  USING (app_has_org_permission(organization_id, 'org.audit.view'));
CREATE POLICY audit_subject_select ON audit_logs FOR SELECT
  USING (visible_to_subject AND subject_user_id = app_current_user_id());
CREATE POLICY audit_admin_select ON audit_logs FOR SELECT
  USING (app_platform_role() = 'admin');

-- access_logs (Marco Civil): aplicação só grava; leitura e retenção só pelo worker.
CREATE POLICY access_insert ON access_logs FOR INSERT TO vagas_app WITH CHECK (true);
CREATE POLICY access_worker ON access_logs FOR ALL TO vagas_worker USING (true) WITH CHECK (true);
RESET ROLE;
