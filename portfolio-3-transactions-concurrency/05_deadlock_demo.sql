-- =============================================================================
-- 05_deadlock_demo.sql
-- Portfolio 3 — Transactions and Concurrency
-- Student: Nuhu Simbiat · 2026/A/MIT/0955 · MIT 8103 · Miva Open University
-- Case study: ReadWell Libraries
-- =============================================================================
--
-- HOW TO USE THIS FILE
-- --------------------
-- This file is a GUIDE. After the SETUP block has run (single terminal), open
-- TWO psql terminals and follow the >>> Terminal A/B <<< labels in order.
--
-- Story
-- -----
--   Session A locks copy 1, then asks for copy 2.
--   Session B locks copy 2, then asks for copy 1.
--   Neither can proceed; PostgreSQL detects the wait-cycle and aborts ONE of
--   the transactions with:
--       ERROR: deadlock detected
--
-- Run setup:
--   sudo runuser -u postgres -- psql -d readwell -f 05_deadlock_demo.sql
--
-- Then open two terminals:
--   sudo runuser -u postgres -- psql -d readwell
-- =============================================================================

\set ON_ERROR_STOP off

\echo '=================================================================='
\echo '  05_deadlock_demo.sql'
\echo '  Two sessions deadlock on copies 9201 and 9202.'
\echo '  PostgreSQL detects the cycle and aborts one of them.'
\echo '=================================================================='

-- ============================================================================
-- SETUP (idempotent — run once in a single terminal)
-- ============================================================================
\echo ''
\echo '== [SETUP] Creating test branch, two books, and two copies =='

INSERT INTO branch (branch_id, name, city)
VALUES (9201, 'Deadlock Branch', 'Abuja')
ON CONFLICT (branch_id) DO NOTHING;

INSERT INTO book (book_id, title, isbn, category)
VALUES (9201, 'Deadlock Book 1', '978-0000-9201', 'Fiction'),
       (9202, 'Deadlock Book 2', '978-0000-9202', 'History')
ON CONFLICT (book_id) DO NOTHING;

INSERT INTO copy (copy_id, book_id, branch_id, barcode, status)
VALUES (9201, 9201, 9201, 'DL-9201', 'available'),
       (9202, 9202, 9201, 'DL-9202', 'available')
ON CONFLICT (copy_id) DO UPDATE SET book_id   = EXCLUDED.book_id,
                                     branch_id = EXCLUDED.branch_id,
                                     barcode   = EXCLUDED.barcode,
                                     status     = 'available';

\echo ''
\echo '== [SETUP state] Copies 9201 and 9202 =='
SELECT copy_id, book_id, branch_id, status FROM copy WHERE copy_id IN (9201, 9202) ORDER BY copy_id;

\echo ''
\echo '=================================================================='
\echo '  SETUP COMPLETE. Open TWO psql terminals and follow the'
\echo '  >>> Terminal A/B <<< labels in EXACTLY the order shown.'
\echo '=================================================================='


-- ============================================================================
-- THE DEADLOCK
-- ============================================================================
\echo ''
\echo '=================================================================='
\echo '  THE DEADLOCK'
\echo '  Order matters — type the commands one terminal at a time,'
\echo '  exactly as labelled.'
\echo '=================================================================='

\echo ''
\echo '>>> STEP 1 — Terminal A <<<  (begin, lock copy 9201)'
\echo '    BEGIN;'
\echo '    SELECT copy_id, status FROM copy WHERE copy_id = 9201 FOR UPDATE;'
\echo '    -- returns the row immediately, A now holds the lock on 9201.'

\echo ''
\echo '>>> STEP 2 — Terminal B <<<  (begin, lock copy 9202)'
\echo '    BEGIN;'
\echo '    SELECT copy_id, status FROM copy WHERE copy_id = 9202 FOR UPDATE;'
\echo '    -- returns the row immediately, B now holds the lock on 9202.'

\echo ''
\echo '>>> STEP 3 — Terminal A <<<  (ask for copy 9202 — BLOCKS)'
\echo '    SELECT copy_id, status FROM copy WHERE copy_id = 9202 FOR UPDATE;'
\echo '    -- this BLOCKS, because Terminal B holds the lock on 9202.'
\echo '    -- do NOT type anything else here yet; switch to Terminal B.'

