-- =============================================================================
-- 03_bulk_generator.sql
-- ReadWell Libraries - Bulk Data Generator (Portfolio 1)
-- Student: Nuhu Simbiat - 2026/A/MIT/0955
--
-- Generates:
--   3 000 members (Nigerian first/last names from Yoruba/Igbo/Hausa pools)
--   5 000 copies (round-robin across the 42 seed books x 4 branches)
--   50 000+ loans over the last 2 years up to today (about a fifth of the
--   copies are out on loan today, some overdue), fines for late returns,
--   and reservations (fulfilled history + open holds).
--
-- All dates are RELATIVE to NOW() (NOW() - INTERVAL '2 years' ... NOW()).
-- Each copy receives 10-13 sequential non-overlapping loans, so the EXCLUDE
-- constraint never fires (no copy is ever loaned twice at once).
-- return_date is NOT NULL for almost every loan (the max-5-active trigger
-- therefore never fires); a small number of currently-outstanding loans are
-- created at the end with loan_date = NOW().
-- 95% of fines are marked paid so the unpaid-fines trigger rarely fires;
-- any loan that does trip a trigger is skipped via BEGIN/EXCEPTION.
--
-- Idempotent: TRUNCATE ONLY loan, fine, copy, member (NOT branch/book/author).
-- =============================================================================

TRUNCATE TABLE fine, loan, copy, member RESTART IDENTITY CASCADE;

-- =============================================================================
-- 1. MEMBERS (3 000)
--    Nigerian first names from Yoruba/Igbo/Hausa pools; emails built from
--    first.last+index@example.com so they are unique.
-- =============================================================================
INSERT INTO member (first_name, last_name, email, phone, home_branch_id, joined_at)
SELECT
    pick.f, pick.l,
    lower(pick.f) || '.' || lower(pick.l) || gs::text || '@example.com',
    -- FIX: real-looking 080/081/070/090 numbers, not +23480 + sequence
    '+234' || (ARRAY['80','81','70','90','91'])[1 + floor(random()*5)::int]
           || lpad(floor(random()*100000000)::text, 8, '0'),
    -- FIX: busier Lagos branches (was exactly 750 members per branch)
    CASE WHEN r < 0.34 THEN 1 WHEN r < 0.61 THEN 2 WHEN r < 0.84 THEN 3 ELSE 4 END,
    NOW() - (random() * INTERVAL '2 years')
FROM generate_series(1, 3000) AS gs
CROSS JOIN LATERAL (SELECT random() AS r, gs AS g) rr
CROSS JOIN (SELECT ARRAY[
    'Ngozi','Tunde','Aisha','Chidi','Fatima','Bola','Emeka','Zainab','Kunle','Amina',
    'Chinwe','Adamu','Yetunde','Ifeoma','Sani','Bisi','Yakubu','Hauwa','Ifeanyi',
    'Adaeze','Abubakar','Funmilayo','Yusuf','Titilayo','Idris','Damilola','Hassan',
    'Nneka','Tope','Sade','Obinna','Aisha','Chukwu','Lola','Tajudeen','Ngozi'
]::text[] AS fn) f
CROSS JOIN (SELECT ARRAY[
    'Adeyemi','Okafor','Bello','Eze','Mohammed','Oyelaran','Ibrahim','Nwosu',
    'Okonkwo','Olabisi','Sani','Adamu','Adebayo','Chukwu','Hamza','Aliyu',
    'Ogunleye','Uche','Salami','Adeleye','Onuoha','Balogun','Okoro','Lawal',
    'Musa','Eze','Abdullahi','Okafor','Oyelaran','Ibrahim'
]::text[] AS ln) l
-- FIX: random first/last name per member (gs % n gave only 180 combinations)
CROSS JOIN LATERAL (SELECT fn[1 + floor(random()*array_length(fn,1))::int] AS f,
                           ln[1 + floor(random()*array_length(ln,1))::int] AS l,
                           rr.g) pick;

-- =============================================================================
-- 2. COPIES (5 000) - enough to support 50k+ non-overlapping loans
--    book_id = round-robin over the 42 seed books (1..count(book))
--    branch_id = round-robin over the 4 branches (1..count(branch))
--    barcode = 'RW' + 8-digit zero-padded sequence
-- =============================================================================
INSERT INTO copy (book_id, branch_id, barcode, status, acquired_at)
SELECT
    -- FIX: popular titles get more copies and Lagos branches hold more stock
    -- (round-robin gave exactly 1,250 copies per branch, which looks fake)
    1 + floor(power(random(), 1.6) * bc.book_count)::int,
    CASE WHEN random() < 0.32 THEN 1 WHEN random() < 0.45 THEN 2
         WHEN random() < 0.60 THEN 3 ELSE 4 END,
    'RW' || lpad(gs::text, 8, '0'),
    'available',
    NOW() - (random() * INTERVAL '3 years')
