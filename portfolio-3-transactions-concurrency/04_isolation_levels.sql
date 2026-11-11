-- =============================================================================
-- 04_isolation_levels.sql
-- Portfolio 3 — Transactions and Concurrency
-- Student: Nuhu Simbiat · 2026/A/MIT/0955 · MIT 8103 · Miva Open University
-- Case study: ReadWell Libraries
-- =============================================================================
--
-- HOW TO USE THIS FILE
-- --------------------
-- This file is a GUIDE, not a one-shot script. Each demo needs TWO psql
-- terminals open at the same time. Run the SETUP block first (it is safe in a
-- single terminal). Then for each demo:
--   * open two terminals labelled Terminal A and Terminal B;
--   * copy-paste the SQL block labelled ">>> Terminal A <<<" into Terminal A;
--   * switch to Terminal B and copy-paste the block labelled ">>> Terminal B <<<";
--   * switch back and forth as the labels indicate.
--
-- Run setup:
--   sudo runuser -u postgres -- psql -d readwell -f 04_isolation_levels.sql
--
-- Then open two terminals:
--   sudo runuser -u postgres -- psql -d readwell
-- =============================================================================

\set ON_ERROR_STOP off

\echo '=================================================================='
\echo '  04_isolation_levels.sql'
\echo '  Demonstrates READ COMMITTED, REPEATABLE READ, SERIALIZABLE.'
\echo '  '
\echo '  This file is a GUIDE. After the SETUP block below has run,'
\echo '  open TWO psql terminals and follow the >>> Terminal A/B <<<'
\echo '  labels for each demo.'
\echo '=================================================================='

-- ============================================================================
-- SETUP (idempotent — run once in a single terminal)
-- ============================================================================
\echo ''
\echo '== [SETUP] Creating test branch, member, books, copies, an old'
\echo '          returned loan, and a fine of NGN 1 500 =='

INSERT INTO branch (branch_id, name, city)
VALUES (9301, 'Iso Branch', 'Lagos')
ON CONFLICT (branch_id) DO NOTHING;

INSERT INTO member (member_id, first_name, last_name, email, home_branch_id)
VALUES (9301, 'Iso', 'Member', 'iso.member@test.local', 9301)
ON CONFLICT (member_id) DO NOTHING;

INSERT INTO book (book_id, title, isbn, category)
VALUES (9301, 'Iso Book 1', '978-0000-9301', 'Fiction'),
       (9302, 'Iso Book 2', '978-0000-9302', 'Science')
ON CONFLICT (book_id) DO NOTHING;

INSERT INTO copy (copy_id, book_id, branch_id, barcode, status)
VALUES (9301, 9301, 9301, 'ISO-9301', 'available'),
       (9302, 9302, 9301, 'ISO-9302', 'available')
ON CONFLICT (copy_id) DO UPDATE SET book_id   = EXCLUDED.book_id,
                                     branch_id = EXCLUDED.branch_id,
                                     barcode   = EXCLUDED.barcode,
                                     status     = 'available';

-- Wipe previous demo rows
DELETE FROM fine  WHERE loan_id IN (SELECT loan_id FROM loan WHERE member_id = 9301);
DELETE FROM loan  WHERE member_id = 9301;
DELETE FROM reservation WHERE member_id = 9301;

-- Old returned loan on copy 9301 (loan_range in the past, so no overlap with NOW)
INSERT INTO loan (copy_id, member_id, loan_date, due_date, return_date)
VALUES (9301, 9301,
        NOW() - INTERVAL '30 days',
        NOW() - INTERVAL '16 days',
        NOW() - INTERVAL '5 days');

UPDATE copy SET status = 'available' WHERE copy_id = 9301;

-- Unpaid fine of NGN 1 500 (under the 2 000 block, so the member can still borrow)
INSERT INTO fine (loan_id, amount, paid)
SELECT l.loan_id, 1500.00, FALSE
  FROM loan l
 WHERE l.member_id = 9301 AND l.copy_id = 9301
   AND NOT EXISTS (SELECT 1 FROM fine f WHERE f.loan_id = l.loan_id);

\echo ''
\echo '== [SETUP state] Fine 9301 (the row we will READ and UPDATE) =='
SELECT f.fine_id, f.loan_id, f.amount, f.paid
  FROM fine f JOIN loan l ON l.loan_id = f.loan_id
 WHERE l.member_id = 9301
 ORDER BY f.fine_id;

\echo ''
\echo '== [SETUP state] Active (unreturned) loans for member 9301 =='
SELECT COUNT(*) AS active_loans
  FROM loan
 WHERE member_id = 9301 AND return_date IS NULL;

