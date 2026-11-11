-- =============================================================================
-- Portfolio 2 - EXPLAIN ANALYZE BEFORE creating the new indexes.
-- Student: Nuhu Simbiat - 2026/A/MIT/0955
-- Database: readwell (PostgreSQL 16)
--
-- Runs EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) for queries Q1-Q6, Q9 and Q10 BEFORE any
-- of the indexes in 03_indexes.sql are added. Only the indexes that already
-- exist on the schema (created by Portfolio 1) are present:
--
--   copy:           idx_copy_book_branch (book_id, branch_id)
--                   idx_copy_status      (status) WHERE status = 'available'
--   loan:           (only its PK and the EXCLUDE gist index - the P1 helper
--                   indexes are dropped below for a fair baseline)
--   reservation:    idx_reservation_book (book_id) WHERE fulfilled_at IS NULL
--                   idx_reservation_member (member_id)
--   fine:           idx_fine_paid (paid) WHERE paid = FALSE
--                   idx_fine_loan (loan_id)
--
-- On the larger tables (loan, copy, fine, reservation) expect SEQ SCAN to
-- dominate because no index yet covers the filter/join columns these queries
-- actually use (e.g. lower(book.title), loan.due_date WHERE return_date IS
-- NULL, fine.loan_id WHERE paid = FALSE, etc.).
--
-- Run with:  sudo runuser -u postgres -- psql -d readwell -f 02_explain_before.sql
-- =============================================================================

-- -----------------------------------------------------------------------------
-- FIX (tested): a TRUE baseline. Portfolio 1's schema already created
-- idx_loan_member, idx_loan_return_null and idx_loan_loan_date, so the
-- "before" and "after" plans were identical. Drop those secondary indexes
-- (and any P2 index left from an earlier run) so BEFORE really shows the
-- un-indexed plans. 03_indexes.sql recreates them all. PK / UNIQUE /
-- EXCLUDE indexes are constraints and stay. ANALYZE refreshes statistics
-- after the bulk load (the planner was guessing 460 rows for 42 books).
-- -----------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_loan_member, idx_loan_return_null, idx_loan_loan_date,
    idx_loan_copy_id, idx_loan_loan_date_covering, idx_loan_member_return,
    idx_copy_status_book_branch, idx_fine_unpaid_member, idx_book_lower_title,
    idx_book_category, idx_loan_overdue, idx_reservation_book_pending;
ANALYZE;

-- Defaults for Q1 parameters (overridable from the command line).
\if :{?title}
\else
  \set title 'Things Fall Apart'
\endif
\if :{?branch}
\else
  \set branch 'Yaba'
\endif


\echo '--- Q1 EXPLAIN ANALYZE BEFORE ---'
-- Q1: available copies of a given title at a given branch.
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT c.copy_id,
       b.title,
       b.isbn,
       b.category,
       c.barcode,
       br.name  AS branch_name,
       br.city  AS branch_city
FROM   book   b
JOIN   copy   c  ON c.book_id   = b.book_id
JOIN   branch br ON br.branch_id = c.branch_id
WHERE  lower(b.title) = lower(:'title')
  AND  br.name = :'branch'
  AND  c.status = 'available'
ORDER  BY c.copy_id;


\echo '--- Q2 EXPLAIN ANALYZE BEFORE ---'
-- Q2: most borrowed books per month, top 10 per month, last 2 years.
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
WITH monthly AS (
    SELECT date_trunc('month', l.loan_date) AS month,
           b.book_id,
           b.title,
           COUNT(*) AS borrows
    FROM   loan l
    JOIN   copy c ON c.copy_id = l.copy_id
    JOIN   book b ON b.book_id = c.book_id
    WHERE  l.loan_date >= date_trunc('month', NOW()) - INTERVAL '2 years'
    GROUP  BY date_trunc('month', l.loan_date), b.book_id, b.title
),
ranked AS (
    SELECT month,
           title,
           borrows,
           RANK() OVER (PARTITION BY month
                        ORDER BY borrows DESC, title) AS rnk
    FROM   monthly
)
SELECT month,
       rnk,
       title,
       borrows
FROM   ranked
WHERE  rnk <= 10
ORDER  BY month DESC, rnk;


