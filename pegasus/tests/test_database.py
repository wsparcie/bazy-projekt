"""
PEGASUS – testy integracyjne bazy danych
=========================================
Uruchamiane w GitHub Actions i lokalnie:
    pip install oracledb pytest
    pytest pegasus/tests/test_database.py -v

Zmienne srodowiskowe:
    ORACLE_SYS_PASSWORD  – haslo SYS (do tworzenia schematu)
    PEGASUS_PASSWORD     – haslo uzytkownika PEGASUS
    DB_HOST              – (opcja, domyslnie localhost)
    DB_PORT              – (opcja, domyslnie 1521)
    DB_SERVICE           – (opcja, domyslnie XEPDB1)
"""

import os
import re
import pytest
import oracledb

# ─── konfiguracja z env ────────────────────────────────────────────────────────
SYS_PWD  = os.environ["ORACLE_SYS_PASSWORD"]
PEG_PWD  = os.environ["PEGASUS_PASSWORD"]
DB_HOST  = os.environ.get("DB_HOST",    "localhost")
DB_PORT  = int(os.environ.get("DB_PORT", "1521"))
DB_SVC   = os.environ.get("DB_SERVICE", "XEPDB1")
DSN      = f"{DB_HOST}:{DB_PORT}/{DB_SVC}"
SQL_DIR  = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "sql"))

# ─── helpery połączeń ──────────────────────────────────────────────────────────
def sys_conn():
    return oracledb.connect(
        user="sys", password=SYS_PWD, dsn=DSN,
        mode=oracledb.AUTH_MODE_SYSDBA
    )

def pegasus_conn():
    return oracledb.connect(user="PEGASUS", password=PEG_PWD, dsn=DSN)


# ─── executor plików SQL ───────────────────────────────────────────────────────
# Kody błędów Oracle, które są bezpiecznie ignorowane przy ponownym uruchomieniu
_IGNORABLE = {
    955,   # ORA-00955: name already used by existing object
    1,     # ORA-00001: unique constraint violated (duplicate test data)
    1408,  # ORA-01408: such column list already indexed (PK/UK already covers it)
    2261,  # ORA-02261: such unique or primary key already exists
    2264,  # ORA-02264: name already used by existing constraint
}

_SQLPLUS_RE = re.compile(
    r"^\s*(SET\s+|DEFINE\s+|PROMPT\s*|@|SPOOL\s+|CONNECT\s+|EXIT\s*;?\s*$)",
    re.IGNORECASE,
)

def _split_statements(content: str) -> list[str]:
    """
    Dzieli plik SQL na pojedyncze instrukcje.
    - Bloki PL/SQL (CREATE PROCEDURE/FUNCTION/TRIGGER, BEGIN...END) kończą się / na osobnej linii.
    - Zwykle instrukcje SQL kończą się ;
    - Pomija dyrektywy SQL*Plus (tylko poza blokami PL/SQL).
    """
    content = content.replace("\r\n", "\n").replace("\r", "\n")
    statements: list[str] = []
    current: list[str] = []
    in_plsql = False

    PLSQL_START = re.compile(
        r"\b(BEGIN|DECLARE|CREATE\s+OR\s+REPLACE\s+(?:PROCEDURE|FUNCTION|TRIGGER|PACKAGE|TYPE))\b",
        re.IGNORECASE,
    )

    for line in content.split("\n"):
        stripped = line.strip()

        # Pomiń dyrektywy SQL*Plus – ALE TYLKO poza blokami PL/SQL,
        # bo np. "SET STATUS = ..." wewnątrz UPDATE pasuje do wzorca SET\s+
        if not in_plsql and _SQLPLUS_RE.match(stripped):
            continue

        # Terminator bloku PL/SQL
        if stripped == "/":
            stmt = "\n".join(current).strip()
            # Usuń samodzielne linie ";" dodawane przez formater SQL (np. VS Code)
            # po "END SP_name;". Oracle widzi podwójne ";" jako dwa polecenia → INVALID.
            stmt = re.sub(r"(\n[ \t]*;[ \t]*)+$", "", stmt).strip()
            if re.sub(r"--[^\n]*", "", stmt).strip():
                statements.append(stmt)
            current = []
            in_plsql = False
            continue

        current.append(line)

        joined = "\n".join(current)
        if PLSQL_START.search(joined):
            in_plsql = True

        # Zwykła instrukcja SQL kończy się ; (nie jesteśmy w bloku PL/SQL)
        if not in_plsql and stripped.endswith(";"):
            stmt = "\n".join(current).strip().rstrip(";").strip()
            stmt_clean = re.sub(r"--[^\n]*", "", stmt).strip()
            if stmt_clean:
                statements.append(stmt)
            current = []

    return statements


