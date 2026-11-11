-- =============================================================================
-- 02_commit_rollback_demo.sql
-- Portfolio 3 — Transactions and Concurrency
-- Student: Nuhu Simbiat · 2026/A/MIT/0955 · MIT 8103 · Miva Open University
-- Case study: ReadWell Libraries
-- =============================================================================
--
-- Demonstrates COMMIT and ROLLBACK driven by the schema's own consistency
-- triggers.
--
-- Story
-- -----
--   Member 9001 (Finbarr Okafor) has an UNPAID fine of NGN 2 500 attached to
--   an OLD loan that has already been returned. The Portfolio 1 trigger
--   `trg_check_unpaid_fines` blocks any new loan while unpaid fines exceed
--   NGN 2 000.
--
--   STEP 1: BEGIN; attempt INSERT INTO loan for the member.
--          The trigger fires -> the statement fails.
--          We wrap the INSERT in a DO $$ ... EXCEPTION WHEN OTHERS ... $$
--          so the script keeps going, then ROLLBACK the outer transaction.
--
--   STEP 2: pay the fine (UPDATE fine SET paid=TRUE, paid_at=NOW()).
--          BEGIN; attempt the same INSERT again -> COMMIT succeeds.
--
-- Run with:
--   sudo runuser -u postgres -- psql -d readwell -f 02_commit_rollback_demo.sql
-- =============================================================================

\set ON_ERROR_STOP off

\echo '============================================================'
\echo ' 02 - COMMIT / ROLLBACK demo: member blocked by unpaid fines'
\echo '============================================================'

-- ============================================================================
-- SETUP: idempotent test data
-- ============================================================================
\echo ''
\echo '== [Setup] Creating test branch, member, book, two copies, an old'
\echo '          returned loan, and an UNPAID fine of NGN 2 500 =='

-- Branch 9001
INSERT INTO branch (branch_id, name, city, address, phone)
VALUES (9001, 'P3 Test Branch', 'Lagos', '1 Test Street, Yaba', '08000000000')
ON CONFLICT (branch_id) DO NOTHING;

-- Member 9001 (home branch 9001)
INSERT INTO member (member_id, first_name, last_name, email, phone, home_branch_id)
VALUES (9001, 'Finbarr', 'Okafor', 'finbarr.p3@test.local', '08011111111', 9001)
ON CONFLICT (member_id) DO NOTHING;

-- Book 9001
INSERT INTO book (book_id, title, isbn, category, publisher, publication_year)
VALUES (9001, 'P3 Test Title', '978-0000-9001', 'Fiction', 'Test Publisher', 2020)
ON CONFLICT (book_id) DO NOTHING;

-- Copy 9001  -> used for the OLD returned loan (which carries the unpaid fine).
-- Copy 9002  -> the available copy the member will try to borrow.
INSERT INTO copy (copy_id, book_id, branch_id, barcode, status)
VALUES (9001, 9001, 9001, 'P3-OLD-9001', 'available')
ON CONFLICT (copy_id) DO UPDATE SET book_id   = EXCLUDED.book_id,
                                     branch_id = EXCLUDED.branch_id,
                                     barcode   = EXCLUDED.barcode,
                                     status     = 'available';
INSERT INTO copy (copy_id, book_id, branch_id, barcode, status)
VALUES (9002, 9001, 9001, 'P3-NEW-9002', 'available')
ON CONFLICT (copy_id) DO UPDATE SET book_id   = EXCLUDED.book_id,
                                     branch_id = EXCLUDED.branch_id,
                                     barcode   = EXCLUDED.barcode,
                                     status     = 'available';

-- Wipe any previous demo rows so this script is idempotent.
DELETE FROM fine  WHERE loan_id IN (SELECT loan_id FROM loan WHERE member_id = 9001);
DELETE FROM loan  WHERE member_id = 9001;
DELETE FROM reservation WHERE member_id = 9001;

-- Old returned loan on copy 9001.
-- loan_range = [NOW-30d, NOW-5d)  -> entirely in the past, no overlap with any
-- new loan starting at NOW().
INSERT INTO loan (copy_id, member_id, loan_date, due_date, return_date)
VALUES (9001, 9001,
        NOW() - INTERVAL '30 days',          -- loan_date
        NOW() - INTERVAL '16 days',          -- due_date  (loan_date + 14d)
        NOW() - INTERVAL '5 days');          -- return_date (5 days after due -> late)

-- copy 9001 is now physically back on the shelf (returned).
UPDATE copy SET status = 'available' WHERE copy_id = 9001;

-- Unpaid fine of NGN 2 500 on the old loan (above the NGN 2 000 block threshold).
INSERT INTO fine (loan_id, amount, paid)
SELECT l.loan_id, 2500.00, FALSE
  FROM loan l
 WHERE l.member_id = 9001 AND l.copy_id = 9001
   AND NOT EXISTS (SELECT 1 FROM fine f WHERE f.loan_id = l.loan_id);

