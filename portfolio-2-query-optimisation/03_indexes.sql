-- =============================================================================
-- Portfolio 2 - Index creation script.
-- Student: Nuhu Simbiat - 2026/A/MIT/0955
-- Database: readwell (PostgreSQL 16)
--
-- Creates the indexes that speed up queries Q1-Q6 (and Q7, Q8) in
-- 01_queries.sql. Each statement uses CREATE INDEX IF NOT EXISTS so the
-- script is idempotent and can be re-run safely.
--
-- Notes on redundancy with Portfolio 1's existing indexes:
--   * Portfolio 1 already created idx_loan_return_null (member_id WHERE
--     return_date IS NULL) and idx_loan_loan_date (loan_date). The indexes
--     below add *covering* and *partial* variants targeted at the specific
--     filters/joins the analytical queries use.
--   * Portfolio 1 already created idx_fine_paid (paid WHERE paid = FALSE)
--     and idx_fine_loan (loan_id). The idx_fine_unpaid_member below is a
--     partial index keyed on loan_id, which directly serves the
--     member -> loan -> fine join in Q4.
--   * Portfolio 1 already created idx_reservation_book (book_id WHERE
--     fulfilled_at IS NULL). idx_reservation_book_pending below is the
--     same definition under a different name; CREATE INDEX IF NOT EXISTS
--     will still create it because the names differ - it is harmless but
--     redundant, kept here for parity with the task specification.
--
-- Run with:  sudo runuser -u postgres -- psql -d readwell -f 03_indexes.sql
-- =============================================================================

\echo '--- re-create the Portfolio 1 helper indexes dropped for the baseline ---'
CREATE INDEX IF NOT EXISTS idx_loan_member      ON loan(member_id);
CREATE INDEX IF NOT EXISTS idx_loan_return_null ON loan(member_id) WHERE return_date IS NULL;
CREATE INDEX IF NOT EXISTS idx_loan_loan_date   ON loan(loan_date);

\echo '--- idx_loan_copy_id : helps Q5/Q6 join loan -> copy by copy_id ---'
-- The schema does NOT already index loan(copy_id); without it every
-- loan->copy join does a Hash Join with a Seq Scan on loan.
CREATE INDEX IF NOT EXISTS idx_loan_copy_id
    ON loan (copy_id);


\echo '--- idx_loan_loan_date_covering : helps Q2, Q6, Q7 (loan_date range scans) ---'
-- Covering index: postgres can answer the loan_date >= ... filter with an
-- Index Only Scan on loan_date and still fetch member_id and copy_id from
-- the index without touching the heap. (Portfolio 1 has idx_loan_loan_date
-- without INCLUDE columns; this is its covering variant.)
CREATE INDEX IF NOT EXISTS idx_loan_loan_date_covering
    ON loan (loan_date) INCLUDE (member_id, copy_id);


\echo '--- idx_loan_member_return : helps Q7 (active loans per member) ---'
-- Partial index limited to rows whose return_date IS NULL. Lets Q7
-- (and the max-active-loans trigger) find a member's open loans with an
-- Index Only Scan. (Functionally close to Portfolio 1's idx_loan_return_null
-- but kept for parity with the task specification.)
CREATE INDEX IF NOT EXISTS idx_loan_member_return
    ON loan (member_id) WHERE return_date IS NULL;


\echo '--- idx_copy_status_book_branch : helps Q1 (status + book + branch filter) ---'
-- Composite index on the three columns Q1 filters and joins on. Because
-- status='available' is highly selective (only shelf-ready copies qualify)
-- this collapses the book -> copy lookup to a small index range scan.
CREATE INDEX IF NOT EXISTS idx_copy_status_book_branch
    ON copy (status, book_id, branch_id);


\echo '--- idx_fine_unpaid_member : helps Q4 (sum unpaid fines per member) ---'
-- Partial index on loan_id, only unpaid rows. Lets the planner satisfy
-- the WHERE paid = FALSE filter AND the join to loan without scanning the
-- whole fine table.
CREATE INDEX IF NOT EXISTS idx_fine_unpaid_member
    ON fine (loan_id) WHERE paid = FALSE;


\echo '--- idx_book_lower_title : helps Q1 (case-insensitive title lookup) ---'
-- Expression index on lower(title). Without it Q1 must lower() every row
-- of book (Seq Scan). With it, postgres does an Index Scan on the
-- expression result for the supplied :title.
CREATE INDEX IF NOT EXISTS idx_book_lower_title
    ON book (lower(title));


\echo '--- idx_book_category : helps Q5 (group by category) ---'
-- Lets the planner consider an Index Only Scan when grouping returned
-- loans by category, instead of an explicit Sort or Hash Aggregate.
CREATE INDEX IF NOT EXISTS idx_book_category
    ON book (category);


\echo '--- idx_loan_overdue : helps Q3 (overdue loans not yet returned) ---'
-- Partial index on due_date limited to loans with no return_date. Q3's
-- WHERE return_date IS NULL AND due_date < NOW() becomes an index range
-- scan on this partial index.
CREATE INDEX IF NOT EXISTS idx_loan_overdue
    ON loan (due_date) WHERE return_date IS NULL;


\echo '--- idx_reservation_book_pending : helps Q8 (pending reservations) ---'
-- Partial index on book_id limited to reservations not yet fulfilled.
-- Speeds up Q8's COUNT(reservation_id) FILTER (WHERE fulfilled_at IS NULL)
-- aggregate. (Functionally identical to Portfolio 1's idx_reservation_book;
-- kept here for parity with the task specification - it will be created
-- because the index name differs.)
CREATE INDEX IF NOT EXISTS idx_reservation_book_pending
    ON reservation (book_id) WHERE fulfilled_at IS NULL;


ANALYZE;

\echo '=============================================================='
\echo 'Index creation complete. Now run 04_explain_after.sql to capture'
\echo 'the new EXPLAIN (ANALYZE, BUFFERS) output and compare to the'
\echo 'BEFORE output captured from 02_explain_before.sql.'
\echo '=============================================================='
