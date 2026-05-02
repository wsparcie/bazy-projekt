-- ============================================================
-- Widoki analityczne i procedura obliczania profilu
-- Uruchamiac po 02_insert_test_data.sql
-- ============================================================

-- Wymagane: blanklines wewnatrz blokow PL/SQL nie przerywaja kompilacji
SET SQLBLANKLINES ON

-- ============================================================
-- Widok: Aktywnosc uzytkownika (sumaryczna)
-- ============================================================
CREATE OR REPLACE VIEW V_USER_ACTIVITY AS
SELECT
    u.USER_ID,
    u.FIRST_NAME || ' ' || u.LAST_NAME AS FULL_NAME,
    u.STATUS,
    COUNT(DISTINCT l.LIKE_ID) AS TOTAL_LIKES,
    COUNT(DISTINCT c.COMMENT_ID) AS TOTAL_COMMENTS,
    COUNT(DISTINCT s.SHARE_ID) AS TOTAL_SHARES,
    COUNT(DISTINCT v.VIEW_ID) AS TOTAL_VIEWS,
    ROUND(
        AVG(
            (
                EXTRACT(
                    HOUR
                    FROM (v.VIEW_END - v.VIEW_START)
                ) * 3600 + EXTRACT(
                    MINUTE
                    FROM (v.VIEW_END - v.VIEW_START)
                ) * 60 + EXTRACT(
                    SECOND
                    FROM (v.VIEW_END - v.VIEW_START)
                )
            )
        ),
        1
    ) AS AVG_VIEW_DURATION_SEC
FROM
    USERS u
    LEFT JOIN LIKES l ON l.USER_ID = u.USER_ID
    LEFT JOIN COMMENTS c ON c.USER_ID = u.USER_ID
    LEFT JOIN SHARES s ON s.FROM_USER_ID = u.USER_ID
    LEFT JOIN POST_VIEWS v ON v.USER_ID = u.USER_ID
    AND v.VIEW_END IS NOT NULL
GROUP BY
    u.USER_ID,
    u.FIRST_NAME,
    u.LAST_NAME,
    u.STATUS;

-- ============================================================
-- Widok: Preferowana kategoria (top 1 na uzytkownika)
-- Uwzglednia polubienia, komentarze (x3) i udostepnienia (x2)
-- Agreguje wszystkie interakcje PRZED rankingiem – bez duplikatow
-- ============================================================
CREATE OR REPLACE VIEW V_USER_PREFERRED_CATEGORY AS
SELECT
    USER_ID,
    CATEGORY_ID,
    TOTAL_INTERACTIONS AS INTERACTION_COUNT
FROM (
        SELECT
            USER_ID, CATEGORY_ID, SUM(CNT) AS TOTAL_INTERACTIONS, RANK() OVER (
                PARTITION BY
                    USER_ID
                ORDER BY SUM(CNT) DESC
            ) AS RNK
        FROM (
                SELECT l.USER_ID, p.CATEGORY_ID, COUNT(*) AS CNT
                FROM LIKES l
                    JOIN POSTS p ON p.POST_ID = l.POST_ID
                GROUP BY
                    l.USER_ID, p.CATEGORY_ID
                UNION ALL
                SELECT c.USER_ID, p.CATEGORY_ID, COUNT(*) * 3 AS CNT
                FROM COMMENTS c
                    JOIN POSTS p ON p.POST_ID = c.POST_ID
                GROUP BY
                    c.USER_ID, p.CATEGORY_ID
                UNION ALL
                SELECT s.FROM_USER_ID, p.CATEGORY_ID, COUNT(*) * 2 AS CNT
                FROM SHARES s
                    JOIN POSTS p ON p.POST_ID = s.POST_ID
                GROUP BY
                    s.FROM_USER_ID, p.CATEGORY_ID
            ) raw_interactions
        GROUP BY
            USER_ID, CATEGORY_ID
    )
