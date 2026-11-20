-- Testes do protótipo de RLS. Executar CONECTADO COMO vagas_app (nunca como superusuário):
--   psql -U vagas_app -v ON_ERROR_STOP=1 -f rls_prototype_tests.sql
-- Cada teste falha com erro (e interrompe o script) se a expectativa não for atendida.
-- IDs: A=aaaaaaaa.. B=bbbbbbbb.. R=cccccccc.. (recrutador X) O=99999999.. (owner X)
--      M=ffffffff.. (removido de X) S=dddddddd.. (owner Y) ADM=eeeeeeee..
--      X=11111111.. Y=22222222..

\set A   '''aaaaaaaa-0000-0000-0000-000000000001'''
\set B   '''bbbbbbbb-0000-0000-0000-000000000001'''
\set R   '''cccccccc-0000-0000-0000-000000000001'''
\set O   '''99999999-0000-0000-0000-000000000001'''
\set M   '''ffffffff-0000-0000-0000-000000000001'''
\set S   '''dddddddd-0000-0000-0000-000000000001'''
\set ADM '''eeeeeeee-0000-0000-0000-000000000001'''
\set X   '''11111111-0000-0000-0000-000000000001'''
\set Y   '''22222222-0000-0000-0000-000000000001'''

-- T01: o papel da aplicação não é superusuário nem ignora RLS
DO $$ BEGIN
  ASSERT (SELECT NOT rolsuper AND NOT rolbypassrls FROM pg_roles WHERE rolname = current_user),
    'T01 papel da aplicação privilegiado';
  RAISE NOTICE 'T01 ok: % sem SUPERUSER e sem BYPASSRLS', current_user;
END $$;

-- T02: contexto vazio após transação anterior não gera erro e não vaza
BEGIN; SELECT set_config('app.user_id', :A, true) \gset
COMMIT;
DO $$ BEGIN
  ASSERT current_setting('app.user_id', true) = '', 'T02 esperado texto vazio (comportamento do PostgreSQL)';
  ASSERT app_current_user_id() IS NULL, 'T02 helper deveria devolver NULL';
  ASSERT (SELECT count(*) FROM documents) = 0, 'T02 sem contexto não pode ver documentos';
  RAISE NOTICE 'T02 ok: valor vazio tratado como NULL, nenhum documento visível';
END $$;

-- T03: usuário A só vê, altera e apaga o que é dele
BEGIN; SELECT set_config('app.user_id', :A, true) \gset
DO $$ DECLARE n int; BEGIN
  ASSERT (SELECT count(*) FROM documents) = 1, 'T03 A deveria ver 1 documento';
  UPDATE documents SET original_filename = 'x' WHERE id = 'd0000000-0000-0000-0000-00000000000b';
  GET DIAGNOSTICS n = ROW_COUNT; ASSERT n = 0, 'T03 A alterou documento de B';
  DELETE FROM documents WHERE id = 'd0000000-0000-0000-0000-00000000000b';
  GET DIAGNOSTICS n = ROW_COUNT; ASSERT n = 0, 'T03 A apagou documento de B';
  RAISE NOTICE 'T03 ok: leitura, alteração e exclusão cruzadas bloqueadas';
END $$;
ROLLBACK;

-- T04: A não cria documento em nome de B
BEGIN; SELECT set_config('app.user_id', :A, true) \gset
DO $$ BEGIN
  BEGIN
    INSERT INTO documents (id, owner_user_id, original_filename)
    VALUES (gen_random_uuid(), 'bbbbbbbb-0000-0000-0000-000000000001', 'falso.pdf');
    RAISE EXCEPTION 'T04 FALHOU: inserção em nome de outro usuário aceita';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'T04 ok: inserção em nome de outro usuário recusada';
  END;
END $$;
ROLLBACK;

-- T05: recrutador R no contexto X vê vagas e candidaturas de X, nada de Y
BEGIN; SELECT set_config('app.user_id', :R, true), set_config('app.org_id', :X, true) \gset
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM job_postings WHERE organization_id = '11111111-0000-0000-0000-000000000001') = 2,
    'T05 R deveria ver as 2 vagas de X (inclusive rascunho)';
  ASSERT (SELECT count(*) FROM job_postings WHERE status = 'draft' AND organization_id = '22222222-0000-0000-0000-000000000001') = 0,
    'T05 R vê rascunho de Y';
  ASSERT (SELECT count(*) FROM applications) = 1, 'T05 R deveria ver só a candidatura de X';
  ASSERT (SELECT count(*) FROM applications WHERE organization_id = '22222222-0000-0000-0000-000000000001') = 0,
    'T05 R vê candidatura de Y';
  RAISE NOTICE 'T05 ok: recrutador isolado na própria organização';
