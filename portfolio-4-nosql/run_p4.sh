#!/usr/bin/env bash
# Portfolio 4 — NoSQL & Advanced Data Models (MongoDB)
# Student: Nuhu Simbiat  | Matric: 2026/A/MIT/0955
# Case study: ReadWell Libraries (Lagos, Abuja, Kaduna)
#
# Run from anywhere:  bash run_p4.sh
# Prereq: mongod already started by setup.sh
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M() { echo; echo "== $2 =="; mongosh readwell_catalog --quiet --file "$DIR/$1"; }

mongosh --quiet --eval 'db.runCommand({ping:1}).ok' >/dev/null || { echo "mongod is not running - see setup.sh"; exit 1; }

M 01_schema_validation.js "Create collection + schema validation (2 negative tests)"
M 03_bulk_generator.js    "Bulk generate 42,000 documents (clears the collection first)"
M 02_seed_data.js         "Seed data (named records, inserted AFTER the bulk load so they are kept)"
M 04_aggregations.js      "Aggregations"
M 05_index_demo.js        "Index demo (COLLSCAN -> IXSCAN)"
echo "== Portfolio 4 complete =="