WHERE
    RNK = 1;

-- ============================================================
-- Widok: Ekspozycja polityczna uzytkownika
-- ============================================================
CREATE OR REPLACE VIEW V_USER_POLITICAL_EXPOSURE AS
SELECT src.USER_ID, pc.POLITICAL_LEAN, SUM(src.CNT) AS INTERACTION_COUNT
FROM (
        SELECT l.USER_ID, p.CATEGORY_ID, COUNT(*) AS CNT
        FROM LIKES l
            JOIN POSTS p ON p.POST_ID = l.POST_ID
        GROUP BY
            l.USER_ID, p.CATEGORY_ID
        UNION ALL
        SELECT c.USER_ID, p.CATEGORY_ID, COUNT(*) AS CNT
        FROM COMMENTS c
            JOIN POSTS p ON p.POST_ID = c.POST_ID
        GROUP BY
            c.USER_ID, p.CATEGORY_ID
        UNION ALL
        SELECT s.FROM_USER_ID, p.CATEGORY_ID, COUNT(*) AS CNT
        FROM SHARES s
            JOIN POSTS p ON p.POST_ID = s.POST_ID
        GROUP BY
            s.FROM_USER_ID, p.CATEGORY_ID
    ) src
    JOIN POST_CATEGORIES pc ON pc.CATEGORY_ID = src.CATEGORY_ID
WHERE
    pc.IS_POLITICAL = 1
GROUP BY
    src.USER_ID,
    pc.POLITICAL_LEAN;

-- ============================================================
-- Widok: Tresci szczegolnej uwagi (dla administratora)
-- ============================================================
CREATE OR REPLACE VIEW V_FLAGGED_POSTS AS
SELECT
    p.POST_ID,
    u.FIRST_NAME || ' ' || u.LAST_NAME AS AUTHOR,
    pc.NAME AS CATEGORY,
    r.NAME AS ATTENTION_REASON,
    r.SEVERITY_LEVEL,
    p.SEVERITY_SCORE,
    p.CONTENT_SUMMARY,
    p.CREATED_AT,
    p.IS_FLAGGED
FROM
    POSTS p
    JOIN USERS u ON u.USER_ID = p.AUTHOR_ID
    JOIN POST_CATEGORIES pc ON pc.CATEGORY_ID = p.CATEGORY_ID
    LEFT JOIN SPECIAL_ATTENTION_REASONS r ON r.REASON_ID = p.REASON_ID
WHERE
    p.REASON_ID IS NOT NULL
    OR p.IS_FLAGGED = 1
ORDER BY COALESCE(
        p.SEVERITY_SCORE, r.SEVERITY_LEVEL, 0
    ) DESC;

-- ============================================================
-- Widok: Profil behawioralny – pelny (dla admina)
-- UML: Admin.dostepDoWszystkiego() – wszystkie pola ProfilAnalitycznego
-- ============================================================
CREATE OR REPLACE VIEW V_USER_FULL_PROFILE AS
SELECT
    up.USER_ID,
    u.FIRST_NAME || ' ' || u.LAST_NAME AS FULL_NAME,
    u.STATUS,
    r.NAME AS ROLE_NAME,
    pc.NAME AS PREFERRED_CATEGORY,
    up.PREFERRED_TOPICS,
    up.ENGAGEMENT_SCORE,
    up.ACTIVITY_PROFILE,
    up.POLITICAL_LEAN,
    up.POLITICAL_SCORE,
    CASE up.EXTREMISM_EXPOSURE
        WHEN 1 THEN 'TAK'
        ELSE 'NIE'
    END AS EXTREMISM_EXPOSURE,
    up.SOCIAL_CLUSTER_ID,
    up.OPINION_INFLUENCE_TIMELINE,
    up.DIGITAL_FINGERPRINT,
    up.LAST_UPDATED
