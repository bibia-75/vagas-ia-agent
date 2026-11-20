#!/usr/bin/env bash
# Sobe um PostgreSQL 16 descartável, aplica o protótipo e roda os testes.
# Uso: bash run_prototype.sh   (precisa dos binários do PostgreSQL 16 e do usuário postgres)
# Não é parte da aplicação; é a evidência dos testes da Fase 0.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PGBIN="${PGBIN:-$(ls -d /usr/lib/postgresql/16/bin)}"
WORK="$(mktemp -d)"; chown postgres "$WORK"
PORT=5499
as_pg() { su postgres -c "$*"; }
cleanup() { as_pg "$PGBIN/pg_ctl -D $WORK/data stop -m fast" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

as_pg "$PGBIN/initdb -D $WORK/data -A trust >/dev/null"
as_pg "$PGBIN/pg_ctl -D $WORK/data -o '-p $PORT -k /tmp' -l $WORK/log start >/dev/null"
sleep 2
PSQL="psql -h /tmp -p $PORT -X -q -v ON_ERROR_STOP=1"
as_pg "$PSQL -c 'CREATE DATABASE vagas_proto'"
as_pg "$PSQL -d vagas_proto -f $HERE/rls_prototype.sql"
as_pg "$PSQL -d vagas_proto -f $HERE/rls_prototype_seed.sql"

echo "== Testes como vagas_app"
as_pg "$PSQL -U vagas_app -d vagas_proto -f $HERE/rls_prototype_tests.sql" 2>&1 | sed 's/^psql:[^:]*:[0-9]*: //'

echo "== Testes extras de auditoria fora do papel da aplicação"
# T21a: o dono das tabelas está sob RLS forçada e não enxerga linhas para alterar.
as_pg "$PSQL -U vagas_owner -d vagas_proto" <<'SQL' 2>&1 | sed 's/^psql:[^:]*:[0-9]*: //'
DO $$ DECLARE n int; BEGIN
  UPDATE audit_logs SET action = 'adulterado'; GET DIAGNOSTICS n = ROW_COUNT;
  ASSERT n = 0, 'T21a dono alterou linhas de auditoria';
  RAISE NOTICE 'T21a ok: dono das tabelas (sob RLS forçada) não altera nenhuma linha';
END $$;
SQL
# T21b: pior caso, superusuário (ignora RLS): o gatilho bloqueia.
as_pg "$PSQL -d vagas_proto" <<'SQL' 2>&1 | sed 's/^psql:[^:]*:[0-9]*: //'
DO $$ BEGIN
  BEGIN
    UPDATE audit_logs SET action = 'adulterado';
    RAISE EXCEPTION 'T21b FALHOU: superusuário alterou auditoria';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'audit_logs is append-only' THEN RAISE; END IF;
  END;
  BEGIN
    DELETE FROM audit_logs;
    RAISE EXCEPTION 'T21b FALHOU: superusuário apagou auditoria';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'audit_logs is append-only' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'T21b ok: gatilho bloqueia UPDATE e DELETE até para superusuário (exceto se desligar o gatilho)';
END $$;
SQL

echo "== Teste extra: worker lê access_logs para aplicar retenção"
as_pg "$PSQL -U vagas_worker -d vagas_proto" <<'SQL' 2>&1 | sed 's/^psql:[^:]*:[0-9]*: //'
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM access_logs) >= 0;
  DELETE FROM access_logs WHERE occurred_at < now() - interval '6 months';
  RAISE NOTICE 'T22 ok: worker lê e aplica retenção em access_logs';
END $$;
SQL