\echo ''
\echo '=================================================================='
\echo '  SETUP COMPLETE. Now open TWO psql terminals and follow the'
\echo '  >>> Terminal A <<< and >>> Terminal B <<< labels below.'
\echo '=================================================================='


-- ============================================================================
-- DEMO 1 — READ COMMITTED  (non-repeatable read is VISIBLE)
-- ============================================================================
\echo ''
\echo '=================================================================='
\echo '  DEMO 1: READ COMMITTED — non-repeatable read.'
\echo '  Terminal A reads the fine amount. Terminal B updates and commits.'
\echo '  Terminal A re-reads and SEES the new value.'
\echo '=================================================================='
\echo ''
\echo '>>> Terminal A <<<  (begin a READ COMMITTED transaction)'
\echo '    BEGIN ISOLATION LEVEL READ COMMITTED;'
\echo '    SELECT fine_id, amount FROM fine WHERE fine_id = (SELECT f.fine_id FROM fine f JOIN loan l ON l.loan_id=f.loan_id WHERE l.member_id=9301 LIMIT 1);'
\echo '    -- expected: amount = 1500.00'
\echo ''
\echo '>>> Terminal B <<<  (update the fine and commit)'
\echo '    UPDATE fine SET amount = 2000.00'
\echo '     WHERE fine_id = (SELECT f.fine_id FROM fine f JOIN loan l ON l.loan_id=f.loan_id WHERE l.member_id=9301 LIMIT 1);'
\echo '    COMMIT;'
\echo ''
\echo '>>> Terminal A <<<  (re-read the SAME row in the SAME transaction)'
\echo '    SELECT fine_id, amount FROM fine WHERE fine_id = (SELECT f.fine_id FROM fine f JOIN loan l ON l.loan_id=f.loan_id WHERE l.member_id=9301 LIMIT 1);'
\echo '    -- expected: amount = 2000.00   (NON-REPEATABLE READ — the value changed)'
\echo '    COMMIT;'

-- The next statements reproduce a value-change check inside a single session
-- when the file is run with psql -f, so the output of THIS file is meaningful
-- too. The actual non-repeatable-read DEMO is the two-terminal version above.
\echo ''
\echo '== [Single-session value-change check (illustrative)] =='
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT f.fine_id, f.amount AS amount_first_read
  FROM fine f JOIN loan l ON l.loan_id = f.loan_id
 WHERE l.member_id = 9301
 ORDER BY f.fine_id LIMIT 1;
UPDATE fine
   SET amount = 2000.00
 WHERE fine_id = (SELECT f.fine_id FROM fine f JOIN loan l ON l.loan_id=f.loan_id WHERE l.member_id=9301 LIMIT 1);
COMMIT;
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT f.fine_id, f.amount AS amount_second_read
  FROM fine f JOIN loan l ON l.loan_id = f.loan_id
 WHERE l.member_id = 9301
 ORDER BY f.fine_id LIMIT 1;
COMMIT;
-- Reset the fine amount back to 1500 so the two-terminal DEMOs below behave
-- as the \echo labels predict.
UPDATE fine
   SET amount = 1500.00
 WHERE fine_id = (SELECT f.fine_id FROM fine f JOIN loan l ON l.loan_id=f.loan_id WHERE l.member_id=9301 LIMIT 1);
\echo ''
\echo '[paste real output here]   <-- DEMO 1 two-terminal transcript (Terminal A re-read shows amount changed)'


-- ============================================================================
-- DEMO 2 — REPEATABLE READ  (phantom is HIDDEN — snapshot isolation)
-- ============================================================================
\echo ''
\echo '=================================================================='
\echo '  DEMO 2: REPEATABLE READ — phantom insert is hidden.'
\echo '  Terminal A counts active loans. Terminal B inserts one and commits.'
\echo '  Terminal A re-runs the SAME query and DOES NOT see the new row.'
\echo '=================================================================='
\echo ''
\echo '>>> Terminal A <<<  (begin a REPEATABLE READ transaction)'
\echo '    BEGIN ISOLATION LEVEL REPEATABLE READ;'
\echo '    SELECT COUNT(*) AS active_loans FROM loan WHERE member_id = 9301 AND return_date IS NULL;'
\echo '    -- expected: 0   (the only existing loan is returned)'
\echo ''
\echo '>>> Terminal B <<<  (insert a new active loan and commit)'
\echo '    BEGIN;'
\echo '    INSERT INTO loan (copy_id, member_id, loan_date, due_date)'
\echo '    VALUES (9302, 9301, NOW(), NOW() + INTERVAL ''14 days'');'
\echo '    UPDATE copy SET status = ''on_loan'' WHERE copy_id = 9302;'
\echo '    COMMIT;'
\echo ''
\echo '>>> Terminal A <<<  (re-run the SAME query in the SAME transaction)'
\echo '    SELECT COUNT(*) AS active_loans FROM loan WHERE member_id = 9301 AND return_date IS NULL;'
\echo '    -- expected: STILL 0  (snapshot isolation — phantom not visible)'
\echo '    COMMIT;'
\echo ''
\echo '>>> Terminal A <<<  (after COMMIT, a fresh query sees the new row)'
\echo '    SELECT COUNT(*) AS active_loans_now FROM loan WHERE member_id = 9301 AND return_date IS NULL;'
\echo '    -- expected: 1   (new snapshot includes Terminal B''s insert)'