FROM
    USER_PROFILES up
    JOIN USERS u ON u.USER_ID = up.USER_ID
    LEFT JOIN ROLES r ON r.ROLE_ID = u.ROLE_ID
    LEFT JOIN POST_CATEGORIES pc ON pc.CATEGORY_ID = up.PREFERRED_CATEGORY_ID;

-- ============================================================
-- Widok: Interakcje uzytkownika (dla samego uzytkownika)
-- UML: UzytkownikWidok.widziPolubionePosty() + widziSwojeKomentarze()
-- ============================================================
CREATE OR REPLACE VIEW V_MY_INTERACTIONS AS
SELECT
    'LIKE' AS INTERACTION_TYPE,
    l.USER_ID,
    p.POST_ID,
    p.CONTENT_SUMMARY,
    pc.NAME AS CATEGORY,
    l.LIKED_AT AS INTERACTION_DATE,
    NULL AS COMMENT_TEXT,
    l.TIME_SPENT_SEC
FROM
    LIKES l
    JOIN POSTS p ON p.POST_ID = l.POST_ID
    JOIN POST_CATEGORIES pc ON pc.CATEGORY_ID = p.CATEGORY_ID
UNION ALL
SELECT
    'COMMENT' AS INTERACTION_TYPE,
    c.USER_ID,
    p.POST_ID,
    p.CONTENT_SUMMARY,
    pc.NAME AS CATEGORY,
    c.COMMENTED_AT,
    c.CONTENT,
    c.TIME_SPENT_SEC
FROM
    COMMENTS c
    JOIN POSTS p ON p.POST_ID = c.POST_ID
    JOIN POST_CATEGORIES pc ON pc.CATEGORY_ID = p.CATEGORY_ID
UNION ALL
SELECT
    'SHARE' AS INTERACTION_TYPE,
    s.FROM_USER_ID,
    p.POST_ID,
    p.CONTENT_SUMMARY,
    pc.NAME AS CATEGORY,
    s.SHARED_AT,
    NULL AS COMMENT_TEXT,
    s.TIME_SPENT_SEC
FROM
    SHARES s
    JOIN POSTS p ON p.POST_ID = s.POST_ID
    JOIN POST_CATEGORIES pc ON pc.CATEGORY_ID = p.CATEGORY_ID;

-- ============================================================
-- Procedura: oblicz i zapisz profil behawioralny uzytkownika
-- ============================================================
CREATE OR REPLACE PROCEDURE SP_CALCULATE_USER_PROFILE (p_user_id IN NUMBER) AS
    v_total_likes         NUMBER := 0;

v_total_comments NUMBER := 0;

v_total_shares NUMBER := 0;

v_engagement NUMBER (5, 2) := 0;

v_preferred_cat NUMBER;

v_preferred_topics VARCHAR2 (500);

v_activity_profile VARCHAR2 (20) := 'NISKA';

v_political_lean VARCHAR2 (20) := 'NONE';

v_political_score NUMBER (5, 2) := 0;

v_extremism NUMBER := 0;

v_left_count NUMBER := 0;

v_right_count NUMBER := 0;

v_ext_count NUMBER := 0;

v_pol_total NUMBER := 0;

v_pol_recent NUMBER := 0;

v_pol_older NUMBER := 0;

v_opinion_timeline VARCHAR2 (20) := 'STABILNA';

v_digital_fp VARCHAR2 (64);