FROM generate_series(1, 5000) AS gs
CROSS JOIN (SELECT count(*)::int AS book_count FROM book)   AS bc
CROSS JOIN (SELECT count(*)::int AS branch_count FROM branch) AS br;

-- =============================================================================
-- 3. LOANS (50 000+) - sequential non-overlapping loans per copy
--    For each copy: 10-13 loans within the last 2 years.
--    60% on-time (return between loan_date and due_date),
--    40% late (1-12 days late, fine = days_late * 50 NGN).
--    95% of fines are marked paid (so unpaid_fines trigger rarely fires).
--    Each loan INSERT is wrapped in BEGIN/EXCEPTION so any trigger failure
--    (e.g. a member with > 2 000 NGN unpaid fines) just skips that loan.
-- =============================================================================
DO $$
DECLARE
    c RECORD;
    v_loan_date    TIMESTAMPTZ;
    v_return_date  TIMESTAMPTZ;
    v_member_id    BIGINT;
    v_days_late    INT;
    v_fine_amount  NUMERIC(10,2);
    v_paid         BOOLEAN;
    v_new_loan_id  BIGINT;
    v_counter      INT;
    v_num_loans    INT;
    v_member_count INT;
    v_window_start TIMESTAMPTZ := NOW() - INTERVAL '2 years';
    v_window_end   TIMESTAMPTZ := NOW();
BEGIN
    SELECT count(*) INTO v_member_count FROM member;

    FOR c IN SELECT copy_id FROM copy ORDER BY copy_id LOOP
        -- Each copy starts its loan history at a random point in the first 30 days
        v_loan_date := v_window_start + (random() * INTERVAL '30 days');
        -- FIX: no fixed 10-13 cap. The cap made most copies stop borrowing
        -- months ago (only 17 loans were active "today"). Every copy now keeps
        -- circulating until today.
        LOOP
            EXIT WHEN v_loan_date > v_window_end;

            -- 60% on-time, 40% late
            IF random() < 0.6 THEN
                v_return_date := v_loan_date
                    + (1 + floor(random() * 14)::int) * INTERVAL '1 day';
                v_days_late := 0;
            ELSE
                v_days_late   := 1 + floor(random() * 12)::int;
                v_return_date := v_loan_date
                    + (14 + v_days_late) * INTERVAL '1 day';
            END IF;

            -- FIX: a loan whose return would be in the future is STILL ACTIVE
            -- (return_date NULL; overdue if due_date has passed). It used to be
            -- force-"returned" at exactly NOW(). No fine until it comes back.
            IF v_return_date > v_window_end THEN
                v_return_date := NULL;
                v_days_late   := 0;
            END IF;

            -- Random member (1..v_member_count)
            v_member_id := 1 + floor(random() * v_member_count)::int;

            BEGIN
                -- due_date and loan_range are NULL here; the BEFORE trigger sets them.
                INSERT INTO loan (copy_id, member_id, loan_date, due_date, return_date, loan_range)
                VALUES (c.copy_id, v_member_id, v_loan_date, NULL, v_return_date, NULL)
                RETURNING loan_id INTO v_new_loan_id;

                -- Late return -> create a fine (95% paid to keep unpaid total low)
                IF v_days_late > 0 AND v_new_loan_id IS NOT NULL THEN
                    v_fine_amount := (v_days_late * 50.00)::NUMERIC(10,2);
                    v_paid        := (random() < 0.95);
                    INSERT INTO fine (loan_id, amount, paid, created_at, paid_at)
                    VALUES (
                        v_new_loan_id,
                        v_fine_amount,
                        v_paid,
                        v_return_date + INTERVAL '1 day',
                        CASE WHEN v_paid
                             THEN v_return_date + INTERVAL '2 days'
                             ELSE NULL END
                    );
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    -- max-5-active or unpaid-fines trigger fired for this member;
                    -- skip this loan and continue with the next copy/loan.
                    RAISE NOTICE 'Skipped loan (copy %, member %): %',
                        c.copy_id, v_member_id, SQLERRM;
                    v_new_loan_id := NULL;
            END;

            -- Move to the next loan: previous return + a 30-60 day gap.
            -- This guarantees the next loan_range does not overlap the previous one.
            EXIT WHEN v_return_date IS NULL;   -- copy is out on loan today
            v_loan_date := v_return_date
                + (30 + floor(random() * 31)::int) * INTERVAL '1 day';
        END LOOP;
    END LOOP;
END $$;

-- =============================================================================
-- 4. A HANDFUL OF CURRENTLY OUTSTANDING LOANS (return_date IS NULL)
--    loan_date = NOW() so the loan_range starts after every past bulk loan's
--    range end (which is <= NOW()) - EXCLUDE constraint never fires.
--    Max-5-active and unpaid-fines triggers are pre-checked via the WHERE
--    clauses; any residual failure is caught by BEGIN/EXCEPTION.
-- =============================================================================
DO $$
DECLARE
    i             INT;
    v_copy_id     BIGINT;
    v_member_id   BIGINT;
