#!/usr/bin/env bash
# Deploy PEGASUS database (Oracle XE w Dockerze)
# Uzycie: ./setup.sh [--reset] [--skip-data]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$ROOT/.env"
CONTAINER="pegasus-db"
ORACLE_SVC="XEPDB1"
RESET=0
SKIP_DATA=0

for arg in "$@"; do
  case $arg in
    --reset)     RESET=1 ;;
    --skip-data) SKIP_DATA=1 ;;
  esac
done

step() { echo ""; echo -e "\033[0;36m[$1] $2\033[0m"; }
ok()   { echo -e "    \033[0;32mOK: $1\033[0m"; }
fail() { echo -e "    \033[0;31mBLAD: $1\033[0m"; exit 1; }
info() { echo -e "    \033[0;90m$1\033[0m"; }

run_sql() {
  local conn="$1" sql="$2"
  local tmp; tmp=$(mktemp /tmp/pegasus_XXXXXX.sql)
  printf '%s' "$sql" > "$tmp"
  docker cp "$tmp" "${CONTAINER}:/tmp/_run.sql"
  docker exec -u oracle "$CONTAINER" sqlplus -L "$conn" "@/tmp/_run.sql"
  local ec=$?
  rm -f "$tmp"
  return $ec
}

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   PEGASUS  –  One-Click Database Setup   ║"
echo "╚══════════════════════════════════════════╝"

# ─────────────────────────────────────────────
step "1/6" "Sprawdzam Docker"
# ─────────────────────────────────────────────
command -v docker &>/dev/null || fail "Docker nie jest zainstalowany. Pobierz: https://www.docker.com/products/docker-desktop/"
docker info &>/dev/null            || fail "Docker nie jest uruchomiony."
ok "Docker uruchomiony"

# ─────────────────────────────────────────────
step "2/6" "Konfiguracja .env"
# ─────────────────────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
  ORACLE_PWD="$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 18)1a"
  PEGASUS_PWD="$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 18)2b"
  printf 'ORACLE_PASSWORD=%s\nPEGASUS_PASSWORD=%s\n' "$ORACLE_PWD" "$PEGASUS_PWD" > "$ENV_FILE"
  ok "Plik .env wygenerowany z losowymi haslami"
else
  ok "Plik .env istnieje – uzywam istniejacych hasel"
fi

ORACLE_PWD=$(grep "^ORACLE_PASSWORD="  "$ENV_FILE" | cut -d= -f2-)
PEGASUS_PWD=$(grep "^PEGASUS_PASSWORD=" "$ENV_FILE" | cut -d= -f2-)
[ -n "$ORACLE_PWD"  ] || fail "Brak ORACLE_PASSWORD w .env"
[ -n "$PEGASUS_PWD" ] || fail "Brak PEGASUS_PASSWORD w .env"

# ─────────────────────────────────────────────
step "3/6" "Uruchamiam Oracle XE (Docker)"
# ─────────────────────────────────────────────
cd "$ROOT"
docker compose up -d 2>&1 | while IFS= read -r line; do info "$line"; done
ok "Kontener $CONTAINER uruchomiony"

# ─────────────────────────────────────────────
step "4/6" "Czekam na gotowos Oracle XE (max 5 min)"
# ─────────────────────────────────────────────
DEADLINE=$(( $(date +%s) + 300 ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if docker logs "$CONTAINER" 2>&1 | grep -q "DATABASE IS READY TO USE"; then
    ok "Oracle XE GOTOWY"; break
  fi
  info "... inicjalizacja w toku"
  sleep 10
done
docker logs "$CONTAINER" 2>&1 | grep -q "DATABASE IS READY TO USE" || {
  docker logs "$CONTAINER" --tail 30; fail "Oracle XE nie uruchomil sie w ciagu 5 minut"
}

# ─────────────────────────────────────────────
step "5/6" "Tworze schemat PEGASUS"
# ─────────────────────────────────────────────
CREATE_USER_SQL="SET SERVEROUTPUT ON
DECLARE
    v_exists NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_exists FROM dba_users WHERE username = 'PEGASUS';
    IF v_exists > 0 THEN
        EXECUTE IMMEDIATE 'DROP USER PEGASUS CASCADE';
        DBMS_OUTPUT.PUT_LINE('Stary schemat PEGASUS usunieto.');
    END IF;
END;
/
CREATE USER PEGASUS IDENTIFIED BY \"$PEGASUS_PWD\";
GRANT CONNECT, RESOURCE, UNLIMITED TABLESPACE TO PEGASUS;
GRANT CREATE VIEW, CREATE PROCEDURE, CREATE SEQUENCE, CREATE TABLE, CREATE SESSION TO PEGASUS;
PROMPT Uzytkownik PEGASUS gotowy.
EXIT;"

run_sql "sys/${ORACLE_PWD}@localhost:1521/${ORACLE_SVC} as sysdba" "$CREATE_USER_SQL"
ok "Uzytkownik PEGASUS utworzony"

# ─────────────────────────────────────────────
step "6/6" "Laduje skrypty SQL"
# ─────────────────────────────────────────────
if [ "$SKIP_DATA" -eq 1 ]; then
  SCRIPTS="@/sql/01_create_tables.sql"
else
  SCRIPTS="@/sql/01_create_tables.sql
@/sql/02_insert_test_data.sql
@/sql/03_views_and_procedures.sql
@/sql/04_demo_data.sql"
fi

MASTER_SQL="CONNECT PEGASUS/\"$PEGASUS_PWD\"@localhost:1521/${ORACLE_SVC}
SET SQLBLANKLINES ON
$SCRIPTS
EXIT;"

run_sql "sys/${ORACLE_PWD}@localhost:1521/${ORACLE_SVC} as sysdba" "$MASTER_SQL"
ok "Skrypty SQL zaladowane"

# ─────────────────────────────────────────────
# Weryfikacja
# ─────────────────────────────────────────────
VERIFY_SQL="ALTER SESSION SET CONTAINER = ${ORACLE_SVC};
SELECT object_type, COUNT(*) cnt FROM dba_objects WHERE owner='PEGASUS' GROUP BY object_type ORDER BY 1;
SELECT object_name, status FROM dba_objects WHERE owner='PEGASUS' AND object_type='PROCEDURE';
EXIT;"

echo ""
run_sql "/ as sysdba" "$VERIFY_SQL"

# ─────────────────────────────────────────────
PORT=$(grep '"[0-9]*:1521"' "$ROOT/docker-compose.yml" | grep -o '[0-9]*:1521' | cut -d: -f1)

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║            GOTOWE!                       ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Dane polaczenia (SQL Developer / DBeaver):"
echo "    Host:         localhost"
echo "    Port:         $PORT"
echo "    Service name: $ORACLE_SVC"
echo "    Uzytkownik:   PEGASUS"
echo "    Haslo:        (patrz plik .env)"
echo ""
echo "  Zatrzymanie:  docker compose down"
echo "  Pelny reset:  docker compose down -v"