BEGIN
    SELECT COUNT(*) INTO v_total_likes    FROM LIKES    WHERE USER_ID = p_user_id;
    SELECT COUNT(*) INTO v_total_comments FROM COMMENTS WHERE USER_ID = p_user_id;
    SELECT COUNT(*) INTO v_total_shares   FROM SHARES   WHERE FROM_USER_ID = p_user_id;

    v_engagement := LEAST(100,
        ROUND((v_total_likes + v_total_comments * 3 + v_total_shares * 3) / 10.0, 2));

    IF    v_engagement >= 70 THEN v_activity_profile := 'WYSOKA';
    ELSIF v_engagement >= 30 THEN v_activity_profile := 'SREDNIA';
    ELSE                          v_activity_profile := 'NISKA';
    END IF;

    BEGIN
        SELECT CATEGORY_ID INTO v_preferred_cat
        FROM V_USER_PREFERRED_CATEGORY
        WHERE USER_ID = p_user_id
        AND ROWNUM = 1;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        v_preferred_cat := NULL;
    END;

    BEGIN
        SELECT LISTAGG(pc.NAME, ', ') WITHIN GROUP (ORDER BY src.TOTAL DESC)
        INTO v_preferred_topics
        FROM (
            SELECT CATEGORY_ID, SUM(CNT) AS TOTAL
            FROM (
                SELECT p.CATEGORY_ID, COUNT(*) AS CNT
                FROM LIKES l
                JOIN POSTS p ON p.POST_ID = l.POST_ID
                WHERE l.USER_ID = p_user_id
                GROUP BY p.CATEGORY_ID
                UNION ALL
                SELECT p.CATEGORY_ID, COUNT(*) * 3 AS CNT
                FROM COMMENTS c
                JOIN POSTS p ON p.POST_ID = c.POST_ID
                WHERE c.USER_ID = p_user_id
                GROUP BY p.CATEGORY_ID
                UNION ALL
                SELECT p.CATEGORY_ID, COUNT(*) * 2 AS CNT
                FROM SHARES s
                JOIN POSTS p ON p.POST_ID = s.POST_ID
                WHERE s.FROM_USER_ID = p_user_id
                GROUP BY p.CATEGORY_ID
            ) interaction_data
            GROUP BY CATEGORY_ID
        ) src
        JOIN POST_CATEGORIES pc ON pc.CATEGORY_ID = src.CATEGORY_ID;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        v_preferred_topics := NULL;
    END;

    BEGIN
        SELECT
            NVL(SUM(CASE WHEN POLITICAL_LEAN = 'LEFT'      THEN INTERACTION_COUNT ELSE 0 END), 0),
            NVL(SUM(CASE WHEN POLITICAL_LEAN = 'RIGHT'     THEN INTERACTION_COUNT ELSE 0 END), 0),
            NVL(SUM(CASE WHEN POLITICAL_LEAN = 'EXTREMIST' THEN INTERACTION_COUNT ELSE 0 END), 0)
        INTO v_left_count, v_right_count, v_ext_count
        FROM V_USER_POLITICAL_EXPOSURE
        WHERE USER_ID = p_user_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        NULL;
    END;

    v_pol_total := v_left_count + v_right_count + v_ext_count;
    IF v_pol_total > 0 THEN
        v_political_score := ROUND(
            (v_right_count - v_left_count) * 100.0 / v_pol_total, 2);
        IF    v_ext_count * 2 > v_pol_total THEN v_political_lean := 'EXTREMIST';
        ELSIF v_political_score < -30        THEN v_political_lean := 'LEFT';
        ELSIF v_political_score >  30        THEN v_political_lean := 'RIGHT';
        ELSE                                      v_political_lean := 'CENTER';
        END IF;
    END IF;

    SELECT COUNT(*) INTO v_extremism
    FROM LIKES l
    JOIN POSTS p ON p.POST_ID = l.POST_ID
    JOIN SPECIAL_ATTENTION_REASONS r ON r.REASON_ID = p.REASON_ID
    WHERE l.USER_ID = p_user_id AND r.SEVERITY_LEVEL >= 4;

    IF v_extremism = 0 THEN
        SELECT COUNT(*) INTO v_extremism
        FROM SHARES s
        JOIN POSTS p ON p.POST_ID = s.POST_ID
        JOIN SPECIAL_ATTENTION_REASONS r ON r.REASON_ID = p.REASON_ID
        WHERE s.FROM_USER_ID = p_user_id AND r.SEVERITY_LEVEL >= 4;
    END IF;

    BEGIN
        SELECT
            NVL(SUM(CASE WHEN l.LIKED_AT >= SYSTIMESTAMP - INTERVAL '30' DAY THEN 1 ELSE 0 END), 0),
            NVL(SUM(CASE WHEN l.LIKED_AT <  SYSTIMESTAMP - INTERVAL '30' DAY THEN 1 ELSE 0 END), 0)
        INTO v_pol_recent, v_pol_older
        FROM LIKES l
        JOIN POSTS p ON p.POST_ID = l.POST_ID
        JOIN POST_CATEGORIES pc ON pc.CATEGORY_ID = p.CATEGORY_ID
        WHERE l.USER_ID = p_user_id AND pc.IS_POLITICAL = 1;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        NULL;
    END;

    IF    v_pol_recent > v_pol_older * 1.3 THEN v_opinion_timeline := 'ROSNACA';
    ELSIF v_pol_older  > v_pol_recent * 1.3 THEN v_opinion_timeline := 'MALEJACA';
    ELSE                                         v_opinion_timeline := 'STABILNA';
    END IF;

    SELECT STANDARD_HASH(
        TO_CHAR(p_user_id) || '|' || v_political_lean || '|' ||
        TO_CHAR(v_engagement) || '|' || NVL(TO_CHAR(v_preferred_cat), 'NULL') || '|' ||
        v_activity_profile,
        'SHA256'
    ) INTO v_digital_fp FROM DUAL;

    IF v_extremism > 0 THEN
        UPDATE USERS
        SET STATUS = 'WATCHED'
        WHERE USER_ID = p_user_id
          AND STATUS = 'ACTIVE';
    END IF;

    MERGE INTO USER_PROFILES up
    USING (SELECT p_user_id AS SRC_USER_ID FROM DUAL) src
    ON (up.USER_ID = src.SRC_USER_ID)
    WHEN MATCHED THEN
        UPDATE SET
            PREFERRED_CATEGORY_ID      = v_preferred_cat,
            PREFERRED_TOPICS           = v_preferred_topics,
            ENGAGEMENT_SCORE           = v_engagement,
            ACTIVITY_PROFILE           = v_activity_profile,
            POLITICAL_LEAN             = v_political_lean,
            POLITICAL_SCORE            = v_political_score,
            EXTREMISM_EXPOSURE         = CASE WHEN v_extremism > 0 THEN 1 ELSE 0 END,
            OPINION_INFLUENCE_TIMELINE = v_opinion_timeline,
            DIGITAL_FINGERPRINT        = v_digital_fp,
            LAST_UPDATED               = SYSTIMESTAMP
    WHEN NOT MATCHED THEN
        INSERT (USER_ID, PREFERRED_CATEGORY_ID, PREFERRED_TOPICS,
                ENGAGEMENT_SCORE, ACTIVITY_PROFILE,
                POLITICAL_LEAN, POLITICAL_SCORE, EXTREMISM_EXPOSURE,
                OPINION_INFLUENCE_TIMELINE, DIGITAL_FINGERPRINT, LAST_UPDATED)
        VALUES (p_user_id, v_preferred_cat, v_preferred_topics,
                v_engagement, v_activity_profile,
                v_political_lean, v_political_score,
                CASE WHEN v_extremism > 0 THEN 1 ELSE 0 END,
                v_opinion_timeline, v_digital_fp, SYSTIMESTAMP);
    COMMIT;
