#!/usr/bin/env bash
# =============================================================================
# run_p5.sh - Portfolio 5 driver script
# ReadWell Libraries - Distributed and Cloud Database Exercise
# Student  : Nuhu Simbiat - 2026/A/MIT/0955
# Database : readwell  (PostgreSQL 16)
# 1. monthly partitioning of loan   2. streaming read replica (port 5433)
# 3. one-script replication demo -> replication_output.log
# =============================================================================
set -euo pipefail
DB=readwell
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PSQL=(sudo runuser -u postgres -- psql -X -v ON_ERROR_STOP=1 -d "$DB")

echo "================================================================"
echo " Portfolio 5 - ReadWell Libraries (Distributed & Cloud)"
echo " Student: Nuhu Simbiat - 2026/A/MIT/0955"
echo "================================================================"

echo; echo "== 1. Partitioning loan by month =="
"${PSQL[@]}" -f - < "$DIR/01_partitioning.sql"

echo; echo "== 2. Streaming replica setup =="
bash "$DIR/02_replica_setup.sh"

echo; echo "== 3. Replication demo (saved to replication_output.log) =="
bash "$DIR/03_replica_demo.sh" 2>&1 | tee "$DIR/replication_output.log"

echo; echo "== Portfolio 5 complete. See 04_cloud_architecture.md for the design. =="