\echo ''
\echo '== [Setup state] Member 9001 unpaid fines (should be NGN 2500.00) =='
SELECT COALESCE(SUM(f.amount), 0) AS total_unpaid
  FROM fine f JOIN loan l ON l.loan_id = f.loan_id
 WHERE l.member_id = 9001 AND f.paid = FALSE;

\echo ''
\echo '== [Setup state] Copies available for book 9001 at branch 9001 =='
SELECT copy_id, barcode, status FROM copy WHERE book_id = 9001 AND branch_id = 9001 ORDER BY copy_id;

-- ============================================================================
-- STEP 1: BLOCKED BORROW ATTEMPT -> ROLLBACK
-- ============================================================================
\echo ''
\echo '============================================================'
\echo ' STEP 1: BEGIN; attempt INSERT INTO loan for member 9001,'
\echo '         copy 9002. The trg_check_unpaid_fines trigger should'
\echo '         fire and abort the INSERT. We wrap it in a DO block'
\echo '         with EXCEPTION WHEN OTHERS so the script continues,'
\echo '         then ROLLBACK the outer transaction.'
\echo '============================================================'

BEGIN;

DO $$
DECLARE
    v_loan_id BIGINT;
BEGIN
    INSERT INTO loan (copy_id, member_id, loan_date, due_date)
    VALUES (9002, 9001, NOW(), NOW() + INTERVAL '14 days')
    RETURNING loan_id INTO v_loan_id;

    -- If we reach here, the trigger did NOT block -> unexpected.
    RAISE NOTICE 'Loan inserted with loan_id=% (UNEXPECTED - the trigger should have blocked this)', v_loan_id;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;

\echo ''
\echo '== [After step 1] Loans for member 9001 (should still be ONLY the old loan) =='
SELECT loan_id, copy_id, loan_date::TEXT AS loan_date, return_date::TEXT AS return_date
  FROM loan WHERE member_id = 9001 ORDER BY loan_id;

-- Discard the (empty) outer transaction. This is the ROLLBACK half of the demo.
ROLLBACK;

\echo ''
\echo '== [After ROLLBACK] No new loan was committed. =='

-- ============================================================================
-- STEP 2: PAY THE FINE -> COMMIT SUCCEEDS
-- ============================================================================
\echo ''
\echo '============================================================'
\echo ' STEP 2: Pay the unpaid fine for member 9001.'
\echo '         Then BEGIN; attempt the same loan; COMMIT succeeds.'
\echo '============================================================'

\echo ''
\echo '== [Before payment] unpaid fines for member 9001 =='
SELECT f.fine_id, f.loan_id, f.amount, f.paid
  FROM fine f JOIN loan l ON l.loan_id = f.loan_id
 WHERE l.member_id = 9001 AND f.paid = FALSE
 ORDER BY f.fine_id;

\echo ''
\echo '== Paying the fine (UPDATE fine SET paid=TRUE, paid_at=NOW()) =='
UPDATE fine
   SET paid = TRUE,
       paid_at = NOW()
 WHERE paid = FALSE
   AND loan_id IN (SELECT loan_id FROM loan WHERE member_id = 9001);

\echo ''
\echo '== [After payment] Member 9001 unpaid fines (should be 0) =='
SELECT COALESCE(SUM(f.amount), 0) AS total_unpaid
  FROM fine f JOIN loan l ON l.loan_id = f.loan_id
 WHERE l.member_id = 9001 AND f.paid = FALSE;

\echo ''
\echo '== BEGIN; INSERT the new loan for copy 9002; UPDATE copy status; COMMIT =='
BEGIN;
INSERT INTO loan (copy_id, member_id, loan_date, due_date)
VALUES (9002, 9001, NOW(), NOW() + INTERVAL '14 days');
UPDATE copy SET status = 'on_loan' WHERE copy_id = 9002;
COMMIT;

\echo ''
\echo '== [After COMMIT] Loans for member 9001 (now TWO rows: old + new) =='
SELECT loan_id, copy_id, loan_date::TEXT AS loan_date,
       due_date::TEXT AS due_date, return_date::TEXT AS return_date
  FROM loan WHERE member_id = 9001 ORDER BY loan_id;

\echo ''
\echo '== [After COMMIT] Copies of book 9001 at branch 9001 (9001=available, 9002=on_loan) =='
SELECT copy_id, barcode, status FROM copy WHERE book_id = 9001 AND branch_id = 9001 ORDER BY copy_id;

\echo ''
\echo '============================================================'
\echo ' DEMO COMPLETE.'
\echo '   - STEP 1: trigger blocked the loan -> ROLLBACK.'
\echo '   - STEP 2: fine paid -> COMMIT succeeded.'
\echo '============================================================'