END SP_CALCULATE_USER_PROFILE;
/

-- ============================================================
-- Przelicz profile dla wszystkich uzytkownikow (batch)
-- ============================================================
CREATE OR REPLACE PROCEDURE SP_CALCULATE_ALL_PROFILES AS
BEGIN
    FOR u IN (SELECT USER_ID FROM USERS WHERE STATUS != 'DELETED') LOOP
        SP_CALCULATE_USER_PROFILE(u.USER_ID);
    END LOOP;
END SP_CALCULATE_ALL_PROFILES;
/

-- ============================================================
-- Budowanie klastrow spolecznosciowych (grupy powiazan)
-- Algorytm: SOCIAL_CLUSTER_ID = MIN(USER_ID) sposrod
--           bezposrednio polaczonych przez SHARES uzytkownikow
-- ============================================================
CREATE OR REPLACE PROCEDURE SP_BUILD_SOCIAL_CLUSTERS AS
    v_cluster_id NUMBER;
BEGIN
    UPDATE USER_PROFILES SET SOCIAL_CLUSTER_ID = NULL;

    FOR u IN (SELECT USER_ID FROM USERS WHERE STATUS != 'DELETED') LOOP
        SELECT MIN(connected_user)
        INTO v_cluster_id
        FROM (
            SELECT u.USER_ID AS connected_user FROM DUAL
            UNION
            SELECT TO_USER_ID FROM SHARES
            WHERE FROM_USER_ID = u.USER_ID AND TO_USER_ID IS NOT NULL
            UNION
            SELECT FROM_USER_ID FROM SHARES
            WHERE TO_USER_ID = u.USER_ID
        );

        UPDATE USER_PROFILES
        SET SOCIAL_CLUSTER_ID = v_cluster_id
        WHERE USER_ID = u.USER_ID;
    END LOOP;

    COMMIT;
