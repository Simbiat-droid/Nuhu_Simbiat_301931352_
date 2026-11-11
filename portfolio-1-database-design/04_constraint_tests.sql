-- =============================================================================
-- 04_constraint_tests.sql
-- ReadWell Libraries - Constraint Tests (Portfolio 1)
-- Student: Nuhu Simbiat - 2026/A/MIT/0955
--
-- Each test deliberately violates a constraint declared in 01_schema.sql.
-- The violating INSERT is wrapped in BEGIN...EXCEPTION WHEN OTHERS so the
-- script keeps running. The expected outcome of every test is a PASS message;
-- a FAIL message means the constraint did NOT fire (a bug).
--
-- Tests:
--   A  EXCLUDE constraint rejects two overlapping loans on the same copy
--   B  Trigger rejects a 6th active loan for a member (max 5)
--   C  Trigger rejects a new loan when member has unpaid fines > NGN 2 000
--   D  Trigger rejects return_date before loan_date
--   E  UNIQUE constraint rejects a duplicate ISBN
--   F  CHECK constraint rejects fine.amount <= 0
--   G  Trigger auto-sets due_date = loan_date + 14 days
-- =============================================================================

-- Idempotency: clean up any test data left by a previous run.
DELETE FROM fine
 WHERE loan_id IN (SELECT loan_id FROM loan
                    WHERE member_id IN (SELECT member_id FROM member
                                         WHERE email LIKE 'test_%@example.com'));
DELETE FROM loan
 WHERE member_id IN (SELECT member_id FROM member
                      WHERE email LIKE 'test_%@example.com');
DELETE FROM member WHERE email LIKE 'test_%@example.com';
-- FIX: the tests used to borrow "free" bulk copies for dates in the past,
-- which can overlap that copy's REAL loan history and fail on the wrong
-- constraint. Each test now uses its own fresh TEST- copies (no history).
DELETE FROM fine WHERE loan_id IN (SELECT loan_id FROM loan WHERE copy_id IN
       (SELECT copy_id FROM copy WHERE barcode LIKE 'TEST-%'));
DELETE FROM loan WHERE copy_id IN (SELECT copy_id FROM copy WHERE barcode LIKE 'TEST-%');
DELETE FROM copy WHERE barcode LIKE 'TEST-%';
INSERT INTO copy (book_id, branch_id, barcode, status)
SELECT 1 + (g % 42), 1 + (g % 4), 'TEST-' || lpad(g::text, 4, '0'), 'available'
FROM generate_series(1, 15) g;
DELETE FROM book_author
 WHERE book_id IN (SELECT book_id FROM book WHERE title = 'Duplicate Test Book');
DELETE FROM book WHERE title = 'Duplicate Test Book';

\echo '=============================================================='
\echo ' ReadWell Libraries - Portfolio 1 Constraint Tests'
\echo '=============================================================='

-- =============================================================================
-- TEST A: EXCLUDE constraint rejects two OVERLAPPING loans on the same copy.
-- =============================================================================
DO $$
DECLARE
    v_copy_id    BIGINT;
    v_member_id  BIGINT;
BEGIN
    SELECT c.copy_id INTO v_copy_id
    FROM copy c
    WHERE NOT EXISTS (
        SELECT 1 FROM loan l
        WHERE l.copy_id = c.copy_id          -- FIX: no loan history at all
    ) AND c.barcode LIKE 'TEST-%'           -- FIX: the test's own copies
    ORDER BY c.copy_id LIMIT 1;

    SELECT m.member_id INTO v_member_id
    FROM member m
    WHERE (SELECT COUNT(*) FROM loan l
            WHERE l.member_id = m.member_id AND l.return_date IS NULL) < 5
      AND (SELECT COALESCE(SUM(f.amount), 0) FROM fine f
            JOIN loan l ON l.loan_id = f.loan_id
            WHERE l.member_id = m.member_id AND f.paid = FALSE) <= 2000
    ORDER BY m.member_id LIMIT 1;

    -- Setup: an active loan spanning the last 10 days (range = [NOW()-10d, NOW()+4d))
    BEGIN
        INSERT INTO loan (copy_id, member_id, loan_date, due_date, return_date, loan_range)
        VALUES (v_copy_id, v_member_id, NOW() - INTERVAL '10 days', NULL, NULL, NULL);
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'TEST A SKIP: setup loan failed: %', SQLERRM;
            RETURN;
    END;

    -- Try a SECOND overlapping loan on the same copy (starts inside the first range)
    BEGIN
        INSERT INTO loan (copy_id, member_id, loan_date, due_date, return_date, loan_range)
        VALUES (v_copy_id, v_member_id, NOW() - INTERVAL '5 days', NULL, NULL, NULL);
        RAISE NOTICE 'TEST A FAIL: overlapping loan was allowed (should have been rejected)';
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'TEST A PASS: exclusion constraint rejected overlapping loan (%)', SQLERRM;
    END;
