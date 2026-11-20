-- Dados fictícios para os testes do protótipo (executar como superusuário).
-- Usuários: A e B candidatos; R recrutador da org X; O owner da org X;
-- M ex-membro (removido) da org X; S owner da org Y; ADM administrador da plataforma.
INSERT INTO users (id, email, password_hash, full_name, platform_role) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','a@exemplo.invalid','$argon2id$teste','Candidata A','none'),
 ('bbbbbbbb-0000-0000-0000-000000000001','b@exemplo.invalid','$argon2id$teste','Candidato B','none'),
 ('cccccccc-0000-0000-0000-000000000001','r@exemplo.invalid','$argon2id$teste','Recrutador R','none'),
 ('99999999-0000-0000-0000-000000000001','o@exemplo.invalid','$argon2id$teste','Owner O','none'),
 ('ffffffff-0000-0000-0000-000000000001','m@exemplo.invalid','$argon2id$teste','Ex-membro M','none'),
 ('dddddddd-0000-0000-0000-000000000001','s@exemplo.invalid','$argon2id$teste','Owner S','none'),
 ('eeeeeeee-0000-0000-0000-000000000001','adm@exemplo.invalid','$argon2id$teste','Admin','admin');

INSERT INTO organizations (id, name) VALUES
 ('11111111-0000-0000-0000-000000000001','Empresa X'),
 ('22222222-0000-0000-0000-000000000001','Empresa Y');

INSERT INTO role_permissions (role_key, permission_key)
SELECT 'owner', p FROM unnest(ARRAY['org.profile.update','org.members.manage','org.audit.view','jobs.view',
  'jobs.create','jobs.update','applications.view','applications.move','interviews.manage']) p
UNION ALL
SELECT 'recruiter', p FROM unnest(ARRAY['jobs.view','jobs.create','applications.view',
  'applications.move','interviews.manage']) p;

INSERT INTO organization_members (id, organization_id, user_id, role_key, status) VALUES
 ('a0000000-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000001','cccccccc-0000-0000-0000-000000000001','recruiter','active'),
 ('a0000000-0000-0000-0000-000000000002','11111111-0000-0000-0000-000000000001','99999999-0000-0000-0000-000000000001','owner','active'),
 ('a0000000-0000-0000-0000-000000000003','11111111-0000-0000-0000-000000000001','ffffffff-0000-0000-0000-000000000001','recruiter','removed'),
 ('a0000000-0000-0000-0000-000000000004','22222222-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000001','owner','active');

INSERT INTO documents (id, owner_user_id, organization_id, original_filename) VALUES
 ('d0000000-0000-0000-0000-00000000000a','aaaaaaaa-0000-0000-0000-000000000001',NULL,'curriculo-a.pdf'),
 ('d0000000-0000-0000-0000-00000000000b','bbbbbbbb-0000-0000-0000-000000000001',NULL,'curriculo-b.pdf'),
 ('d0000000-0000-0000-0000-00000000000c',NULL,'11111111-0000-0000-0000-000000000001','logo-x.png');

INSERT INTO job_postings (id, organization_id, title, status) VALUES
 ('70000000-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000001','Vaga X publicada','published'),
 ('70000000-0000-0000-0000-000000000002','11111111-0000-0000-0000-000000000001','Vaga X rascunho','draft'),
 ('70000000-0000-0000-0000-000000000003','22222222-0000-0000-0000-000000000001','Vaga Y publicada','published');

-- Candidatura de A na vaga X publicada; de B na vaga Y publicada.
INSERT INTO applications (id, job_posting_id, organization_id, candidate_user_id) VALUES
 ('a1000000-0000-0000-0000-00000000000a','70000000-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001'),
 ('a1000000-0000-0000-0000-00000000000b','70000000-0000-0000-0000-000000000003','22222222-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001');

INSERT INTO application_attachments (id, application_id, organization_id, storage_key) VALUES
 ('a2000000-0000-0000-0000-00000000000a','a1000000-0000-0000-0000-00000000000a','11111111-0000-0000-0000-000000000001','private/orgs/x/app-a/curriculo.pdf');

INSERT INTO interview_schedules (id, application_id, organization_id, notes_internal) VALUES
 ('a3000000-0000-0000-0000-00000000000a','a1000000-0000-0000-0000-00000000000a','11111111-0000-0000-0000-000000000001','nota interna');

INSERT INTO user_sessions (id, user_id, token_hash, absolute_expires_at) VALUES
 ('a4000000-0000-0000-0000-00000000000a','aaaaaaaa-0000-0000-0000-000000000001',sha256('token-da-candidata-a'::bytea), now() + interval '1 day'),
 ('a4000000-0000-0000-0000-00000000000b','bbbbbbbb-0000-0000-0000-000000000001',sha256('token-do-candidato-b'::bytea), now() + interval '1 day');

INSERT INTO audit_logs (actor_user_id, organization_id, subject_user_id, visible_to_subject, action) VALUES
 ('cccccccc-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000001',NULL,false,'job.publish'),
 ('cccccccc-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001',true,'document.download'),
 ('dddddddd-0000-0000-0000-000000000001','22222222-0000-0000-0000-000000000001',NULL,false,'job.publish');

INSERT INTO admin_access_grants (id, admin_user_id, target_user_id, justification, expires_at) VALUES
 ('a5000000-0000-0000-0000-00000000000b','eeeeeeee-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','Atendimento do chamado de suporte 123 a pedido do titular', now() + interval '30 minutes');