def execute_sql_file(conn, filepath: str) -> None:
    """Wykonuje plik SQL przez oracledb (bez SQL*Plus, bez ograniczeń blank-line)."""
    with open(filepath, encoding="utf-8") as f:
        content = f.read()

    statements = _split_statements(content)
    cursor = conn.cursor()

    for stmt in statements:
        stmt_exec = re.sub(r"--[^\n]*", "", stmt).strip()
        if not stmt_exec:
            continue
        try:
            cursor.execute(stmt_exec)
        except oracledb.DatabaseError as exc:
            (err,) = exc.args
            if err.code not in _IGNORABLE:
                fname = os.path.basename(filepath)
                raise RuntimeError(
                    f"[{fname}] ORA-{err.code:05d}: {err.message}\n"
                    f"Statement: {stmt_exec[:300]}"
                ) from exc

    conn.commit()
    cursor.close()


# ─── SETUP (raz na sesję pytest) ───────────────────────────────────────────────
@pytest.fixture(scope="session", autouse=True)
def setup_database():
    """Tworzy schemat PEGASUS i ładuje wszystkie dane testowe (mock)."""

    # 1. Utwórz / zresetuj schemat PEGASUS
    with sys_conn() as conn:
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM dba_users WHERE username='PEGASUS'")
        if cur.fetchone()[0]:
            cur.execute("DROP USER PEGASUS CASCADE")
        cur.execute(f'CREATE USER PEGASUS IDENTIFIED BY "{PEG_PWD}"')
        for priv in (
            "CONNECT", "RESOURCE", "UNLIMITED TABLESPACE",
            "CREATE VIEW", "CREATE PROCEDURE", "CREATE SEQUENCE",
            "CREATE TABLE", "CREATE SESSION",
        ):
            cur.execute(f"GRANT {priv} TO PEGASUS")
        conn.commit()
        cur.close()

    # 2. Uruchom skrypty 01-04 (mock danych przez 02 i 04)
    scripts = [
        "01_create_tables.sql",
        "02_insert_test_data.sql",
        "03_views_and_procedures.sql",
        "04_demo_data.sql",
    ]
    with pegasus_conn() as conn:
        for script in scripts:
            execute_sql_file(conn, os.path.join(SQL_DIR, script))

    yield
    # Kontener CI jest efemeryczny – teardown nie jest potrzebny


# ══════════════════════════════════════════════════════════════════════════════
# TESTY – Struktura schematu
# ══════════════════════════════════════════════════════════════════════════════
class TestSchema:
    EXPECTED_TABLES = {
        "ROLES", "POST_CATEGORIES", "SPECIAL_ATTENTION_REASONS",
        "USERS", "POSTS", "LIKES", "COMMENTS", "SHARES",
        "POST_VIEWS", "USER_PROFILES",
    }
    EXPECTED_VIEWS = {
        "V_USER_ACTIVITY", "V_USER_PREFERRED_CATEGORY",
        "V_USER_POLITICAL_EXPOSURE", "V_FLAGGED_POSTS",
        "V_USER_FULL_PROFILE", "V_MY_INTERACTIONS",
    }
    EXPECTED_PROCEDURES = {
        "SP_CALCULATE_USER_PROFILE",
        "SP_CALCULATE_ALL_PROFILES",
        "SP_BUILD_SOCIAL_CLUSTERS",
    }

    def test_tables_exist(self):
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT table_name FROM user_tables")
            tables = {r[0] for r in cur}
        assert tables == self.EXPECTED_TABLES, f"Brakujace: {self.EXPECTED_TABLES - tables}"

    def test_views_exist(self):
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT view_name FROM user_views")
            views = {r[0] for r in cur}
        assert views == self.EXPECTED_VIEWS, f"Brakujace: {self.EXPECTED_VIEWS - views}"

    def test_procedures_valid(self):
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.execute(
                "SELECT object_name, status FROM user_objects WHERE object_type='PROCEDURE'"
            )
            procs = {r[0]: r[1] for r in cur}
        assert set(procs) == self.EXPECTED_PROCEDURES, f"Brakujace: {self.EXPECTED_PROCEDURES - set(procs)}"
        invalid = [n for n, s in procs.items() if s != "VALID"]
        assert not invalid, f"Procedury INVALID: {invalid}"

    def test_sequences_count(self):
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM user_sequences")
            assert cur.fetchone()[0] == 10

    def test_indexes_created(self):
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM user_indexes")
            # Co najmniej indeksy PK + dodatkowe (28 zgodnie z DDL)
            assert cur.fetchone()[0] >= 20


# ══════════════════════════════════════════════════════════════════════════════
# TESTY – Dane (mock data)
# ══════════════════════════════════════════════════════════════════════════════
class TestMockData:
    def test_roles_present(self):
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT name FROM roles ORDER BY role_id")
            names = [r[0] for r in cur]
        assert len(names) >= 2
        assert "Admin" in names or any("admin" in n.lower() for n in names)

    def test_categories_present(self):
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM post_categories")
            assert cur.fetchone()[0] >= 3

    def test_users_present(self):
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM users WHERE status != 'DELETED'")
            assert cur.fetchone()[0] >= 5

    def test_posts_present(self):
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM posts")
            assert cur.fetchone()[0] >= 5

    def test_interactions_present(self):
        """Przynajmniej jeden rodzaj interakcji powinien miec dane."""
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM likes")
            likes = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM comments")
            comments = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM shares")
            shares = cur.fetchone()[0]
        assert likes + comments + shares >= 1, "Brak danych interakcji"

    def test_special_attention_reasons_present(self):
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM special_attention_reasons")
            assert cur.fetchone()[0] >= 1