END $$;
ROLLBACK;

-- T06: R forjando o contexto da organização Y não ganha nada
BEGIN; SELECT set_config('app.user_id', :R, true), set_config('app.org_id', :Y, true) \gset
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM applications) = 0, 'T06 contexto forjado expôs candidaturas';
  ASSERT NOT app_has_org_permission('22222222-0000-0000-0000-000000000001', 'applications.view'), 'T06 permissão concedida a não membro';
  ASSERT NOT app_has_org_permission('11111111-0000-0000-0000-000000000001', 'applications.view'),
    'T06 permissão de X não deve valer com contexto Y';
  RAISE NOTICE 'T06 ok: contexto de organização forjado não dá acesso';
END $$;
ROLLBACK;

-- T07: membro removido perde acesso imediatamente
BEGIN; SELECT set_config('app.user_id', :M, true), set_config('app.org_id', :X, true) \gset
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM applications) = 0, 'T07 removido vê candidaturas';
  ASSERT (SELECT count(*) FROM job_postings WHERE status = 'draft') = 0, 'T07 removido vê rascunho';
  RAISE NOTICE 'T07 ok: membro removido sem acesso';
END $$;
ROLLBACK;

-- T08: candidatura só em vaga publicada e só em nome próprio
BEGIN; SELECT set_config('app.user_id', :A, true) \gset
DO $$ BEGIN
  INSERT INTO applications (id, job_posting_id, organization_id, candidate_user_id)
  VALUES (gen_random_uuid(), '70000000-0000-0000-0000-000000000003', '22222222-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001');
  BEGIN
    INSERT INTO applications (id, job_posting_id, organization_id, candidate_user_id)
    VALUES (gen_random_uuid(), '70000000-0000-0000-0000-000000000002', '11111111-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'T08 FALHOU: candidatura em rascunho aceita';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO applications (id, job_posting_id, organization_id, candidate_user_id)
    VALUES (gen_random_uuid(), '70000000-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'T08 FALHOU: candidatura em nome de outro aceita';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO applications (id, job_posting_id, organization_id, candidate_user_id)
    VALUES (gen_random_uuid(), '70000000-0000-0000-0000-000000000003', '11111111-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'T08 FALHOU: organização divergente da vaga aceita';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RAISE NOTICE 'T08 ok: candidatura válida aceita; rascunho, outro candidato e organização trocada recusados';
END $$;
ROLLBACK;

-- T09: candidato vê a própria candidatura e a entrevista dela; outro candidato não
BEGIN; SELECT set_config('app.user_id', :A, true) \gset
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM applications) = 1, 'T09 A deveria ver 1 candidatura';
  ASSERT (SELECT count(*) FROM interview_schedules) = 1, 'T09 A deveria ver a entrevista';
  RAISE NOTICE 'T09a ok: candidata vê candidatura e entrevista próprias';
END $$;
ROLLBACK;
BEGIN; SELECT set_config('app.user_id', :B, true) \gset
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM interview_schedules) = 0, 'T09 B vê entrevista de A';
  ASSERT (SELECT count(*) FROM applications WHERE candidate_user_id <> 'bbbbbbbb-0000-0000-0000-000000000001') = 0, 'T09 B vê candidatura alheia';
  RAISE NOTICE 'T09b ok: outro candidato não vê';
END $$;
ROLLBACK;

-- T10: anexos da candidatura: empresa da vaga e candidato veem; outros não; cofre de A invisível para X
BEGIN; SELECT set_config('app.user_id', :R, true), set_config('app.org_id', :X, true) \gset
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM application_attachments) = 1, 'T10 R deveria ver o anexo';
  ASSERT (SELECT count(*) FROM documents WHERE owner_user_id IS NOT NULL) = 0, 'T10 R vê cofre pessoal de candidato';
  RAISE NOTICE 'T10a ok: empresa vê o anexo enviado, não o cofre do candidato';
END $$;
ROLLBACK;
BEGIN; SELECT set_config('app.user_id', :S, true), set_config('app.org_id', :Y, true) \gset
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM application_attachments) = 0, 'T10 S (org Y) vê anexo de X';
  RAISE NOTICE 'T10b ok: outra empresa não vê o anexo';
END $$;
ROLLBACK;
BEGIN; SELECT set_config('app.user_id', :A, true) \gset
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM application_attachments) = 1, 'T10 A deveria ver o próprio anexo';
  RAISE NOTICE 'T10c ok: candidata vê o próprio anexo';
