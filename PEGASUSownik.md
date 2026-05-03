# PEGASUSownik


## Co to jest

System zbierania i analizy danych o zachowaniu użytkowników na podstawie tego, jak wchodzą w interakcje z postami. Zakładamy, że moduł analityczny działa w tle jako część już istniejącej platformy społecznościowej.

---

## Dane o użytkownikach

Przechowujemy podstawowe dane w tabeli `USERS`: id, imię, nazwisko, e-mail oraz status konta. Dodatkowo każdy użytkownik ma przypisaną odgórnie rolę w systemie z tabeli `ROLES` (np. `Admin` lub `UzytkownikWidok`).

---

## Posty

Każdy post ma przypisaną kategorię treści oraz opcjonalnie powód, dla którego wymaga "szczególnej uwagi". Są to dwie osobne rzeczy, gdyż post może być polityczny i jednocześnie ekstremistyczny, albo zupełnie neutralny i też problematyczny.

Do postów dodajemy też 5-stopniową skalę ekstremalności, żeby odróżnić lekkie przekleństwo od jawnej przemocy.

**Kategorie treści** (`POST_CATEGORIES`):
- bezpieczne - kotki, kawusia, muzyka, gotowanie itp.
- polityczne - polemika polityczna/światopoglądowa, treści z krańców spektrum (mają nadaną w bazie tzw. flagę polityczną).

**Powody szczególnej uwagi** (`SPECIAL_ATTENTION_REASONS`):
- poradniki, jak robić nielegalne rzeczy (np. omijanie regulaminów)
- materiały niewygodne dla reklamodawców
- treści ekstremistyczne (rasizm, mizoginia, homofobia etc.)
- treści antydemokratyczne, prorosyjskie, eurosceptyczne, antysemickie
- wulgarny język / przemoc

---

## Interakcje

Śledzimy cztery rodzaje interakcji (każda ma swoją osobną tabelę w bazie):

- **polubienia** (`LIKES`): kto, co, czas spędzony
- **komentarze** (`COMMENTS`): kto, co, treść komentarza, czas spędzony
- **udostępnienia** (`SHARES`): kto, co, komu, czas spędzony
- **sesje oglądania** (`POST_VIEWS`): dokładny czas startu i zakończenia czytania/oglądania posta przez użytkownika

---

## Co chcemy z tego wyciągnąć

Na podstawie historii interakcji nasza baza danych za pomocą specjalnej procedury automatycznie buduje profil każdego użytkownika. Wszystko jest zebrane w jedną tabelę (`USER_PROFILES`) - jeden wiersz na użytkownika:

- **zainteresowania i preferowana tematyka treści** (wyliczane wagowo: np. komentarz punktuje wyżej niż lajk)
- **stopień zaangażowania** (czy tylko biernie lajkuje, czy jest aktywnym twórcą dyskusji)
- **profil poglądów politycznych** (na podstawie interakcji z postami nacechowanymi politycznie)
- **ekspozycja na ekstremizm** (jak często ma styczność z oflagowanymi treściami)
- **grupy powiązań (klastry)** między użytkownikami na podstawie wspólnych zachowań i udostępnień
- **wpływ w czasie** - jak treści wpływają na opinie użytkownika (trend: stabilna / rosnąca / malejąca)
- **digital fingerprint** - charakterystyczny wzorzec zachowania online zapisany jako hash SHA-256

---

## Kto co widzi

**Admin** - dostęp do wszystkiego (widzi użytkowników, posty, wszystkie interakcje, oflagowane treści i ma wgląd w pełne profile analityczne poprzez specjalne widoki).

**Użytkownik** - widzi tylko swoje polubione posty i swoje komentarze. Może ewentualnie zobaczyć swój mocno uproszczony, publiczny zarys profilu, ale nie ma pojęcia o istnieniu analitycznego silnika w tle.

---

## Technologia

Projekt zrealizowany zostanie na chmurowej bazie **Oracle Autonomous Database** (usługa Free Tier), obsługiwanej przez przeglądarkę (SQL Developer Web) - pozwala to na pisanie zaawansowanych procedur działających w tle. 
Alternatywnie, projekt jest przygotowany tak, że każdy członek zespołu i prowadzący może go uruchomić lokalnie na swoim komputerze za pomocą **Dockera (baza Oracle XE)** bez żadnej instalacji oprogramowania chmurowego.
