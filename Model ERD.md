erDiagram
  ROLES {
    int id PK
    string rola
  }

  USERS {
    int id PK
    string imie
    string nazwisko
    string email
    string status
    int rola_id FK
  }

  POST_CATEGORIES {
    int id PK
    string nazwa
    boolean flaga_polityczna
    string kierunek
  }

  SPECIAL_ATTENTION_REASONS {
    int id PK
    string powod
    int skala
  }

  POSTS {
    int id PK
    int autor_id FK
    int kategoria_id FK
    int powod_uwagi_id FK
    int skala_ekstremalnosci
  }

  LIKES {
    int id PK
    int user_id FK
    int post_id FK
    int czas_spedzony
  }

  COMMENTS {
    int id PK
    int user_id FK
    int post_id FK
    string tresc
    int czas_spedzony
  }

  SHARES {
    int id PK
    int from_user_id FK
    int post_id FK
    int to_user_id FK
    int czas_spedzony
  }

  POST_VIEWS {
    int id PK
    int user_id FK
    int post_id FK
    datetime czas_start
    datetime czas_end
  }

  USER_PROFILES {
    int user_id PK
    string activity_profile
    float engagement_score
    int preferred_category_id FK
    string preferred_topics
    string political_lean
    float political_score
    float extremism_exposure_score
    string opinion_influence_timeline
    string digital_fingerprint
  }

  %% Relacje 
  ROLES ||--o{ USERS : "posiada"
  USERS ||--o{ POSTS : "tworzy_autor"
  
  POST_CATEGORIES ||--o{ POSTS : "kategoryzuje"
  SPECIAL_ATTENTION_REASONS |o--o{ POSTS : "flaguje"

  USERS ||--o{ LIKES : "wykonuje"
  POSTS ||--o{ LIKES : "otrzymuje"

  USERS ||--o{ COMMENTS : "pisze"
  POSTS ||--o{ COMMENTS : "posiada"

  USERS ||--o{ SHARES : "udostepnia_od"
  USERS |o--o{ SHARES : "otrzymuje_do"
  POSTS ||--o{ SHARES : "dotyczy"

  USERS ||--o{ POST_VIEWS : "generuje"
  POSTS ||--o{ POST_VIEWS : "jest_ogladany"

  USERS ||--|| USER_PROFILES : "posiada_profil"