END $$;
ROLLBACK;

-- T11: login sem contexto: tabela fechada, função de autenticação funciona e valida entrada
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM users) = 0, 'T11 users visível sem contexto';
  ASSERT (SELECT count(*) FROM auth_lookup_login('A@Exemplo.invalid')) = 1, 'T11 login por e-mail falhou';
  ASSERT (SELECT count(*) FROM auth_lookup_login('nao-e-email')) = 0, 'T11 entrada inválida aceita';
  ASSERT (SELECT count(*) FROM auth_lookup_login(repeat('a', 300) || '@x.invalid')) = 0, 'T11 e-mail longo aceito';
  RAISE NOTICE 'T11 ok: login via função, sem expor a tabela users';
END $$;

-- T12: resolução de sessão por hash do token
DO $$ BEGIN
  ASSERT (SELECT user_id FROM auth_resolve_session(sha256('token-da-candidata-a'::bytea)))
         = 'aaaaaaaa-0000-0000-0000-000000000001', 'T12 sessão válida não resolvida';
  ASSERT (SELECT count(*) FROM auth_resolve_session(sha256('token-errado'::bytea))) = 0, 'T12 token errado resolvido';
  ASSERT (SELECT count(*) FROM auth_resolve_session('\x00'::bytea)) = 0, 'T12 hash de tamanho inválido aceito';
  ASSERT (SELECT count(*) FROM user_sessions) = 0, 'T12 sessões visíveis sem contexto';
  RAISE NOTICE 'T12 ok: sessão resolvida só pela função';
END $$;

-- T13: cadastro pela função, com validação
BEGIN;
DO $$ BEGIN
  PERFORM auth_register_user(gen_random_uuid(), 'nova@exemplo.invalid', '$argon2id$v=19$teste', 'Pessoa Nova');
  PERFORM auth_register_user(gen_random_uuid(), 'nova@exemplo.invalid', '$argon2id$v=19$teste', 'Outra');  -- duplicado não falha
  BEGIN
    PERFORM auth_register_user(gen_random_uuid(), 'x@exemplo.invalid', 'senha-em-texto', 'Pessoa');
    RAISE EXCEPTION 'T13 FALHOU: hash que não é Argon2id aceito';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  ASSERT (SELECT count(*) FROM auth_lookup_login('nova@exemplo.invalid')) = 1, 'T13 usuário não criado';
  RAISE NOTICE 'T13 ok: cadastro valida entrada, duplicado silencioso';
END $$;
ROLLBACK;

-- T14: auditoria: grava; não altera nem apaga; leitura por organização, titular e admin
BEGIN; SELECT set_config('app.user_id', :R, true), set_config('app.org_id', :X, true) \gset
DO $$ BEGIN
  INSERT INTO audit_logs (actor_user_id, organization_id, action)
  VALUES ('cccccccc-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001', 'teste.insercao');
  BEGIN
    UPDATE audit_logs SET action = 'adulterado';
    RAISE EXCEPTION 'T14 FALHOU: UPDATE em auditoria permitido';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    DELETE FROM audit_logs;
    RAISE EXCEPTION 'T14 FALHOU: DELETE em auditoria permitido';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  ASSERT (SELECT count(*) FROM audit_logs) = 0, 'T14 recrutador sem org.audit.view leu auditoria';
  RAISE NOTICE 'T14a ok: aplicação grava, não altera, não apaga; sem permissão não lê';
END $$;
ROLLBACK;
BEGIN; SELECT set_config('app.user_id', :O, true), set_config('app.org_id', :X, true) \gset
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM audit_logs) = 2, 'T14 owner X deveria ver 2 registros de X';
  ASSERT (SELECT count(*) FROM audit_logs WHERE organization_id = '22222222-0000-0000-0000-000000000001') = 0, 'T14 owner X vê auditoria de Y';
  RAISE NOTICE 'T14b ok: owner com org.audit.view lê só a própria organização';
END $$;
ROLLBACK;
BEGIN; SELECT set_config('app.user_id', :A, true) \gset
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM audit_logs) = 1, 'T14 titular deveria ver 1 acesso aos seus dados';
  RAISE NOTICE 'T14c ok: titular vê o histórico de acesso aos próprios dados';
END $$;
ROLLBACK;
BEGIN; SELECT set_config('app.user_id', :ADM, true) \gset
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM audit_logs) = 3, 'T14 admin deveria ver tudo';
  RAISE NOTICE 'T14d ok: administrador lê toda a auditoria';