END SP_BUILD_SOCIAL_CLUSTERS;
/

-- ============================================================
-- Role i uprawnienia (uruchamiac jako DBA/ADMIN)
-- UML: Rola <|-- Admin (dostepDoWszystkiego), Rola <|-- UzytkownikWidok
-- ============================================================
-- CREATE ROLE PLATFORM_ADMIN;
-- CREATE ROLE PLATFORM_USER;
--
-- GRANT SELECT, INSERT, UPDATE, DELETE ON USERS               TO PLATFORM_ADMIN;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON POSTS               TO PLATFORM_ADMIN;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON LIKES               TO PLATFORM_ADMIN;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON COMMENTS            TO PLATFORM_ADMIN;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON SHARES              TO PLATFORM_ADMIN;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON POST_VIEWS          TO PLATFORM_ADMIN;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON USER_PROFILES       TO PLATFORM_ADMIN;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ROLES               TO PLATFORM_ADMIN;
-- GRANT SELECT ON POST_CATEGORIES             TO PLATFORM_ADMIN;
-- GRANT SELECT ON SPECIAL_ATTENTION_REASONS   TO PLATFORM_ADMIN;
-- GRANT EXECUTE ON SP_CALCULATE_USER_PROFILE  TO PLATFORM_ADMIN;
-- GRANT EXECUTE ON SP_CALCULATE_ALL_PROFILES  TO PLATFORM_ADMIN;
-- GRANT EXECUTE ON SP_BUILD_SOCIAL_CLUSTERS   TO PLATFORM_ADMIN;
-- GRANT SELECT ON V_USER_FULL_PROFILE         TO PLATFORM_ADMIN;
-- GRANT SELECT ON V_FLAGGED_POSTS             TO PLATFORM_ADMIN;
-- GRANT SELECT ON V_USER_ACTIVITY             TO PLATFORM_ADMIN;
-- GRANT SELECT ON V_MY_INTERACTIONS           TO PLATFORM_USER;
-- GRANT SELECT ON V_USER_ACTIVITY             TO PLATFORM_USER;

-- ============================================================
-- Test: przelicz profile i sprawdz wyniki
-- ============================================================
-- BEGIN SP_CALCULATE_ALL_PROFILES; END;
-- /
-- BEGIN SP_BUILD_SOCIAL_CLUSTERS; END;
-- /
-- SELECT * FROM V_USER_FULL_PROFILE;
-- SELECT * FROM V_USER_ACTIVITY;
-- SELECT * FROM V_FLAGGED_POSTS;