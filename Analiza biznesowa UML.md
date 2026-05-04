flowchart LR
subgraph Aktorzy
    A1[Admin]
    A2[Użytkownik / UzytkownikWidok]
end

subgraph AdminCases [Panel Administratora]
    U1[Zarządzaj kontami USERS]
    U1a[Zarządzaj słownikami kategorii i powodów]
    U2[Przeglądaj zagregowaną aktywność V_USER_ACTIVITY]
    U3[Analizuj pełne profile V_USER_FULL_PROFILE]
    U4[Monitoruj zagrożenia V_FLAGGED_POSTS]
    U5[Ręcznie przelicz SP_CALCULATE_ALL_PROFILES]
    U6[Generuj raporty i eksportuj dane]
    U8[Oznacz post jako szczególnej uwagi]
end

subgraph UserCases [Działania Użytkownika]
    U10[Logowanie]
    U11[Przeglądaj feed z treściami]
    U18[Rejestruj sesję oglądania POST_VIEWS]
    U12[Zostaw polubienie LIKES]
    U13[Napisz komentarz COMMENTS]
    U14[Udostępnij post SHARES]
    U15[Przeglądaj swój V_USER_BEHAVIORAL_PROFILE]
end

subgraph SystemCases [Automatyczne Procedury w Tle]
    S1[Agreguj dane do widoków analitycznych]
    S2[Wywołaj SP_CALCULATE_USER_PROFILE]
    S3[Buduj wzorzec Digital Fingerprint - SHA256]
    S4[Obliczaj ekspozycję na ekstremizm]
    S5[Grupuj użytkowników SP_BUILD_SOCIAL_CLUSTERS]
end

%% Powiązania Aktorów
A1 --> U1 & U1a & U2 & U3 & U4 & U5 & U6 & U8
A2 --> U10 & U11 & U12 & U13 & U14 & U15

%% Wymagania (Include)
U11 -.-> |<< zawiera >>| U10
U12 -.-> |<< zawiera >>| U10
U13 -.-> |<< zawiera >>| U10
U14 -.-> |<< zawiera >>| U10
U15 -.-> |<< zawiera >>| U10
U11 -.-> |<< zawiera >>| U18

%% Wyzwalacze analityczne bazodanowe (Triggery w tle)
U12 -.-> |<< wyzwala >>| S2
U13 -.-> |<< wyzwala >>| S2
U14 -.-> |<< wyzwala >>| S2
U18 -.-> |<< wyzwala >>| S1

%% Wewnętrzne zależności systemowe
S2 -.-> |<< zawiera >>| S3
S2 -.-> |<< zawiera >>| S4
S2 -.-> |<< wyzwala >>| S5
U5 -.-> |<< zawiera >>| S2
U8 -.-> |<< wyzwala >>| S1