END $$;

-- =============================================================================
-- TEST B: Trigger rejects a 6th ACTIVE loan for a member (max 5).
-- =============================================================================
DO $$
DECLARE
    v_member_id BIGINT;
    v_copies    BIGINT[];
BEGIN
    -- 6 different copies that have no active loan
    SELECT array_agg(c.copy_id ORDER BY c.copy_id) INTO v_copies
    FROM (
        SELECT c.copy_id FROM copy c
        WHERE NOT EXISTS (
            SELECT 1 FROM loan l
            WHERE l.copy_id = c.copy_id          -- FIX: no loan history at all
        ) AND c.barcode LIKE 'TEST-%'           -- FIX: the test's own copies
        ORDER BY c.copy_id LIMIT 6
    ) c;

    IF v_copies IS NULL OR array_length(v_copies, 1) < 6 THEN
        RAISE NOTICE 'TEST B SKIP: could not find 6 free copies';
        RETURN;
    END IF;

    -- Fresh member so we know exactly how many active loans they have
    INSERT INTO member (first_name, last_name, email, phone, home_branch_id, joined_at)
    VALUES ('Testb', 'User', 'test_b@example.com', '+2348090000002', 1, NOW() - INTERVAL '1 month')
    RETURNING member_id INTO v_member_id;

    -- Insert 5 active loans on 5 different copies (each copy has only 1 loan, so
    -- EXCLUDE never fires; max-active trigger fires only on the 6th)
    BEGIN
        INSERT INTO loan (copy_id, member_id, loan_date, due_date, return_date, loan_range)
        VALUES (v_copies[1], v_member_id, NOW() - INTERVAL '5 days', NULL, NULL, NULL);

        INSERT INTO loan (copy_id, member_id, loan_date, due_date, return_date, loan_range)
        VALUES (v_copies[2], v_member_id, NOW() - INTERVAL '4 days', NULL, NULL, NULL);

        INSERT INTO loan (copy_id, member_id, loan_date, due_date, return_date, loan_range)
        VALUES (v_copies[3], v_member_id, NOW() - INTERVAL '3 days', NULL, NULL, NULL);

        INSERT INTO loan (copy_id, member_id, loan_date, due_date, return_date, loan_range)
        VALUES (v_copies[4], v_member_id, NOW() - INTERVAL '2 days', NULL, NULL, NULL);

        INSERT INTO loan (copy_id, member_id, loan_date, due_date, return_date, loan_range)
        VALUES (v_copies[5], v_member_id, NOW() - INTERVAL '1 day',  NULL, NULL, NULL);
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'TEST B SKIP: setup of 5 active loans failed: %', SQLERRM;
            RETURN;
    END;

    -- Attempt the 6th active loan -> trigger should fire
    BEGIN
        INSERT INTO loan (copy_id, member_id, loan_date, due_date, return_date, loan_range)
        VALUES (v_copies[6], v_member_id, NOW(), NULL, NULL, NULL);
        RAISE NOTICE 'TEST B FAIL: 6th active loan was allowed (should have been rejected)';
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'TEST B PASS: max-5-active-loans trigger fired (%)', SQLERRM;
    END;
END $$;

-- =============================================================================
-- TEST C: Trigger blocks borrowing when member has unpaid fines > NGN 2 000.
-- =============================================================================
DO $$
DECLARE
    v_member_id BIGINT;
    v_copy_id   BIGINT;
    v_loan_id   BIGINT;
