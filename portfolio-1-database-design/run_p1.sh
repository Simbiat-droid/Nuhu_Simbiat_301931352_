#!/usr/bin/env bash
# =============================================================================
# run_p1.sh - Portfolio 1 runner for ReadWell Libraries DB.
# Student: Nuhu Simbiat - 2026/A/MIT/0955
# Loads schema -> seed -> bulk -> constraint tests -> prints row counts.
# Stops on the first SQL error (ON_ERROR_STOP) so it can never print "Done"
# after a failure. SQL is fed on stdin, so the postgres user does not need
# read permission on the Codespace folder.
# =============================================================================
set -euo pipefail
DB=readwell
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PSQL=(sudo runuser -u postgres -- psql -X -v ON_ERROR_STOP=1 -d "$DB")
run_sql() { echo; echo "== $2 =="; "${PSQL[@]}" -f - < "$DIR/$1"; }

run_sql 01_schema.sql         "Loading schema"
run_sql 02_seed_data.sql      "Seed data"
run_sql 03_bulk_generator.sql "Bulk data (50k+ loans) - takes 1-3 minutes"
run_sql 04_constraint_tests.sql "Constraint tests (every test must print PASS)"

echo; echo "== Row counts =="
"${PSQL[@]}" -c "SELECT 'branch' t, count(*) FROM branch UNION ALL SELECT 'author', count(*) FROM author
 UNION ALL SELECT 'book', count(*) FROM book UNION ALL SELECT 'book_author', count(*) FROM book_author
 UNION ALL SELECT 'copy', count(*) FROM copy UNION ALL SELECT 'member', count(*) FROM member
 UNION ALL SELECT 'loan', count(*) FROM loan UNION ALL SELECT 'fine', count(*) FROM fine
 UNION ALL SELECT 'reservation', count(*) FROM reservation;"

echo "== Data sanity checks (all should look realistic) =="
"${PSQL[@]}" -c "SELECT b.name AS branch, count(c.*) AS copies,
        count(*) FILTER (WHERE c.status='on_loan') AS on_loan_today
   FROM branch b LEFT JOIN copy c ON c.branch_id=b.branch_id
  WHERE b.branch_id <= 4 GROUP BY b.branch_id, b.name ORDER BY b.branch_id;"
"${PSQL[@]}" -c "SELECT count(*) FILTER (WHERE return_date IS NULL) AS active_loans,
        count(*) FILTER (WHERE return_date IS NULL AND due_date < now()) AS overdue_now,
        min(loan_date)::date AS first_loan, max(loan_date)::date AS latest_loan
   FROM loan;"

N=$("${PSQL[@]}" -At -c "SELECT count(*) FROM loan")
if [ "$N" -lt 50000 ]; then echo "FAIL: only $N loans (need 50,000+)"; exit 1; fi
echo "== Portfolio 1 complete: $N loans =="
