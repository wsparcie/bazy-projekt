# PEGASUSownik

_System Analizy Behawioralnej Platformy Społecznościowej_

Projekt bazy danych dla klienta (grupa F).
Implementacja na Oracle Autonomous Database (Free Tier) — SQL Developer Web.

---

## Opis systemu

Moduł analityczny osadzony w istniejącej platformie społecznościowej.  
Zbiera dane o interakcjach użytkowników z treściami (polubienia, komentarze, udostępnienia, czas oglądania) i na ich podstawie automatycznie buduje profil behawioralny każdego użytkownika:

- preferowana tematyka treści,
- wskaźnik zaangażowania,
- profil poglądów politycznych,
- ekspozycja na treści ekstremistyczne,
- potencjalne grupy powiązań między użytkownikami (klastry).

---

## Struktura projektu

```
pegasus/
├── analysis/
│   ├── Analiza biznesowa UML.md          ← diagram przypadków użycia (Mermaid)
│   ├── Algorytm analizy behawioralnej UML.md  ← diagram klas UML (Mermaid)
│   ├── Model ERD.md                      ← diagram ERD (Mermaid)
│   └── PEGASUSownik.md                   ← opis koncepcji systemu
├── diagrams/
│   ├── 01_use_case.puml                  ← przypadki użycia (PlantUML)
│   ├── 02_activity_profile_calc.puml     ← czynności: obliczanie profilu
│   ├── 03_activity_user_interaction.puml ← czynności: interakcja użytkownika
│   ├── 04_state_user.puml                ← diagram stanów użytkownika
│   └── 05_erd.puml                       ← ERD (PlantUML)
└── sql/
    ├── 00_setup_schema.sql               ← tworzenie użytkownika PEGASUS (tylko lokalnie / XE)
    ├── 01_create_tables.sql              ← DDL: tabele, sekwencje, więzy
    ├── 02_insert_test_data.sql           ← dane testowe (słowniki + przykładowi użytkownicy)
    ├── 03_views_and_procedures.sql       ← widoki analityczne + procedura SP_CALCULATE_PROFILE
    └── 04_demo_data.sql                  ← dane demo na zajęcia
```

---

## Schemat bazy danych

### Tabele

| Tabela                      | Opis                                                        |
| --------------------------- | ----------------------------------------------------------- |
| `ROLES`                     | Role użytkowników (`Admin`, `UzytkownikWidok`)              |
| `POST_CATEGORIES`           | Słownik kategorii treści (z flagą polityczną i kierunkiem)  |
| `SPECIAL_ATTENTION_REASONS` | Słownik powodów szczególnej uwagi (skala 1–5)               |
| `USERS`                     | Użytkownicy (imię, nazwisko, e-mail, status, rola)          |
| `POSTS`                     | Posty (autor, kategoria, powód uwagi, skala ekstremalności) |
| `LIKES`                     | Polubienia (user → post, czas spędzony)                     |
| `COMMENTS`                  | Komentarze (user → post, treść, czas spędzony)              |
| `SHARES`                    | Udostępnienia (from_user → post → to_user, czas spędzony)   |
| `POST_VIEWS`                | Sesje oglądania postów (czas start/end)                     |
| `USER_PROFILES`             | Profile behawioralne użytkowników (1:1 z `USERS`)           |

### Widoki analityczne

| Widok                       | Opis                                                                        |
| --------------------------- | --------------------------------------------------------------------------- |
| `V_USER_ACTIVITY`           | Sumaryczna aktywność użytkownika (lajki, komentarze, udostępnienia, widoki) |
| `V_USER_PREFERRED_CATEGORY` | Top-1 preferowana kategoria (ważone: lajk×1, komentarz×3, udostępnienie×2)  |
| `V_USER_POLITICAL_EXPOSURE` | Ekspozycja polityczna (LEFT / RIGHT / CENTER / EXTREMIST)                   |
| `V_FLAGGED_POSTS`           | Treści szczególnej uwagi (dla administratora)                               |
| `V_USER_BEHAVIORAL_PROFILE` | Pełny profil behawioralny użytkownika (dla admina)                          |

### Procedura

`SP_CALCULATE_PROFILE(p_user_id)` — przelicza i zapisuje do `USER_PROFILES`:

- `ENGAGEMENT_SCORE` i `ACTIVITY_PROFILE` (WYSOKA / SREDNIA / NISKA),
- `PREFERRED_CATEGORY_ID` i `PREFERRED_TOPICS`,
- `POLITICAL_LEAN` i `POLITICAL_SCORE`,
- `EXTREMISM_EXPOSURE_SCORE`,
- `OPINION_INFLUENCE_TIMELINE` (STABILNA / ROSNACA / MALEJACA),
- `DIGITAL_FINGERPRINT` (hash SHA-256 wzorca zachowania).