\echo ''
\echo '[paste real output here]   <-- DEMO 2 two-terminal transcript (Terminal A still sees 0 then 1 after COMMIT)'


-- ============================================================================
-- DEMO 3 — SERIALIZABLE  (a conflict aborts one of the two transactions)
-- ============================================================================
\echo ''
\echo '=================================================================='
\echo '  DEMO 3: SERIALIZABLE — SSI aborts one of the two writers.'
\echo '  Both transactions read the same fine row, then both try to UPDATE it.'
\echo '  The first COMMIT succeeds; the second COMMIT fails with a'
\echo '  serialization failure.'
\echo '=================================================================='
\echo ''
\echo '>>> Terminal A <<<  (begin SERIALIZABLE, read the fine amount)'
\echo '    BEGIN ISOLATION LEVEL SERIALIZABLE;'
\echo '    SELECT f.fine_id, f.amount FROM fine f JOIN loan l ON l.loan_id=f.loan_id WHERE l.member_id=9301 LIMIT 1;'
\echo ''
\echo '>>> Terminal B <<<  (begin SERIALIZABLE, read the SAME fine amount)'
\echo '    BEGIN ISOLATION LEVEL SERIALIZABLE;'
\echo '    SELECT f.fine_id, f.amount FROM fine f JOIN loan l ON l.loan_id=f.loan_id WHERE l.member_id=9301 LIMIT 1;'
\echo ''
\echo '>>> Terminal A <<<  (UPDATE the fine and COMMIT — succeeds)'
\echo '    UPDATE fine SET amount = amount + 100'
\echo '     WHERE fine_id = (SELECT f.fine_id FROM fine f JOIN loan l ON l.loan_id=f.loan_id WHERE l.member_id=9301 LIMIT 1);'
\echo '    COMMIT;'
\echo ''
\echo '>>> Terminal B <<<  (UPDATE the same fine; the statement blocks, then succeeds; COMMIT FAILS)'
\echo '    UPDATE fine SET amount = amount + 200'
\echo '     WHERE fine_id = (SELECT f.fine_id FROM fine f JOIN loan l ON l.loan_id=f.loan_id WHERE l.member_id=9301 LIMIT 1);'
\echo '    COMMIT;'
\echo '    -- expected: ERROR: could not serialize access due to read/write dependencies among transactions'
\echo '    --            HINT: The transaction might succeed if retried.'
\echo ''
\echo '>>> Terminal B <<<  (ROLLBACK the failed transaction and verify the final value)'
\echo '    ROLLBACK;'
\echo '    SELECT f.fine_id, f.amount FROM fine f JOIN loan l ON l.loan_id=f.loan_id WHERE l.member_id=9301 LIMIT 1;'
\echo '    -- expected: amount = 1600.00   (only Terminal A''s +100 was applied)'

\echo ''
\echo '[paste real output here]   <-- DEMO 3 two-terminal transcript (Terminal B COMMIT fails with serialization error)'


-- ============================================================================
-- SUMMARY
-- ============================================================================
\echo ''
\echo '=================================================================='
\echo '  SUMMARY'
\echo '  - READ COMMITTED: each statement sees a fresh snapshot, so'
\echo '    non-repeatable reads AND phantoms are visible.'
\echo '  - REPEATABLE READ: the transaction sees a stable snapshot taken'
\echo '    at its first read; phantoms are hidden (snapshot isolation).'
\echo '  - SERIALIZABLE: PostgreSQL uses SSI to detect read/write'
\echo '    dependencies; one of two conflicting transactions is aborted'
\echo '    at COMMIT time with a serialization failure.'
\echo '=================================================================='
