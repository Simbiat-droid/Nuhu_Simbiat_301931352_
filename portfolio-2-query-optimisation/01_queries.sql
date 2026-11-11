-- =============================================================================
-- Portfolio 2 - Query Processing and Optimisation
-- ReadWell Libraries - Analytical Queries
-- Student: Nuhu Simbiat - 2026/A/MIT/0955
-- Database: readwell (PostgreSQL 16)
--
-- 8 analytical queries against the schema created by Portfolio 1.
-- Dates are computed relative to NOW() so the reports stay current.
-- Run with:  sudo runuser -u postgres -- psql -d readwell -f 01_queries.sql
--
-- Override the Q1 parameters from the command line if desired, e.g.:
--   sudo runuser -u postgres -- psql -d readwell \
--       -v title='Things Fall Apart' -v branch='Yaba' -f 01_queries.sql
-- =============================================================================

-- Default parameters for Q1 (overridable via psql -v ...)
\if :{?title}
\else
  \set title 'Things Fall Apart'
\endif
\if :{?branch}
\else
  \set branch 'Yaba'
\endif


\echo '=============================================================='
\echo 'Q1 - Available copies of a given title at a given branch'
\echo '     (parameters: title = :title, branch = :branch)'
\echo '=============================================================='
-- Joins book -> copy -> branch. Filters on lower(title) and branch.name
-- so the lookup is case-insensitive. Only status = 'available' copies
-- are returned. Useful for the "can I pick this up at Yaba today?" screen.
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


\echo '=============================================================='
\echo 'Q2 - Most borrowed books per month (top 10 per month, last 2 yrs)'
\echo '=============================================================='
-- Monthly ranking of book titles by number of loans, keeping the top
-- 10 per month using RANK() inside a CTE. date_trunc groups loans into
-- calendar months; the outer filter keeps only the top-10 ranks.
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


\echo '=============================================================='
\echo 'Q3 - Overdue loans not yet returned'
\echo '=============================================================='
-- Every loan still on the shelf past its due date. Joined through
-- copy -> book and member -> branch so the report shows who owes what,
-- for which title, picked up where, and how many days overdue.
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


\echo '=============================================================='
\echo 'Q4 - Members with unpaid fines (total > 0), ordered by total'
\echo '=============================================================='
-- Sums unpaid fine.amount per member. Only rows where paid = FALSE
-- contribute. HAVING > 0 removes members who have already settled.
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


\echo '=============================================================='
\echo 'Q5 - Average loan length per book category (in days)'
\echo '=============================================================='
-- Only fully returned loans (return_date IS NOT NULL) are counted.
-- The loan length in days is computed from the interval between
-- loan_date and return_date.
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


\echo '=============================================================='
\echo 'Q6 - Branch activity: loans, active loans, reservations (30 days)'
\echo '=============================================================='
-- Two CTEs aggregate loans and reservations separately to avoid a
-- cartesian product between loan and reservation rows, then both are
-- LEFT JOINed onto branch so every branch is listed even with no
-- activity in the window.
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


\echo '=============================================================='
\echo 'Q7 - Top 10 members by number of loans in the last year'
\echo '=============================================================='
SELECT m.member_id,
       m.first_name || ' ' || m.last_name AS member_name,
       m.email,
       br.name AS home_branch,
       COUNT(l.loan_id) AS loans_count
FROM   member m
JOIN   loan   l  ON l.member_id     = m.member_id
LEFT JOIN branch br ON br.branch_id = m.home_branch_id
WHERE  l.loan_date >= NOW() - INTERVAL '1 year'
GROUP  BY m.member_id, m.first_name, m.last_name, m.email, br.name
ORDER  BY loans_count DESC, member_name
LIMIT  10;


\echo '=============================================================='
\echo 'Q8 - Books with the most reservations (titles in demand)'
\echo '=============================================================='
SELECT b.book_id,
       b.title,
       b.category,
       COUNT(r.reservation_id)                          AS total_reservations,
       COUNT(r.reservation_id) FILTER (WHERE r.fulfilled_at IS NULL) AS pending_reservations
FROM   book b
JOIN   reservation r ON r.book_id = b.book_id
GROUP  BY b.book_id, b.title, b.category
ORDER  BY total_reservations DESC, pending_reservations DESC, b.title
LIMIT  10;

\echo '=============================================================='
\echo 'Q9 - One member''s full loan history (librarian looks up member 1234)'
\echo '=============================================================='
SELECT l.loan_id, b.title, l.loan_date::date, l.due_date::date, l.return_date::date
FROM   loan l
JOIN   copy c ON c.copy_id = l.copy_id
JOIN   book b ON b.book_id = c.book_id
WHERE  l.member_id = 1234
ORDER  BY l.loan_date DESC;

\echo '=============================================================='
\echo 'Q10 - Loans issued at the desk in the last 24 hours'
\echo '=============================================================='
SELECT l.loan_id, l.member_id, l.copy_id, l.loan_date
FROM   loan l
WHERE  l.loan_date >= NOW() - INTERVAL '24 hours'
ORDER  BY l.loan_date DESC;

\echo '=============================================================='
\echo 'End of 01_queries.sql'
\echo '=============================================================='