---

## Podział pracy

| Osoba | Zakres                                                                                          |
| ----- | ----------------------------------------------------------------------------------------------- |
| **1** | Analiza biznesowa, opis procesów, wymagania, diagram UML przypadków użycia                      |
| **2** | Model ERD, decyzje projektowe, słowniki kategorii i powodów                                     |
| **3** | Algorytm analizy behawioralnej, diagramy UML czynności i stanu, widoki SQL                      |
| **4** | Wdrożenie Oracle Cloud, skrypty DDL/DML, procedury, demo na zajęciach, materiały do prezentacji |

---

## Kolejność uruchamiania skryptów SQL

**Oracle Autonomous Database (chmura)** — jako użytkownik `ADMIN` w SQL Developer Web:

```sql
@01_create_tables.sql          -- tworzy tabele i sekwencje
@02_insert_test_data.sql       -- słowniki i dane testowe
@03_views_and_procedures.sql   -- widoki i procedura SP_CALCULATE_PROFILE
@04_demo_data.sql              -- dane demo
```

**Lokalnie (Docker + Oracle XE)** — patrz sekcja [Uruchamianie lokalnie](#uruchamianie-lokalnie-docker--oracle-xe):

```sql
-- Jako SYS:
@00_setup_schema.sql           -- tworzy użytkownika PEGASUS (jednorazowo)

-- Jako PEGASUS:
@01_create_tables.sql
@02_insert_test_data.sql
@03_views_and_procedures.sql
@04_demo_data.sql
```

---

## Uruchamianie lokalnie (Docker + Oracle XE)

Alternatywa dla Oracle Autonomous Database (chmura) — każdy może uruchomić bazę na swoim komputerze bez konta Oracle Cloud.

### Wymagania

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows / macOS / Linux)

### Krok 1 — uruchom kontener

```bash
docker compose up -d
```

Obraz `gvenzl/oracle-xe:21-slim` (~1 GB) zostanie pobrany automatycznie.  
Pierwsze uruchomienie trwa **2–4 minuty** (inicjalizacja bazy). Gotowość sprawdzisz przez:

```bash
docker logs pegasus-db --tail 10
# Szukaj linii: DATABASE IS READY TO USE!
```

### Krok 2 — utwórz schemat PEGASUS

Ustaw hasło dla użytkownika PEGASUS i uruchom skrypt konfiguracyjny:

```bash
# Ustaw hasło jako zmienną środowiskową (wybierz własne, silne hasło)
export PEGASUS_PASSWORD='twoje_silne_haslo'

# Połącz się jako SYS i uruchom skrypt
docker exec -it pegasus-db sqlplus sys/Admin1234@XEPDB1 as sysdba @/sql/00_setup_schema.sql
# SQL*Plus zapyta o wartość &&PEGASUS_PASSWORD — wpisz swoje hasło
```

Skrypt tworzy użytkownika `PEGASUS` z podanym przez Ciebie hasłem i nadaje mu wszystkie potrzebne uprawnienia.

### Krok 3 — uruchom skrypty projektu

```bash
# Połącz się jako PEGASUS (użyj hasła wybranego w kroku 2)
docker exec -it pegasus-db sqlplus PEGASUS/<twoje_haslo>@XEPDB1

# Następnie wewnątrz SQL*Plus:
@/sql/01_create_tables.sql
@/sql/02_insert_test_data.sql
@/sql/03_views_and_procedures.sql
@/sql/04_demo_data.sql
```

### Dane połączenia (SQL Developer / DBeaver / inne narzędzia)

| Parametr     | Wartość                 |
| ------------ | ----------------------- |
| Host         | `localhost`             |
| Port         | `1521`                  |
| Service name | `XEPDB1`                |
| Użytkownik   | `PEGASUS`               |
| Hasło        | _(ustawione w kroku 2)_ |

> **SQL Developer**: wybierz typ połączenia _Basic_, wpisz powyższe dane.  
> **DBeaver**: sterownik _Oracle_, Service Name = `XEPDB1`.

### Zatrzymanie / reset

```bash
# Zatrzymaj kontener (dane zachowane)
docker compose down

# Usuń kontener + dane (pełny reset)
docker compose down -v
```

---

## Konwencje Git

```
main                              ← zostawiamy bez zmian
pegasus                           ← wersja prezentacyjna (tylko merge przez PR)
    feat/analiza-biznesowa-UML
    feat/erd-model
    feat/analiza-behawioralna-UML
    feat/oracle-wdrozenie
```

Każda osoba pracuje na swojej gałęzi feature i otwiera Pull Request do `pegasus` po zakończeniu zadania.