\echo ''
\echo '>>> STEP 4 — Terminal B <<<  (ask for copy 9201 — DEADLOCK fires)'
\echo '    SELECT copy_id, status FROM copy WHERE copy_id = 9201 FOR UPDATE;'
\echo '    -- PostgreSQL detects the wait cycle:'
\echo '    --     A waits for B (step 3)'
\echo '    --     B waits for A (this step)'
\echo '    -- One of the two sessions is killed with:'
\echo '    --     ERROR:  deadlock detected'
\echo '    -- The OTHER session''s blocked SELECT then runs to completion.'

\echo ''
\echo '>>> STEP 5 — Both terminals: clean up <<<'
\echo '    The aborted transaction must ROLLBACK; the surviving one COMMITs.'
\echo '    -- In whichever terminal got the ERROR:'
\echo '    ROLLBACK;'
\echo '    -- In the OTHER terminal (the one whose SELECT just returned):'
\echo '    COMMIT;'

\echo ''
\echo '>>> STEP 6 — Verify final state <<<'
\echo '    (run in either terminal)'
\echo '    SELECT copy_id, status FROM copy WHERE copy_id IN (9201, 9202) ORDER BY copy_id;'
\echo '    -- expected: both copies still ''available'' — the SELECTs FOR UPDATE'
\echo '    -- did not change any data.'

\echo ''
\echo '=================================================================='
\echo '  EXPECTED OUTPUT'
\echo '=================================================================='
\echo ''
\echo 'The session that LOST the deadlock sees (in psql):'
\echo ''
\echo '    ERROR:  deadlock detected'
\echo '    DETAIL:  Process <pid_A> waits for ShareLock on transaction <xid_B>; blocked by process <pid_B>.'
\echo '    Process <pid_B> waits for ShareLock on transaction <xid_A>; blocked by process <pid_A>.'
\echo '    HINT:  See server log for query details.'
\echo '    CONTEXT:  while locking tuple (<block>,<offset>) in relation "copy"'
\echo ''
\echo 'The OTHER session sees its previously-blocked SELECT return:'
\echo ''
\echo '     copy_id |  status'
\echo '    ---------+----------'
\echo '        9201 | available     (or 9202, depending on which session won)'
\echo '    (1 row)'
\echo ''
\echo '[paste real output here]   <-- the deadlock ERROR from the losing terminal'
\echo '[paste real output here]   <-- the SELECT returning from the winning terminal after the deadlock was resolved'

\echo ''
\echo '=================================================================='
\echo '  POSTGRESQL SERVER LOG LINE'
\echo '=================================================================='
\echo ''
\echo 'The PostgreSQL server log adds a line that names BOTH processes and the'
\echo 'exact statement that triggered the deadlock. On this Codespaces box the'
\echo 'log is typically at:'
\echo ''
\echo '    /var/log/postgresql/postgresql-16-main.log'
\echo ''
\echo 'Inspect the most recent deadlock entry with (run in your shell, NOT psql):'
\echo ''
\echo '    sudo tail -n 200 /var/log/postgresql/postgresql-16-main.log | grep -A2 -B2 deadlock'
\echo ''
\echo 'A typical log line looks like:'
\echo ''
\echo '    LOG:  process <pid> detected deadlock while waiting for ShareLock on'
\echo '          transaction <xid> after 1000.000 ms'
\echo '    DETAIL:  Process holding the lock: <other_pid>. Wait queue: .'
\echo '    CONTEXT:  while locking tuple (<block>,<offset>) in relation "copy"'
\echo '    STATEMENT:  SELECT copy_id, status FROM copy WHERE copy_id = 9201 FOR UPDATE;'
\echo ''
\echo '[paste real output here]   <-- the PostgreSQL server log line about the deadlock'

\echo ''
\echo '=================================================================='
\echo '  WHY THIS HAPPENS'
\echo '  - A holds a row lock on 9201 and wants 9202.'
\echo '  - B holds a row lock on 9202 and wants 9201.'
\echo '  - The wait-for graph has a cycle: A -> B -> A.'
\echo '  - PostgreSQL runs a background deadlock detector (default'
\echo '    deadlock_timeout = 1 s). Once it fires, it picks one transaction'
\echo '    to abort so the other can proceed.'
\echo '  - In real application code the fix is to ALWAYS lock shared resources'
\echo '    in a consistent order (e.g. always lock the lower copy_id first).'
\echo '=================================================================='

\echo ''
\echo '== [Optional cleanup] =='
\echo '    DELETE FROM copy   WHERE copy_id IN (9201, 9202);'
\echo '    DELETE FROM book   WHERE book_id IN (9201, 9202);'
\echo '    DELETE FROM branch WHERE branch_id = 9201;'