# ══════════════════════════════════════════════════════════════════════════════
# TESTY – Widoki analityczne
# ══════════════════════════════════════════════════════════════════════════════
class TestViews:
    def test_v_user_activity_returns_rows(self):
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM v_user_activity")
            assert cur.fetchone()[0] >= 1

    def test_v_user_activity_columns(self):
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT * FROM v_user_activity WHERE ROWNUM = 1")
            cols = [d[0] for d in cur.description]
        expected = {"USER_ID", "FULL_NAME", "STATUS", "TOTAL_LIKES",
                    "TOTAL_COMMENTS", "TOTAL_SHARES", "TOTAL_VIEWS"}
        assert expected.issubset(set(cols)), f"Brakujace kolumny: {expected - set(cols)}"

    def test_v_flagged_posts_accessible(self):
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM v_flagged_posts")
            cur.fetchone()

    def test_v_user_full_profile_accessible(self):
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM v_user_full_profile")
            cur.fetchone()

    def test_v_user_political_exposure_accessible(self):
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM v_user_political_exposure")
            cur.fetchone()


# ══════════════════════════════════════════════════════════════════════════════
# TESTY – Procedury składowane
# ══════════════════════════════════════════════════════════════════════════════
class TestProcedures:
    def _get_user_id(self, conn) -> int:
        cur = conn.cursor()
        cur.execute("SELECT user_id FROM users WHERE status != 'DELETED' AND ROWNUM = 1")
        row = cur.fetchone()
        assert row, "Brak aktywnych uzytkownikow w tabeli USERS"
        return row[0]

    def test_sp_calculate_user_profile_runs(self):
        """SP_CALCULATE_USER_PROFILE oblicza i zapisuje profil uzytkownika."""
        with pegasus_conn() as conn:
            user_id = self._get_user_id(conn)
            cur = conn.cursor()
            cur.callproc("SP_CALCULATE_USER_PROFILE", [user_id])
            conn.commit()

            # Profil powinien byc zapisany
            cur.execute(
                "SELECT engagement_score, activity_profile FROM user_profiles WHERE user_id = :1",
                [user_id],
            )
            row = cur.fetchone()
        assert row is not None, "Profil nie zostal zapisany do USER_PROFILES"
        assert row[0] is not None, "engagement_score jest NULL"
        assert row[1] in ("WYSOKA", "SREDNIA", "NISKA"), f"Nieprawidlowy activity_profile: {row[1]}"

    def test_sp_calculate_all_profiles_runs(self):
        """SP_CALCULATE_ALL_PROFILES dziala dla wszystkich uzytkownikow."""
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.callproc("SP_CALCULATE_ALL_PROFILES")
            conn.commit()

            # Przynajmniej jeden profil powinien byc w tabeli
            cur.execute("SELECT COUNT(*) FROM user_profiles")
            assert cur.fetchone()[0] >= 1

    def test_sp_build_social_clusters_runs(self):
        """SP_BUILD_SOCIAL_CLUSTERS uzupelnia SOCIAL_CLUSTER_ID."""
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.callproc("SP_BUILD_SOCIAL_CLUSTERS")
            conn.commit()

    def test_digital_fingerprint_sha256_format(self):
        """DIGITAL_FINGERPRINT powinien byc SHA-256 (64 znaki hex)."""
        with pegasus_conn() as conn:
            cur = conn.cursor()
            cur.execute(
                "SELECT digital_fingerprint FROM user_profiles "
                "WHERE digital_fingerprint IS NOT NULL AND ROWNUM = 1"
            )
            row = cur.fetchone()

        if row:  # moze byc NULL jesli brak interakcji
            fp = row[0]
            assert len(fp) == 64, f"Zly dlugosc fingerprint: {len(fp)}"
            assert re.fullmatch(r"[0-9A-Fa-f]{64}", fp), f"Zly format fingerprint: {fp}"

    def test_watched_status_set_for_extremist_users(self):
        """Uzytkownicy z kontaktem z ekstremistycznymi tresciami maja status WATCHED."""
        with pegasus_conn() as conn:
            cur = conn.cursor()
            # Sprawdz ile uzytkownikow ma EXTREMISM_EXPOSURE=1
            cur.execute(
                "SELECT COUNT(*) FROM user_profiles WHERE extremism_exposure = 1"
            )
            exposed = cur.fetchone()[0]
            if exposed > 0:
                # Przynajmniej jeden z nich powinien miec status WATCHED lub SUSPENDED
                cur.execute(
                    "SELECT COUNT(*) FROM users u "
                    "JOIN user_profiles up ON up.user_id = u.user_id "
                    "WHERE up.extremism_exposure = 1 AND u.status IN ('WATCHED','SUSPENDED','DELETED')"
                )
                assert cur.fetchone()[0] >= 1, "Uzytkownicy z extremism_exposure nie maja statusu WATCHED"