BEGIN
    SELECT c.copy_id INTO v_copy_id
    FROM copy c
    WHERE NOT EXISTS (
        SELECT 1 FROM loan l
        WHERE l.copy_id = c.copy_id          -- FIX: no loan history at all
    ) AND c.barcode LIKE 'TEST-%'           -- FIX: the test's own copies
    ORDER BY c.copy_id LIMIT 1;

    IF v_copy_id IS NULL THEN
        RAISE NOTICE 'TEST C SKIP: no free copy available';
        RETURN;
    END IF;

    -- Fresh member with zero loans and zero fines
    INSERT INTO member (first_name, last_name, email, phone, home_branch_id, joined_at)
    VALUES ('Testc', 'User', 'test_c@example.com', '+2348090000003', 2, NOW() - INTERVAL '1 month')
    RETURNING member_id INTO v_member_id;

    -- A returned loan in the past (so it is not "active" for the max-5 trigger)
    INSERT INTO loan (copy_id, member_id, loan_date, due_date, return_date, loan_range)
    VALUES (v_copy_id, v_member_id,
            NOW() - INTERVAL '60 days', NULL,
            NOW() - INTERVAL '40 days', NULL)
    RETURNING loan_id INTO v_loan_id;

    -- Unpaid fine of NGN 3 000 -> exceeds the 2 000 threshold
    INSERT INTO fine (loan_id, amount, paid, created_at, paid_at)
    VALUES (v_loan_id, 3000.00, FALSE, NOW() - INTERVAL '40 days', NULL);

    -- Attempt a new loan (on the SAME copy: the previous loan ended 40 days ago,
    -- so no EXCLUDE overlap). The unpaid-fines trigger should fire.
    BEGIN
        INSERT INTO loan (copy_id, member_id, loan_date, due_date, return_date, loan_range)
        VALUES (v_copy_id, v_member_id, NOW(), NULL, NULL, NULL);
        RAISE NOTICE 'TEST C FAIL: member with unpaid fines was allowed to borrow';
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'TEST C PASS: unpaid-fines trigger fired (%)', SQLERRM;
    END;
END $$;

-- =============================================================================
-- TEST D: Trigger rejects return_date BEFORE loan_date.
-- =============================================================================
DO $$
DECLARE
    v_copy_id   BIGINT;
    v_member_id BIGINT;
BEGIN
    SELECT c.copy_id INTO v_copy_id
    FROM copy c
    WHERE NOT EXISTS (
        SELECT 1 FROM loan l
        WHERE l.copy_id = c.copy_id          -- FIX: no loan history at all
    ) AND c.barcode LIKE 'TEST-%'           -- FIX: the test's own copies
    ORDER BY c.copy_id LIMIT 1;

    SELECT m.member_id INTO v_member_id
    FROM member m
    WHERE (SELECT COUNT(*) FROM loan l
            WHERE l.member_id = m.member_id AND l.return_date IS NULL) < 5
      AND (SELECT COALESCE(SUM(f.amount), 0) FROM fine f
            JOIN loan l ON l.loan_id = f.loan_id
            WHERE l.member_id = m.member_id AND f.paid = FALSE) <= 2000
    ORDER BY m.member_id LIMIT 1;

    IF v_copy_id IS NULL OR v_member_id IS NULL THEN
        RAISE NOTICE 'TEST D SKIP: no free copy/member';
        RETURN;
    END IF;

    -- return_date is 10 days BEFORE loan_date -> trigger must raise
    BEGIN
        INSERT INTO loan (copy_id, member_id, loan_date, due_date, return_date, loan_range)
        VALUES (v_copy_id, v_member_id,
                NOW() - INTERVAL '10 days', NULL,
                NOW() - INTERVAL '20 days', NULL);
        RAISE NOTICE 'TEST D FAIL: return_date before loan_date was allowed';
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'TEST D PASS: return_date-before-loan_date trigger fired (%)', SQLERRM;
    END;
END $$;

-- =============================================================================
-- TEST E: UNIQUE constraint rejects a duplicate ISBN.
-- =============================================================================
DO $$
DECLARE
    v_existing_isbn TEXT;
