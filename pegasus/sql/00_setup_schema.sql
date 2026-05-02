-- ============================================================
-- Konfiguracja schematu PEGASUS na lokalnej bazie Oracle XE
-- Uruchamiac jako SYS (SYSDBA) na PDB: XEPDB1
--
-- Sposob uzycia (patrz README – sekcja "Uruchamianie lokalnie"):
--   docker exec -it pegasus-db sqlplus sys/Admin1234@XEPDB1 as sysdba @/sql/00_setup_schema.sql
--
-- UWAGA: Przed uruchomieniem ustaw zmienne srodowiskowe:
--   PEGASUS_PASSWORD  – haslo dla uzytkownika PEGASUS
--
-- Przyklad (bash):
--   export PEGASUS_PASSWORD='twoje_silne_haslo'
--   docker exec -e PEGASUS_PASSWORD pegasus-db sqlplus sys/Admin1234@XEPDB1 as sysdba @/sql/00_setup_schema.sql
--
-- W SQL*Plus zmieniona wartosc podstawia sie przez: &&PEGASUS_PASSWORD
-- ============================================================

CREATE USER PEGASUS IDENTIFIED BY && PEGASUS_PASSWORD;

GRANT CONNECT TO PEGASUS;

GRANT RESOURCE TO PEGASUS;

GRANT UNLIMITED TABLESPACE TO PEGASUS;

GRANT CREATE VIEW TO PEGASUS;

GRANT CREATE PROCEDURE TO PEGASUS;

GRANT CREATE SEQUENCE TO PEGASUS;

GRANT CREATE TABLE TO PEGASUS;

GRANT CREATE SESSION TO PEGASUS;

EXIT;