BEGIN
    FOR i IN 1..10 LOOP
        SELECT c.copy_id INTO v_copy_id
        FROM copy c
        WHERE NOT EXISTS (
            SELECT 1 FROM loan l
            WHERE l.copy_id = c.copy_id AND l.return_date IS NULL
        )
        ORDER BY random() LIMIT 1;

        SELECT m.member_id INTO v_member_id
        FROM member m
        WHERE (
            SELECT COUNT(*) FROM loan l
            WHERE l.member_id = m.member_id AND l.return_date IS NULL
        ) < 5
        AND (
            SELECT COALESCE(SUM(f.amount), 0)
            FROM fine f JOIN loan l ON l.loan_id = f.loan_id
            WHERE l.member_id = m.member_id AND f.paid = FALSE
        ) <= 2000
        ORDER BY random() LIMIT 1;

        EXIT WHEN v_copy_id IS NULL OR v_member_id IS NULL;

        BEGIN
            INSERT INTO loan (copy_id, member_id, loan_date, due_date, return_date, loan_range)
            VALUES (v_copy_id, v_member_id, NOW(), NULL, NULL, NULL);
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'Skipped active loan (copy %, member %): %',
                    v_copy_id, v_member_id, SQLERRM;
        END;
    END LOOP;
END $$;

-- =============================================================================
-- 4b. FIX: make the rest of the data agree with the loans
-- =============================================================================
-- copy.status must say on_loan for every copy with an unreturned loan
-- (it was 'available' for all 5,000 copies even while on loan)
UPDATE copy c SET status = 'on_loan'
 WHERE EXISTS (SELECT 1 FROM loan l WHERE l.copy_id = c.copy_id AND l.return_date IS NULL);
-- about 1% of shelf copies written off as lost or damaged
UPDATE copy SET status = CASE WHEN random() < 0.6 THEN 'lost' ELSE 'damaged' END
 WHERE status = 'available' AND random() < 0.01;

-- a member cannot have borrowed before joining: pull joined_at back
UPDATE member m SET joined_at = f.first_loan - (1 + floor(random()*60)::int) * INTERVAL '1 day'
  FROM (SELECT member_id, MIN(loan_date) AS first_loan FROM loan GROUP BY member_id) f
 WHERE f.member_id = m.member_id AND m.joined_at > f.first_loan;

-- reservations (the table was EMPTY, so Q6/Q8 in Portfolio 2 returned nothing):
-- 2,500 past reservations fulfilled by a copy of that title at that branch,
-- plus open ones for titles whose copies at a branch are all out.
INSERT INTO reservation (book_id, member_id, branch_id, reserved_at, fulfilled_at, fulfilled_by_copy_id)
SELECT c.book_id, l.member_id, c.branch_id,
       l.loan_date - (1 + floor(random()*10)::int) * INTERVAL '1 day',
       l.loan_date, c.copy_id
FROM loan l JOIN copy c ON c.copy_id = l.copy_id
WHERE l.loan_date < NOW() - INTERVAL '1 day'
ORDER BY random() LIMIT 2500;

INSERT INTO reservation (book_id, member_id, branch_id, reserved_at)
SELECT x.book_id, m.member_id, x.branch_id, NOW() - (random() * INTERVAL '10 days')
FROM (SELECT book_id, branch_id FROM copy GROUP BY 1, 2
      HAVING bool_and(status <> 'available')) x
CROSS JOIN LATERAL (SELECT member_id FROM member WHERE member_id % 97 = (x.book_id + x.branch_id) % 97
                    ORDER BY random() LIMIT 3) m;
-- plus a steady trickle of open holds on the most popular titles
INSERT INTO reservation (book_id, member_id, branch_id, reserved_at)
SELECT 1 + floor(power(random(), 2) * 42)::int, 1 + floor(random() * 3000)::int,
       1 + floor(random() * 4)::int, NOW() - (random() * INTERVAL '14 days')
FROM generate_series(1, 180);

-- =============================================================================
-- 5. SUMMARY - total loans must be >= 50 000
-- =============================================================================
SELECT count(*) AS total_loans, count(*) FILTER (WHERE return_date IS NULL) AS active_loans
FROM loan;

SELECT 'members' AS table_name, count(*) FROM member
UNION ALL SELECT 'copies',       count(*) FROM copy
UNION ALL SELECT 'loans',         count(*) FROM loan
UNION ALL SELECT 'fines',         count(*) FROM fine
UNION ALL SELECT 'unpaid_fines',  count(*) FROM fine WHERE paid = FALSE
UNION ALL SELECT 'reservations',  count(*) FROM reservation
UNION ALL SELECT 'copies_on_loan', count(*) FROM copy WHERE status = 'on_loan';

-- =============================================================================
-- End of bulk generator
-- =============================================================================
