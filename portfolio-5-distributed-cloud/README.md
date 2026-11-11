# Portfolio 5 — Distributed and Cloud Database Exercise

**ReadWell Libraries** — Library Book Lending case study.
Student: **Nuhu Simbiat** — Matric **2026/A/MIT/0955** — Miva Open University, MIT 8103 Advanced Database Systems.

---

## What this portfolio demonstrates

1. **Monthly partitioning of the `loan` table** (`RANGE` on `loan_date`) —
   `loan_YYYYMM` partitions from the oldest loan month to 2 months ahead (plus a
   DEFAULT safety partition). PostgreSQL 16 cannot keep the EXCLUDE constraint
   on a partitioned table, so a trigger with a per-copy advisory lock enforces
   "no overlapping loans" across all partitions. EXPLAIN shows partition pruning.
2. **Primary + streaming read replica** for the online catalogue search —
   `pg_basebackup -R -S replica_slot` clones the primary into a hot-standby on
   port 5433.
3. **Cloud architecture that keeps data in Nigeria under NDPA 2023** — on-prem
   PostgreSQL per branch + Lagos datacentre as the PRIMARY, because there is
   no major hyperscaler region physically inside Nigeria yet.
4. **CAP & sync-vs-async trade-offs** — catalogue search is **AP** (async
   replication); loan/borrow writes are **CP** (single writer = Lagos).
5. **Branch-offline design** — when a branch loses internet it keeps serving
   catalogue reads from the local replica and queues new loans in a local
   `branch_pending_loans` spool that is replayed against the primary on
   reconnect; conflicts are caught by the overlap guard trigger.

---

## Codespaces run commands

```bash
# Portfolios 1-4 must have run first (P1 builds the readwell database).
cd portfolio-5-distributed-cloud
bash run_p5.sh 2>&1 | tee p5_output.log
```

`run_p5.sh` does everything in order and stops on the first error:

1. `01_partitioning.sql` - migrates `loan` to monthly partitions, lists them,
   runs the overlap-guard test and the partition-pruning EXPLAIN.
2. `02_replica_setup.sh` - configures the primary, clones it with
   `pg_basebackup` and starts the streaming replica on port 5433.
3. `03_replica_demo.sh` - ONE script that switches between primary and
   replica itself; its output is saved to `replication_output.log`.

All commands follow the Codespaces rules: `sudo runuser -u postgres -- ...`
(never `sudo -u postgres`), connect via the Unix socket, never TCP logins,
`pg_ctlcluster` instead of `systemctl`, and `pg_hba.conf` trust lines are
prepended to the TOP of the file.

---

## What to screenshot

Paste real terminal output (no invented output) for each of these into the
relevant file under the `[paste real output here]` markers:

1. **Partition listing** — the `SELECT ... FROM pg_inherits ...` output at the
   end of `01_partitioning.sql` showing all `loan_YYYYMM` partitions.
2. **Replica rejecting an INSERT** — on the replica, the line:
   `ERROR:  cannot execute INSERT in a read-only transaction`
   (step 2 in `replication_output.log`).
3. **New row appearing on the replica after COMMIT on primary** — step 3 in
   `replication_output.log` (the `Replica Test HHMMSS` row appears on the replica).
4. **EXPLAIN showing partition pruning** — the `EXPLAIN (ANALYZE, SUMMARY)`
   output from `01_partitioning.sql` (Step 10) AND step 5 of
   `replication_output.log`, showing only one `loan_YYYYMM` partition scanned.
5. (Bonus) `pg_stat_replication` on the primary and `pg_is_in_recovery()` on
   the replica (steps 1 and 4 of `replication_output.log`).

---

## Git commit command

```bash
cd /workspaces/<your-repo>
git add portfolio-5-distributed-cloud/
git commit -m "Portfolio 5 (Distributed & Cloud DB) - Nuhu Simbiat 2026/A/MIT/0955

- Partition loan table by month (RANGE on loan_date) with an overlap-guard trigger
  including the partition key, monthly partitions for last 24 + next 2 months
- Streaming read replica on port 5433 via pg_basebackup -R -S replica_slot
- Cloud architecture: on-prem PostgreSQL per branch + Lagos primary, NDPA 2023
  compliant (data residency inside Nigeria, DPO, 72h breach notification)
- CAP analysis: catalogue search = AP, loan writes = CP (single writer)
- Sync vs async trade-off: async streaming + local branch_pending_loans spool
- Branch-offline design: local replica keeps reads, spool replays on reconnect"
```

---

## Study sessions covered

* **Study Session 2 — Distributed DB**: horizontal partitioning / partition
  pruning, CAP theorem, ACID vs BASE, sync vs async replication, physical
  replication & WAL shipping.
* **Study Session 3 — Cloud DB**: cloud-vs-on-prem trade-off, data sovereignty
  when no hyperscaler region exists in-country.
* **Study Session 6 — Data Privacy / NDPA 2023**: data residency, data
  subject rights (access, erasure), Data Protection Officer, breach
  notification within 72 hours, encryption at rest and in transit, audit
  logging.

---

## Files in this portfolio

| File | Purpose |
| --- | --- |
| `run_p5.sh` | Driver script — partitioning, replica setup and replica demo, in order. |
| `01_partitioning.sql` | Rename `loan` → `loan_old`, create partitioned parent, monthly partitions, migrate data, EXPLAIN pruning. |
| `02_replica_setup.sh` | Called by run_p5.sh: configure primary, `pg_basebackup` clone, start replica on port 5433 with `pg_ctl`. |
| `03_replica_demo.sh` | One script, switches servers itself: who is who, read-only INSERT rejection, row arrives on replica, lag, partition pruning. |
| `03_replica_demo.sql` | Pointer to the script above plus the individual statements. |
| `04_cloud_architecture.md` | Cloud + NDPA 2023 + CAP + sync/async + branch-offline design. |
| `README.md` | This file. |