BEGIN
    SELECT isbn INTO v_existing_isbn FROM book ORDER BY book_id LIMIT 1;
    IF v_existing_isbn IS NULL THEN
        RAISE NOTICE 'TEST E SKIP: no existing book';
        RETURN;
    END IF;

    BEGIN
        INSERT INTO book (title, isbn, category, publisher, publication_year)
        VALUES ('Duplicate Test Book', v_existing_isbn, 'Fiction', 'Test Publisher', 2023);
        RAISE NOTICE 'TEST E FAIL: duplicate ISBN was allowed';
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'TEST E PASS: UNIQUE constraint rejected duplicate ISBN (%)', SQLERRM;
    END;
END $$;

-- =============================================================================
-- TEST F: CHECK constraint rejects fine.amount <= 0.
-- =============================================================================
DO $$
DECLARE
    v_loan_id BIGINT;
BEGIN
    SELECT loan_id INTO v_loan_id FROM loan ORDER BY loan_id LIMIT 1;
    IF v_loan_id IS NULL THEN
        RAISE NOTICE 'TEST F SKIP: no existing loan';
        RETURN;
    END IF;

    -- amount = 0
    BEGIN
        INSERT INTO fine (loan_id, amount, paid)
        VALUES (v_loan_id, 0.00, FALSE);
        RAISE NOTICE 'TEST F1 FAIL: fine with amount=0 was allowed';
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'TEST F1 PASS: CHECK constraint rejected fine amount=0 (%)', SQLERRM;
    END;

    -- amount = negative
    BEGIN
        INSERT INTO fine (loan_id, amount, paid)
        VALUES (v_loan_id, -100.00, FALSE);
        RAISE NOTICE 'TEST F2 FAIL: fine with negative amount was allowed';
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'TEST F2 PASS: CHECK constraint rejected negative fine (%)', SQLERRM;
    END;
END $$;

-- =============================================================================
-- TEST G: Trigger auto-sets due_date = loan_date + 14 days.
-- =============================================================================
DO $$
DECLARE
    v_copy_id    BIGINT;
    v_member_id  BIGINT;
    v_loan_id    BIGINT;
    v_loan_date  TIMESTAMPTZ;
    v_due_date   TIMESTAMPTZ;
BEGIN
    SELECT c.copy_id INTO v_copy_id
    FROM copy c
    WHERE NOT EXISTS (
        SELECT 1 FROM loan l
        WHERE l.copy_id = c.copy_id          -- FIX: no loan history at all
    ) AND c.barcode LIKE 'TEST-%'           -- FIX: the test's own copies
    ORDER BY c.copy_id LIMIT 1;

    SELECT m.member_id INTO v_member_id
    FROM member m
    WHERE (SELECT COUNT(*) FROM loan l
            WHERE l.member_id = m.member_id AND l.return_date IS NULL) < 5
      AND (SELECT COALESCE(SUM(f.amount), 0) FROM fine f
            JOIN loan l ON l.loan_id = f.loan_id
            WHERE l.member_id = m.member_id AND f.paid = FALSE) <= 2000
    ORDER BY m.member_id LIMIT 1;

    IF v_copy_id IS NULL OR v_member_id IS NULL THEN
        RAISE NOTICE 'TEST G SKIP: no free copy/member';
        RETURN;
    END IF;

    -- Insert with due_date = NULL; the trigger should set due_date = loan_date + 14 days
    INSERT INTO loan (copy_id, member_id, loan_date, due_date, return_date, loan_range)
    VALUES (v_copy_id, v_member_id, NOW() - INTERVAL '5 days', NULL, NULL, NULL)
    RETURNING loan_id, loan_date INTO v_loan_id, v_loan_date;

    SELECT due_date INTO v_due_date FROM loan WHERE loan_id = v_loan_id;

    IF v_due_date = v_loan_date + INTERVAL '14 days' THEN
        RAISE NOTICE 'TEST G PASS: due_date auto-set to loan_date + 14 days (due_date=%)', v_due_date;
    ELSE
        RAISE NOTICE 'TEST G FAIL: due_date=%, expected=%', v_due_date, v_loan_date + INTERVAL '14 days';
    END IF;
END $$;

-- =============================================================================
-- SUMMARY
-- =============================================================================
\echo '=============================================================='
\echo ' End of constraint tests. Every test above should show PASS.'
\echo ' A FAIL message means a constraint did NOT fire (a bug).'
\echo '=============================================================='
