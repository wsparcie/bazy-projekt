classDiagram
  %% PEGASUSownik - Diagram Klas (Algorytm Analizy) zmapowany na struktury bazy

  class USERS {
    +id INT
    +imie string
    +nazwisko string
    +email string
    +status string
    +rola_id FK
  }

  class POSTS {
    +id INT
    +autor_id FK
    +kategoria_id FK
    +powod_uwagi_id FK
    +skala_ekstremalnosci INT
  }

  class LIKES {
    +user_id FK
    +post_id FK
    +czas_spedzony INT
  }

  class COMMENTS {
    +user_id FK
    +post_id FK
    +tresc string
    +czas_spedzony INT
  }

  class SHARES {
    +from_user_id FK
    +post_id FK
    +to_user_id FK
    +czas_spedzony INT
  }

  class POST_VIEWS {
    +user_id FK
    +post_id FK
    +czas_start datetime
    +czas_end datetime
  }

  class USER_PROFILES {
    +user_id FK (1:1 z USERS)
    +engagement_score float
    +activity_profile string
    +preferred_category_id FK
    +preferred_topics string
    +political_lean string
    +political_score float
    +extremism_exposure_score float
    +opinion_influence_timeline string
    +digital_fingerprint SHA256
  }

  class ROLES {
    +nazwa string (Admin, UzytkownikWidok)
  }

  class POST_CATEGORIES {
    +kategoria string
    +flaga_polityczna boolean
    +kierunek string
  }

  class SPECIAL_ATTENTION_REASONS {
    +powod string
    +skala 1-5
  }

  %% Relacje encji podstawowych i słowników
  USERS "1" --> "0..1" ROLES : posiada rolę
  POSTS "1" --> "0..1" POST_CATEGORIES : posiada kategorię
  POSTS "1" --> "0..1" SPECIAL_ATTENTION_REASONS : może posiadać powód

  %% Interakcje z postami (Zastąpienie generycznej "Interakcji" dokładnymi tabelami)
  USERS "1" --> "0..*" LIKES : wykonuje
  USERS "1" --> "0..*" COMMENTS : tworzy
  USERS "1" --> "0..*" SHARES : inicjuje / odbiera
  USERS "1" --> "0..*" POST_VIEWS : ogląda

  POSTS "1" <-- "0..*" LIKES : dotyczy
  POSTS "1" <-- "0..*" COMMENTS : dotyczy
  POSTS "1" <-- "0..*" SHARES : dotyczy
  POSTS "1" <-- "0..*" POST_VIEWS : dotyczy

  %% Profil Behawioralny
  USERS "1" -- "1" USER_PROFILES : posiada
