-- =============================================================================
-- Portfolio 2 - EXPLAIN ANALYZE AFTER creating the new indexes.
-- Student: Nuhu Simbiat - 2026/A/MIT/0955
-- Database: readwell (PostgreSQL 16)
--
-- Runs the SAME EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) statements as
-- 02_explain_before.sql, but AFTER the indexes in 03_indexes.sql have been
-- created. Run this file *after* 03_indexes.sql so the planner can pick
-- Index Scan / Index Only Scan / Bitmap Index Scan nodes instead of
-- Seq Scan on the large tables.
--
-- Run with:  sudo runuser -u postgres -- psql -d readwell -f 04_explain_after.sql
-- =============================================================================

-- Defaults for Q1 parameters (overridable from the command line).
\if :{?title}
\else
  \set title 'Things Fall Apart'
\endif
\if :{?branch}
\else
  \set branch 'Yaba'
\endif


\echo '--- Q1 EXPLAIN ANALYZE AFTER ---'
-- Q1: available copies of a given title at a given branch.
-- Expected: Index Scan on idx_book_lower_title for the title filter, then
-- Index Scan on idx_copy_status_book_branch for the (status, book, branch)
-- lookup, instead of a Seq Scan over book and copy.
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


\echo '--- Q2 EXPLAIN ANALYZE AFTER ---'
-- Q2: most borrowed books per month, top 10 per month, last 2 years.
-- Expected: Index Only Scan on idx_loan_loan_date_covering for the
-- loan_date >= ... filter, avoiding a Seq Scan over the loan heap.
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


\echo '--- Q3 EXPLAIN ANALYZE AFTER ---'
-- Q3: overdue loans not yet returned.
-- Expected: Index Scan on idx_loan_overdue (partial on due_date WHERE
-- return_date IS NULL) instead of a Seq Scan with a filter on the full
-- loan table.
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


\echo '--- Q4 EXPLAIN ANALYZE AFTER ---'
-- Q4: members with unpaid fines (total > 0), ordered by total descending.
-- Expected: Index Only Scan on idx_fine_unpaid_member (partial on loan_id
-- WHERE paid = FALSE) instead of Seq Scan over fine with a paid = FALSE
-- filter.
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


\echo '--- Q5 EXPLAIN ANALYZE AFTER ---'
-- Q5: average loan length per book category (in days).
-- Expected: Hash Join still (loan is large), but the join to book may use
-- idx_book_category for an Index Only Scan on the book side, reducing the
-- Sort/Hash cost on the GROUP BY b.category.
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


\echo '--- Q6 EXPLAIN ANALYZE AFTER ---'
-- Q6: branch activity - total loans, active loans, reservations (30 days).
-- Expected: Index Only Scan on idx_loan_loan_date_covering for the
-- loan_date >= NOW() - INTERVAL '30 days' filter inside the loans_30 CTE,
-- and idx_loan_copy_id (or idx_copy_book_branch) for the loan -> copy join.
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
\echo '--- Q9 EXPLAIN ANALYZE AFTER ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT l.loan_id, b.title, l.loan_date::date, l.due_date::date, l.return_date::date
FROM   loan l
JOIN   copy c ON c.copy_id = l.copy_id
JOIN   book b ON b.book_id = c.book_id
WHERE  l.member_id = 1234
ORDER  BY l.loan_date DESC;

\echo '--- Q10 EXPLAIN ANALYZE AFTER ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT l.loan_id, l.member_id, l.copy_id, l.loan_date
FROM   loan l
WHERE  l.loan_date >= NOW() - INTERVAL '24 hours'
ORDER  BY l.loan_date DESC;

\echo '=============================================================='
\echo 'End of 04_explain_after.sql - copy the Execution Time line and'
\echo 'the top-level plan node into 05_results_table.md (AFTER column).'
\echo '=============================================================='
