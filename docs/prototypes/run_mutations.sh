#!/usr/bin/env bash
# Testes de mutação do protótipo de RLS: aplica um erro proposital por vez numa
# cópia descartável dos arquivos e confere se os testes detectam o erro.
# Uso: bash run_mutations.sh   (mesmos requisitos de run_prototype.sh)
# Não é parte da aplicação; é a evidência de que os testes pegam falhas reais.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RESULTS=()
FAILED=0

# mutate <id> <descrição> <esperado: detect|pass> <texto esperado na saída> <arquivo> <antigo> <novo> [<arquivo2> <antigo2> <novo2>]
mutate() {
  local id="$1" desc="$2" expect="$3" needle="$4"; shift 4
  local work; work="$(mktemp -d)"; chmod 755 "$work"   # o usuário postgres precisa ler os arquivos
  cp "$HERE"/rls_prototype*.sql "$HERE"/run_prototype.sh "$work"/; chmod 644 "$work"/*
  while [ "$#" -ge 3 ]; do
    python3 -I - "$work/$1" "$2" "$3" <<'PY' || { echo "ERRO: trecho da mutação não encontrado"; exit 2; }
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path, encoding="utf-8").read()
if s.count(old) != 1:
    sys.exit(1)
open(path, "w", encoding="utf-8").write(s.replace(old, new))
PY
    shift 3
  done
  local out rc
  out="$(bash "$work/run_prototype.sh" 2>&1)"; rc=$?
  rm -rf "$work"
  local outcome
  if [ "$expect" = "detect" ]; then
    if [ $rc -ne 0 ] && grep -qF "$needle" <<<"$out"; then outcome="DETECTADA (como esperado)"; else outcome="NÃO DETECTADA (FALHA DO TESTE)"; FAILED=1; fi
  else
    if [ $rc -eq 0 ] && grep -qF "$needle" <<<"$out"; then outcome="TESTES PASSARAM (como esperado)"; else outcome="RESULTADO INESPERADO"; FAILED=1; fi
  fi
  RESULTS+=("$id | $desc | $outcome")
  echo "== $id: $desc -> $outcome"
  grep -E "FALHOU|ERROR|invalid input" <<<"$out" | head -2 | sed 's/^/   /'
  case "$outcome" in *FALHA*|*INESPERADO*) head -8 <<<"$out" | sed 's/^/   | /';; esac
}

mutate M1 "Cadastro antigo: devolve o id mesmo no e-mail duplicado" detect "ERROR:  T13 duplicado devolveu id" \
  rls_prototype.sql $'  RETURNING id INTO v_id;\n  RETURN v_id;' $'  RETURNING id INTO v_id;\n  RETURN p_id;'

mutate M2 "Suspensão sem exigir administrador" detect "ERROR:  T23f FALHOU" \
  rls_prototype.sql "IF v_admin IS NULL OR public.app_platform_role() <> 'admin' THEN" "IF v_admin IS NULL THEN"

mutate M3 "Exclusão de conta sem a regra do único owner" detect "ERROR:  T23c único owner" \
  rls_prototype.sql "    RETURN 'blocked_sole_owner';" "    NULL;"

mutate M4 "Aplicação com UPDATE em todas as colunas de users" detect "ERROR:  T23a FALHOU" \
  rls_prototype.sql "GRANT UPDATE (full_name, password_hash) ON users TO vagas_app;" "GRANT UPDATE ON users TO vagas_app;"

mutate M5 "Login com tabela sem esquema e search_path SEM pg_temp por último (T19 retirado para isolar o T24)" detect "ERROR:  T24 FALHOU" \
  rls_prototype.sql $'RETURNS TABLE (user_id uuid, password_hash text, status text)\nLANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp' $'RETURNS TABLE (user_id uuid, password_hash text, status text)\nLANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public' \
  rls_prototype.sql "FROM public.users u WHERE u.email = lower(p_email);" "FROM users u WHERE u.email = lower(p_email);" \
  rls_prototype_tests.sql "-- T19: toda função SECURITY DEFINER" "\\if false
-- T19: toda função SECURITY DEFINER" \
  rls_prototype_tests.sql "-- T20: visitante" "\\endif
-- T20: visitante"

mutate M6 "Controle: tabela sem esquema MAS com pg_temp por último (T19 retirado)" pass "TODOS OS TESTES PASSARAM" \
  rls_prototype.sql "FROM public.users u WHERE u.email = lower(p_email);" "FROM users u WHERE u.email = lower(p_email);" \
  rls_prototype_tests.sql "-- T19: toda função SECURITY DEFINER" "\\if false
-- T19: toda função SECURITY DEFINER" \
  rls_prototype_tests.sql "-- T20: visitante" "\\endif
-- T20: visitante"

mutate M7 "Função de contexto sem nullif" detect "ERROR:  invalid input syntax for type uuid" \
  rls_prototype.sql "SELECT nullif(current_setting('app.user_id', true), '')::uuid" "SELECT current_setting('app.user_id', true)::uuid"

mutate M8 "Candidatura sem exigir que seja em nome próprio" detect "ERROR:  T08 FALHOU" \
  rls_prototype.sql $'    candidate_user_id = app_current_user_id()\n    AND status = \'submitted\'' "    status = 'submitted'"

mutate M9 "Permissão sem amarrar à organização do contexto" detect "ERROR:  T06" \
  rls_prototype.sql $'        AND p_org = public.app_current_org_id()\n' ""

echo
echo "== Resumo"
printf '%s\n' "${RESULTS[@]}"
exit $FAILED