END $$;
ROLLBACK;

-- T15: admin só vê documento privado com concessão vigente; variável forjada não vale
BEGIN; SELECT set_config('app.user_id', :ADM, true) \gset
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM documents WHERE owner_user_id = 'bbbbbbbb-0000-0000-0000-000000000001') = 1, 'T15 admin com concessão não vê';
  ASSERT (SELECT count(*) FROM documents WHERE owner_user_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 0, 'T15 admin sem concessão vê';
  RAISE NOTICE 'T15a ok: acesso administrativo só com concessão';
END $$;
ROLLBACK;
BEGIN; SELECT set_config('app.user_id', :A, true), set_config('app.platform_role', 'admin', true) \gset
DO $$ BEGIN
  ASSERT app_platform_role() = 'none', 'T15 papel de plataforma veio da variável forjada';
  ASSERT (SELECT count(*) FROM audit_logs) = 1, 'T15 variável forjada deu leitura de admin';
  RAISE NOTICE 'T15b ok: papel de plataforma vem do banco, não da variável';
END $$;
ROLLBACK;

-- T16: candidato não muda status direto; retira pela função
BEGIN; SELECT set_config('app.user_id', :A, true) \gset
DO $$ DECLARE n int; BEGIN
  UPDATE applications SET status = 'hired';
  GET DIAGNOSTICS n = ROW_COUNT; ASSERT n = 0, 'T16 candidato alterou o próprio status';
  ASSERT candidate_withdraw_application('a1000000-0000-0000-0000-00000000000a'), 'T16 retirada falhou';
  ASSERT (SELECT status FROM applications WHERE id = 'a1000000-0000-0000-0000-00000000000a') = 'withdrawn', 'T16 status não mudou';
  ASSERT NOT candidate_withdraw_application('a1000000-0000-0000-0000-00000000000b'), 'T16 retirou candidatura alheia';
  RAISE NOTICE 'T16 ok: só a retirada é permitida ao candidato, e só na própria candidatura';
END $$;
ROLLBACK;

-- T17: diretório da equipe
BEGIN; SELECT set_config('app.user_id', :R, true), set_config('app.org_id', :X, true) \gset
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM org_member_directory('11111111-0000-0000-0000-000000000001')) = 2, 'T17 R deveria ver 2 colegas ativos';
  ASSERT (SELECT count(*) FROM org_member_directory('22222222-0000-0000-0000-000000000001')) = 0, 'T17 R vê equipe de Y';
  RAISE NOTICE 'T17a ok: membro vê só a própria equipe ativa';
END $$;
ROLLBACK;
BEGIN; SELECT set_config('app.user_id', :A, true) \gset
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM org_member_directory('11111111-0000-0000-0000-000000000001')) = 0, 'T17 não membro vê equipe';
  RAISE NOTICE 'T17b ok: não membro não vê equipe';
END $$;
ROLLBACK;

-- T18: registros de acesso (Marco Civil): aplicação grava, não lê
DO $$ BEGIN
  INSERT INTO access_logs (user_id, ip_address, event) VALUES (NULL, '203.0.113.10', 'login');
  BEGIN
    PERFORM count(*) FROM access_logs;
    RAISE EXCEPTION 'T18 FALHOU: aplicação leu access_logs';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RAISE NOTICE 'T18 ok: access_logs só gravação para a aplicação';
END $$;

-- T19: toda função SECURITY DEFINER tem search_path fixo e dono sem login
DO $$ BEGIN
  ASSERT NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef
      AND NOT coalesce(array_to_string(p.proconfig, ',') LIKE '%search_path=%', false)),
    'T19 função SECURITY DEFINER sem search_path';
  ASSERT NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_roles r ON r.oid = p.proowner
    WHERE n.nspname = 'public' AND p.prosecdef AND (r.rolcanlogin OR r.rolsuper OR r.rolbypassrls)),
    'T19 função SECURITY DEFINER com dono privilegiado ou com login';
  RAISE NOTICE 'T19 ok: funções privilegiadas com search_path fixo e donos mínimos';
END $$;

-- T20: visitante sem contexto vê só vagas publicadas
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM job_postings) = 2, 'T20 visitante deveria ver 2 vagas publicadas';
  ASSERT (SELECT count(*) FROM job_postings WHERE status <> 'published') = 0, 'T20 visitante vê rascunho';
  RAISE NOTICE 'T20 ok: público vê só vagas publicadas';
END $$;

\echo 'TODOS OS TESTES PASSARAM'
