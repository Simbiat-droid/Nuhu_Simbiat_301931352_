#!/usr/bin/env bash
# =============================================================================
# collect_results.sh - gathers the REAL output of every portfolio into ONE
# file, my_results.txt, for writing the documentation.
# Run from the repository root after the five run_pN.sh scripts:
#     bash collect_results.sh && code my_results.txt
# Nothing here is typed in - it only copies lines from the logs your own
# Codespace produced. A section saying "(no ... log)" means that portfolio
# did not run.
# =============================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/my_results.txt"
P1="$ROOT/portfolio-1-database-design"
P2="$ROOT/portfolio-2-query-optimisation"
P3="$ROOT/portfolio-3-transactions-concurrency"
P4="$ROOT/portfolio-4-nosql"
P5="$ROOT/portfolio-5-distributed-cloud"

sec() { echo; echo "######## $* ########"; }
have() { [ -s "$1" ] || { echo "(no $(basename "$1") - this part did not run)"; return 1; }; }
strip() { sed -e 's/^psql:<stdin>:[0-9]*: //'; }

{
echo "MIT 8103 CA results - Nuhu Simbiat (2026/A/MIT/0955) - ReadWell Libraries"
echo "Collected: $(date '+%Y-%m-%d %H:%M %Z')   Host: $(hostname)   User: $(whoami)"
echo "Repo: $(git -C "$ROOT" remote get-url origin 2>/dev/null || echo 'no git remote')"
echo "Commits so far: $(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 0)"
git -C "$ROOT" log --pretty='  %h %ad %s' --date=format:'%Y-%m-%d %H:%M' 2>/dev/null | head -15
echo "PostgreSQL: $(sudo runuser -u postgres -- psql -X -tAc 'SHOW server_version' 2>/dev/null)   MongoDB: $(mongosh --quiet --eval 'db.version()' 2>/dev/null)"

sec "P1 database design (p1_output.log)"
if have "$P1/p1_output.log"; then
  grep -E "TEST [A-Z0-9]+ (PASS|FAIL)" "$P1/p1_output.log" | strip
  awk '/== Row counts ==/{f=1} f' "$P1/p1_output.log"
fi

sec "P2 query optimisation (p2_timing_summary.md)"
if have "$P2/p2_timing_summary.md"; then cat "$P2/p2_timing_summary.md"; fi
sec "P2 sample query results (first rows of Q1-Q8)"
if have "$P2/p2_output.log"; then
  awk '/== EXPLAIN ANALYZE BEFORE/{exit} {print}' "$P2/p2_output.log" | grep -v '^\s*$' | awk '
    /^Q[0-9]/ {n=0; print; next} {n++; if (n<=8) print}' | head -120
fi

sec "P3 COMMIT / ROLLBACK demo (from p3_output.log)"
if have "$P3/p3_output.log"; then
  awk '/== COMMIT \/ ROLLBACK/{f=1} /== Isolation level setup/{f=0} f' "$P3/p3_output.log" | strip | grep -v '^\s*$' | head -80
fi
sec "P3 two-session demos (race_demos_output.log)"
if have "$P3/race_demos_output.log"; then cat "$P3/race_demos_output.log"; fi

sec "P4 MongoDB (p4_output.log)"
if have "$P4/p4_output.log"; then
  grep -E "REJECTED|UNEXPECTED|Error code|Inserted|In DB now|Per-type|^  (printed_book|ebook|journal|magazine|thesis)" "$P4/p4_output.log"
  awk '/== Aggregations ==/{f=1} /== Index demo/{f=0} f' "$P4/p4_output.log"
  awk '/== Index demo/{f=1} f' "$P4/p4_output.log" | grep -E "winningPlan|stage|Docs|Keys|executionTime|COLLSCAN|IXSCAN|\|" | head -60
fi

sec "P5 partitioning (p5_output.log)"
if have "$P5/p5_output.log"; then
  awk '/STEP 9/{f=1} /== 2. Streaming replica setup/{f=0} f' "$P5/p5_output.log" | strip | grep -v '^\s*$' | head -90
  grep -E "loan_old_rows" -A2 "$P5/p5_output.log"
fi
sec "P5 replication (replication_output.log)"
if have "$P5/replication_output.log"; then cat "$P5/replication_output.log"; fi

echo
echo "######## END ########"
} > "$OUT" 2>&1

echo "Wrote $OUT ($(wc -l < "$OUT") lines). Open it, Ctrl+A, Ctrl+C and paste it back."
