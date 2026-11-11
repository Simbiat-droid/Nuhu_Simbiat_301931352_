#!/usr/bin/env bash
# =============================================================================
# Portfolio 3 — Transactions and Concurrency
# Student: Nuhu Simbiat · 2026/A/MIT/0955 · MIT 8103 · Miva Open University
# Case study: ReadWell Libraries (PostgreSQL 16, database: readwell)
#
# Runs the single-session scripts, then run_race_demos.py, which performs the
# six two-terminal demos (bug, EXCLUDE fix, FOR UPDATE fix, SERIALIZABLE,
# READ COMMITTED vs REPEATABLE READ, deadlock) with two real sessions and
# saves the output to race_demos_output.log.
# =============================================================================
set -euo pipefail
DB=readwell
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PSQL=(sudo runuser -u postgres -- psql -X -v ON_ERROR_STOP=1 -d "$DB")
run_sql() { echo; echo "== $2 =="; "${PSQL[@]}" -f - < "$DIR/$1"; }

run_sql 01_borrow_copy_function.sql "Install borrow_copy() function"
run_sql 02_commit_rollback_demo.sql "COMMIT / ROLLBACK demo (member blocked by fines)"
run_sql 04_isolation_levels.sql     "Isolation level setup + single-session demo"

echo; echo "== Two-session concurrency demos (real output -> race_demos_output.log) =="
python3 "$DIR/run_race_demos.py" 2>&1 | tee "$DIR/race_demos_output.log"
grep -q "ALL SIX DEMOS FINISHED" "$DIR/race_demos_output.log" || { echo "race demos did not finish"; exit 1; }
echo "== Portfolio 3 complete =="
