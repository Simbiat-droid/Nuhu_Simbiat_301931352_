# CHANGES — fixes made after testing (Nuhu Simbiat, 2026/A/MIT/0955, ReadWell Libraries)

The kit was drafted by the student's AI assistant. It was then tested on a
stock Ubuntu PostgreSQL 16 cluster plus MongoDB, set up like GitHub Codespaces:
a `codespace` user whose sudo works only as root, so `sudo -u postgres` is
refused, and no systemd. Every script ran as that user, in order: setup →
P1 → P5 → collect_results. Each problem below is what happened when the
original was run, followed by the fix and the result of re-running it. The
"tested result" numbers come from the test environment. The student's own
Codespace run produces her own numbers, which are the ones used in the
documentation.

| # | File | Problem when run | Fix | Tested result |
|---|---|---|---|---|
| 1 | setup.sh | `systemctl enable --now postgresql` under `set -e`: Codespaces has no systemd, so setup **aborted** before MongoDB was installed | `pg_ctlcluster 16 main start`; mongod started with `--fork` | DB part of setup runs; cluster online |
| 2 | setup.sh | `postgresql-16` is not packaged in every Ubuntu release; MongoDB repo forced to `jammy` (wrong on focal) | Adds apt.postgresql.org only if 16 is missing; MongoDB repo uses focal/jammy/noble as detected | Syntax-checked; apt itself needs internet (run in the student's Codespace) |
| 3 | setup.sh | `#!` line was not on line 1; `mongosh --eval "use readwell_catalog"` does nothing | Shebang first; removed; prints the MongoDB version instead | OK |
| 4 | setup.sh | No PostgreSQL role for the Codespace user and no psycopg2 (needed for the P3 two-session demo) | `createuser -s $(whoami)`; psycopg2 via pip `--user`, then the `--break-system-packages` fallback, then apt | `psycopg2 2.9` imports |
| 5 | run_p1..p5.sh | psql ran without `ON_ERROR_STOP`, so a runner printed "Done" after SQL errors; `psql -f /path` failed with **Permission denied** when postgres could not read the folder | `psql -X -v ON_ERROR_STOP=1 -f - < file` (SQL fed on stdin); each runner checks its own result | A failing SQL statement now stops the runner |
| 6 | P1 03_bulk_generator.sql | `copy.status` was `available` for all 5,000 copies, even those on loan | Status set from unreturned loans; about 1% marked lost/damaged | 1,146 copies on loan = 1,146 active loans |
| 7 | P1 03_bulk_generator.sql | 10–13 loan cap per copy plus loans force-"returned" at NOW(): only **17** loans active today, and recent months thinned out | No cap; a loan running past today stays active (overdue if past due) | 64.5k loans; 1,146 active; 236 overdue; steady months |
| 8 | P1 03_bulk_generator.sql | Identical counts (1,250 copies and 750 members per branch); `gs % n` names gave only 180 name pairs; sequential phone numbers | Weighted branches and titles; random name pairs; realistic 080/081/070/090/091 numbers | Yaba 1,580 / Ikeja 1,573 / Garki 1,121 / Kaduna 741 copies |
| 9 | P1 03_bulk_generator.sql | `reservation` table **empty**, so P2 Q6 and Q8 returned nothing | 2,500 fulfilled reservations plus open holds | 2,680 reservations; Q6 and Q8 return rows |
| 10 | P1 03_bulk_generator.sql | Members could borrow before their `joined_at` date | `joined_at` moved before the first loan | 0 loans before joining |
| 11 | P1 04_constraint_tests.sql | Tests borrowed bulk copies for past dates. With realistic history, Test C failed on the **wrong** constraint (EXCLUDE) and stopped the run | Tests create their own `TEST-` copies with no history | Tests A–G all **PASS** (8 lines) |
| 12 | P2 02_explain_before.sql | P1 had already created the loan indexes and no ANALYZE ran after the bulk load, so the BEFORE plans equalled the AFTER plans | BEFORE drops the helper indexes and runs ANALYZE; 03_indexes.sql recreates them | BEFORE shows Seq Scan on loan |
| 13 | P2 queries | Q1–Q6 aggregate the whole loan table, so indexes cannot help and the README promised index scans | Added selective Q9 (one member's history) and Q10 (desk loans, last 24 h); README now explains the results honestly | Q9 4.16→0.24 ms (17×), Q10 7.05→0.78 ms (9×), Q6 3.2×, Q3 1.9×; aggregates unchanged |
| 14 | P2 run_p2.sh | Timings had to be copied by hand | Writes `p2_timing_summary.md` from the real Execution Time lines; saves full plans | Table generated |
| 15 | P3 run_p3.sh | Race, isolation and deadlock demos were manual only, with no saved evidence | New `run_race_demos.py`: two real sessions, a thread, and a `pg_stat_activity` observer → `race_demos_output.log` | All 6 parts run; B shown BLOCKED on a lock |
| 16 | P3 race guide | "The bug" was not a real bug (the EXCLUDE constraint already caught it) | Part 1 runs the same race on a scratch table without the constraint | 2 overlapping loans of one copy (bug); Part 2 rejected by `loan_copy_id_loan_range_excl`; Part 3 B got a reservation; Part 4 SQLSTATE 40001, final 1600.00; Part 6 deadlock 40P01 |
| 17 | P4 01_schema_validation.js | `additionalProperties: false` without `_id`: MongoDB rejected **every** document, so run_p4 crashed at the smoke test | `_id` declared | Smoke docs, seed and 42,000 docs insert |
| 18 | P4 01_schema_validation.js | Per-type fields were not required (an e-book with no file format was accepted) | `oneOf` branch per itemType (`$jsonSchema` has no if/then/else); second negative test added | Both negative tests REJECTED (code 121) |
| 19 | P4 run_p4.sh / 03 | The bulk `deleteMany({})` wiped the named seed records; uniform picks gave ~4,200 docs per subject; editions "1th/2th"; "inserted undefined" | Seed loaded after bulk; skewed subjects/authors/branches; proper ordinals; counts fixed | 42,010 docs; Literature 11,608 … Biology 2,318 |
| 20 | P4 05_index_demo.js | After skewing, the demo subject would be too common for an index to help | "Computer Science" kept at ~6% of documents | COLLSCAN 42,010 docs / 30 ms → IXSCAN 2,661 docs / 7 ms |
| 21 | P5 01_partitioning.sql | `ALTER TABLE … DROP TRIGGER` is not valid SQL: P5 stopped at step 1 | `DROP TRIGGER … ON loan_old` | Runs |
| 22 | P5 01_partitioning.sql | EXCLUDE on a partitioned table is rejected by PostgreSQL 16, and with `loan_date WITH =` it would only block identical start dates | Overlap-guard trigger with a per-copy advisory lock that checks all partitions | "OVERLAP TEST PASS" |
| 23 | P5 01_partitioning.sql | `loan_old` kept the `idx_loan_*` names, so `CREATE INDEX IF NOT EXISTS` was skipped (no indexes on the new table); PK and sequence names clashed | Old indexes, PK and sequence renamed first | Partition indexes exist; pruning uses `loan_YYYYMM_loan_date_idx` |
| 24 | P5 01_partitioning.sql | `fine` still referenced `loan_old`, so fines for new loans would fail the FK | `fine.loan_date` added; FK `(loan_id, loan_date)` → partitioned loan | FK created |
| 25 | P5 01_partitioning.sql | Fixed "last 24 months" range; not safe to re-run | Partitions from the oldest loan month to +2 months, plus DEFAULT; row-count check; re-run guard | 64.5k = 64.5k rows, 0 in DEFAULT; 1 of 28 partitions scanned |
| 26 | P5 02_replica_setup.sh | `systemctl restart` (no systemd); replica config under /etc showed up as a phantom cluster; no `pg_ident.conf`; `pg_ctl -m stop` is an invalid mode; script not called by run_p5 | `pg_ctlcluster restart`; config kept in the replica data dir; ident copied, `chmod 700`; `-m fast stop`; wait for streaming; run_p5 calls it | Replica streaming on 5433 (`async`) |
| 27 | P5 03_replica_demo.sql | Only printed instructions to copy and paste | New `03_replica_demo.sh`, one script that switches servers itself → `replication_output.log` | Replica write rejected; row arrived in ~0.05 s; lag 0 bytes |
| 28 | P5 04_cloud_architecture.md | Wrong NDPA 2023 sections (9, 30, 4, 35, 14) and an invented "7-year retention under s.36"; claimed foreign hosting is "a direct breach" | s.24 principles, s.25 lawful basis, s.32 DPO, s.34 rights, s.40 breaches, ss.41–43 cross-border; retention is ReadWell's own policy | Checked against the Act's arrangement of sections |
| 29 | P5 README / cloud doc | Said EXCLUDE was kept per partition, which is false after the migration | Describes the overlap-guard trigger | — |
| 30 | All READMEs | AI sandbox paths `/home/z/my-project/download/…` | Repo-relative paths | 0 left |
| 31 | Repo | No `collect_results.sh`, `.gitignore`, references or screenshot list; PDF name with dashes | Added all four; names `Simbiat_Nuhu_Documentation.pdf` in folder `Simbiat_Nuhu_2026AMIT0955` | — |
| 32 | setup.sh | First run in the student's Codespace stopped during setup (likely `apt-get update` erroring on a broken third-party source under `set -e`; `apt-cache … | grep -q` could also misfire under pipefail) | apt update failures become a warning; PostgreSQL check no longer piped into `grep -q`; setup output saved to `~/setup_log.txt` | Syntax-checked; the Ubuntu, PostgreSQL and MongoDB sources still update |