\echo '--- Q3 EXPLAIN ANALYZE BEFORE ---'
-- Q3: overdue loans not yet returned.
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT l.loan_id,
       m.first_name || ' ' || m.last_name AS member_name,
       m.email,
       b.title,
       br.name AS branch_name,
       l.loan_date,
       l.due_date,
       (NOW()::date - l.due_date::date) AS days_overdue
FROM   loan   l
JOIN   copy   c  ON c.copy_id   = l.copy_id
JOIN   book   b  ON b.book_id   = c.book_id
JOIN   member m  ON m.member_id = l.member_id
JOIN   branch br ON br.branch_id = c.branch_id
WHERE  l.return_date IS NULL
  AND  l.due_date < NOW()
ORDER  BY days_overdue DESC, l.loan_id;


\echo '--- Q4 EXPLAIN ANALYZE BEFORE ---'
-- Q4: members with unpaid fines (total > 0), ordered by total descending.
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT m.member_id,
       m.first_name || ' ' || m.last_name AS member_name,
       m.email,
       COUNT(f.fine_id)  AS unpaid_fine_count,
       SUM(f.amount)     AS total_unpaid
FROM   member m
JOIN   loan   l ON l.member_id = m.member_id
JOIN   fine   f ON f.loan_id  = l.loan_id
WHERE  f.paid = FALSE
GROUP  BY m.member_id, m.first_name, m.last_name, m.email
HAVING SUM(f.amount) > 0
ORDER  BY total_unpaid DESC, member_name;


\echo '--- Q5 EXPLAIN ANALYZE BEFORE ---'
-- Q5: average loan length per book category (in days).
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT b.category,
       COUNT(l.loan_id) AS returned_loans,
       ROUND(
         AVG(EXTRACT(EPOCH FROM (l.return_date - l.loan_date)) / 86400)::numeric,
         2
       ) AS avg_loan_days
FROM   loan l
JOIN   copy c ON c.copy_id = l.copy_id
JOIN   book b ON b.book_id = c.book_id
WHERE  l.return_date IS NOT NULL
GROUP  BY b.category
ORDER  BY avg_loan_days DESC NULLS LAST, b.category;


\echo '--- Q6 EXPLAIN ANALYZE BEFORE ---'
-- Q6: branch activity - total loans, active loans, reservations (30 days).
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
WITH loans_30 AS (
    SELECT c.branch_id,
           COUNT(*)                       AS total_loans,
           COUNT(*) FILTER (WHERE l.return_date IS NULL) AS active_loans
    FROM   loan l
    JOIN   copy c ON c.copy_id = l.copy_id
    WHERE  l.loan_date >= NOW() - INTERVAL '30 days'
    GROUP  BY c.branch_id
),
res_30 AS (
    SELECT branch_id,
           COUNT(*) AS reservations
    FROM   reservation
    WHERE  reserved_at >= NOW() - INTERVAL '30 days'
    GROUP  BY branch_id
)
SELECT br.branch_id,
       br.name,
       br.city,
       COALESCE(l.total_loans, 0)  AS loans_last_30d,
       COALESCE(l.active_loans, 0) AS active_loans_30d,
       COALESCE(r.reservations, 0) AS reservations_30d
FROM   branch br
LEFT JOIN loans_30 l ON l.branch_id = br.branch_id
LEFT JOIN res_30  r ON r.branch_id = br.branch_id
ORDER  BY loans_last_30d DESC NULLS LAST, br.name;

-- Q9/Q10 (added after testing): SELECTIVE lookups. Q1-Q8 are mostly
-- whole-table aggregates where an index cannot avoid reading every loan,
-- so their timings barely change; Q9 and Q10 show where indexes do help.
\echo '--- Q9 EXPLAIN ANALYZE BEFORE ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT l.loan_id, b.title, l.loan_date::date, l.due_date::date, l.return_date::date
FROM   loan l
JOIN   copy c ON c.copy_id = l.copy_id
JOIN   book b ON b.book_id = c.book_id
WHERE  l.member_id = 1234
ORDER  BY l.loan_date DESC;

\echo '--- Q10 EXPLAIN ANALYZE BEFORE ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT l.loan_id, l.member_id, l.copy_id, l.loan_date
FROM   loan l
WHERE  l.loan_date >= NOW() - INTERVAL '24 hours'
ORDER  BY l.loan_date DESC;

\echo '=============================================================='
\echo 'End of 02_explain_before.sql - copy the Execution Time line and'
\echo 'the top-level plan node into 05_results_table.md (BEFORE column).'
\echo '=============================================================='
