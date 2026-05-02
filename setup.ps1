#Requires -Version 5.1
<#
.SYNOPSIS
    One-click deploy PEGASUS database (Oracle XE w Dockerze)
.DESCRIPTION
    Uruchamia Oracle XE, tworzy schemat PEGASUS i laduje wszystkie dane.
    Przy ponownym uruchomieniu: resetuje schemat (DROP + CREATE).
    Wymaga: Docker Desktop
.EXAMPLE
    .\setup.ps1
    .\setup.ps1 -Reset
    .\setup.ps1 -SkipData
#>
param(
    [switch]$Reset,
    [switch]$SkipData
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ROOT        = Split-Path -Parent $MyInvocation.MyCommand.Path
$ENV_FILE    = Join-Path $ROOT ".env"
$COMPOSE     = Join-Path $ROOT "docker-compose.yml"
$CONTAINER   = "pegasus-db"
$ORACLE_SVC  = "XEPDB1"

function Write-Step  { param($n, $msg) Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Write-OK    { param($msg)     Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Fail  { param($msg)     Write-Host "    BLAD: $msg" -ForegroundColor Red; exit 1 }
function Write-Info  { param($msg)     Write-Host "    $msg" -ForegroundColor DarkGray }

function Invoke-OracleSQL {
    param([string]$ConnStr, [string]$SqlText)
    $tmp = [System.IO.Path]::GetTempFileName() + ".sql"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($tmp, $SqlText, $utf8NoBom)
    docker cp $tmp "${CONTAINER}:/tmp/_run.sql" | Out-Null
    $out = docker exec -u oracle $CONTAINER sqlplus -L $ConnStr "@/tmp/_run.sql" 2>&1 | Out-String
    $ec = $LASTEXITCODE
    Remove-Item $tmp -ErrorAction SilentlyContinue
    if ($out -match "ORA-|SP2-0") {
        if ($out -notmatch "ORA-\d{5}" -and $out -match "succeeded|created|completed") {
            return 0
        }
    }
    return $ec
}

Write-Host ""
Write-Host "#==========================================╗" -ForegroundColor Cyan
Write-Host "#   PEGASUS  –   Database Setup            #" -ForegroundColor Cyan
Write-Host "#==========================================#" -ForegroundColor Cyan

# ---------------------------------------------
Write-Step "1/6" "Sprawdzam Docker"
# ---------------------------------------------
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Fail "Docker nie jest zainstalowany. Pobierz: https://www.docker.com/products/docker-desktop/"
}
try { docker info 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw } }
catch { Write-Fail "Docker Desktop nie jest uruchomiony. Uruchom go i sprobuj ponownie." }
Write-OK "Docker uruchomiony"

# ---------------------------------------------
Write-Step "2/6" "Konfiguracja .env"
# ---------------------------------------------
if (-not (Test-Path $ENV_FILE)) {
    $pool = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789'
    $oraclePwd  = (-join (1..18 | ForEach-Object { $pool[(Get-Random -Maximum $pool.Length)] })) + "1a"
    $pegasusPwd = (-join (1..18 | ForEach-Object { $pool[(Get-Random -Maximum $pool.Length)] })) + "2b"
    "ORACLE_PASSWORD=$oraclePwd`nPEGASUS_PASSWORD=$pegasusPwd`n" |
        Out-File $ENV_FILE -Encoding utf8 -NoNewline
    Write-OK "Plik .env wygenerowany z losowymi haslami"
} else {
    Write-OK "Plik .env istnieje – uzywam istniejacych hasel"
}

$envRaw     = [System.IO.File]::ReadAllText($ENV_FILE)
$oraclePwd  = ($envRaw -split "`n" | Where-Object { $_ -match "^ORACLE_PASSWORD="  }) -replace "^ORACLE_PASSWORD=",""  | ForEach-Object { $_.Trim() } | Select-Object -First 1
$pegasusPwd = ($envRaw -split "`n" | Where-Object { $_ -match "^PEGASUS_PASSWORD=" }) -replace "^PEGASUS_PASSWORD=","" | ForEach-Object { $_.Trim() } | Select-Object -First 1

if (-not $oraclePwd -or -not $pegasusPwd) { Write-Fail "Nie udalo sie odczytac hasel z .env" }

# ---------------------------------------------
Write-Step "3/6" "Uruchamiam Oracle XE (Docker)"
# ---------------------------------------------
Push-Location $ROOT
$prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
cmd /c "docker compose up -d" 2>&1 | Out-Null
$ErrorActionPreference = $prevEAP
$running = docker ps --filter "name=$CONTAINER" --format "{{.Status}}" 2>&1
if (-not $running) { Write-Fail "docker compose up nieudany - kontener nie dziala" }
Pop-Location
Write-OK "Kontener $CONTAINER uruchomiony"

# ---------------------------------------------
Write-Step "4/6" "Czekam na gotowos Oracle XE (max 5 min)"
# ---------------------------------------------
$deadline = (Get-Date).AddMinutes(5)
$ready = $false
while ((Get-Date) -lt $deadline) {
    $log = docker logs $CONTAINER 2>&1 | Out-String
    if ($log -match "DATABASE IS READY TO USE") { $ready = $true; break }
    Write-Info "... inicjalizacja w toku"
    Start-Sleep 10
}
if (-not $ready) {
    docker logs $CONTAINER --tail 30
    Write-Fail "Oracle XE nie uruchomil sie w ciagu 5 minut"
}
Write-OK "Oracle XE GOTOWY"

# ---------------------------------------------
Write-Step "5/6" "Tworze schemat PEGASUS"
# ---------------------------------------------
$sysConn = "sys/${oraclePwd}@localhost:1521/${ORACLE_SVC}"

$createUser = @"
SET SERVEROUTPUT ON
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
CREATE USER PEGASUS IDENTIFIED BY "$pegasusPwd";
GRANT CONNECT, RESOURCE, UNLIMITED TABLESPACE TO PEGASUS;
GRANT CREATE VIEW, CREATE PROCEDURE, CREATE SEQUENCE, CREATE TABLE, CREATE SESSION TO PEGASUS;
PROMPT Uzytkownik PEGASUS gotowy.
EXIT;
"@

$ec = Invoke-OracleSQL "sys/${oraclePwd}@localhost:1521/${ORACLE_SVC} as sysdba" $createUser
if ($ec -ne 0) { Write-Fail "Tworzenie uzytkownika PEGASUS nieudane (exit $ec)" }
Write-OK "Uzytkownik PEGASUS utworzony"

# ---------------------------------------------
Write-Step "6/6" "Laduje skrypty SQL"
# ---------------------------------------------
$scripts = if ($SkipData) {
    "@/sql/01_create_tables.sql"
} else {
    "@/sql/01_create_tables.sql`n@/sql/02_insert_test_data.sql`n@/sql/03_views_and_procedures.sql`n@/sql/04_demo_data.sql"
}

$masterSql = @"
SET SQLBLANKLINES ON
$scripts
EXIT;
"@

$tmp = [System.IO.Path]::GetTempFileName() + ".sql"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($tmp, $masterSql, $utf8NoBom)
docker cp $tmp "${CONTAINER}:/tmp/_master.sql" | Out-Null
docker exec -u oracle $CONTAINER sqlplus "PEGASUS/${pegasusPwd}@localhost:1521/${ORACLE_SVC}" "@/tmp/_master.sql"
$ec = $LASTEXITCODE
Remove-Item $tmp -ErrorAction SilentlyContinue
if ($ec -ne 0) { Write-Fail "Uruchamianie skryptow SQL nieudane (exit $ec)" }
Write-OK "Skrypty SQL zaladowane"

# ---------------------------------------------
# Weryfikacja
# ---------------------------------------------
$verifySql = @"
ALTER SESSION SET CONTAINER = ${ORACLE_SVC};
SET LINESIZE 60
COLUMN object_type FORMAT A25
COLUMN cnt         FORMAT 9999
COLUMN object_name FORMAT A35
COLUMN status      FORMAT A10
SELECT object_type, COUNT(*) cnt
  FROM dba_objects WHERE owner='PEGASUS'
 GROUP BY object_type ORDER BY 1;
SELECT object_name, status
  FROM dba_objects WHERE owner='PEGASUS' AND object_type='PROCEDURE';
EXIT;
"@
Write-Host ""
Write-Host "  +- Stan schematu PEGASUS " + ("-" * 18) + "+" -ForegroundColor Cyan
$ec = Invoke-OracleSQL "/ as sysdba" $verifySql
Write-Host ""

$errSql = @"
ALTER SESSION SET CONTAINER = ${ORACLE_SVC};
SELECT COUNT(*) FROM dba_objects WHERE owner='PEGASUS' AND object_type='PROCEDURE' AND status='INVALID';
EXIT;
"@
$tmp2 = [System.IO.Path]::GetTempFileName() + ".sql"
[System.IO.File]::WriteAllText($tmp2, $errSql, [System.Text.Encoding]::UTF8)
docker cp $tmp2 "${CONTAINER}:/tmp/_check.sql" | Out-Null
$invalids = docker exec -u oracle $CONTAINER sqlplus -S "/ as sysdba" "@/tmp/_check.sql" 2>&1 |
    Where-Object { $_ -match "^\s*\d+\s*$" } | ForEach-Object { $_.Trim() } | Select-Object -First 1
Remove-Item $tmp2 -ErrorAction SilentlyContinue
if ($invalids -and [int]$invalids -gt 0) {
    Write-Host "  UWAGA: $invalids procedur(y) ma status INVALID – sprawdz logi powyzej." -ForegroundColor Yellow
}

# ---------------------------------------------
# Podsumowanie
# ---------------------------------------------
$port = (Get-Content $COMPOSE | Select-String '"\d+:1521"').ToString() -replace '.*"(\d+):1521".*','$1'

Write-Host ""
Write-Host "#==========================================╗" -ForegroundColor Green
Write-Host "#            GOTOWE!                       #" -ForegroundColor Green
Write-Host "#==========================================#" -ForegroundColor Green
Write-Host ""
Write-Host "  Dane polaczenia (SQL Developer / DBeaver):" -ForegroundColor White
Write-Host "    Host:         localhost"         -ForegroundColor White
Write-Host "    Port:         $port"             -ForegroundColor White
Write-Host "    Service name: $ORACLE_SVC"       -ForegroundColor White
Write-Host "    Uzytkownik:   PEGASUS"            -ForegroundColor White
Write-Host "    Haslo:        (patrz plik .env)" -ForegroundColor White
Write-Host ""
Write-Host "  Zatrzymanie:  docker compose down"         -ForegroundColor DarkGray
Write-Host "  Pelny reset:  docker compose down -v"      -ForegroundColor DarkGray
