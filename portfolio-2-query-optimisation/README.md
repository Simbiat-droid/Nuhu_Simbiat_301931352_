# Portfolio 2 - Query Processing and Optimisation

**Student:** Nuhu Simbiat
**Matric:** 2026/A/MIT/0955
**Programme:** BSc Computer Science - MIT 8103 Advanced Database Systems
**University:** Miva Open University

**Case study:** ReadWell Libraries - Library Book Lending (Lagos / Yaba & Ikeja, Abuja / Garki, Kaduna).

This portfolio depends on the `readwell` PostgreSQL 16 database created by Portfolio 1
(`portfolio-1-database-design/01_schema.sql` and its seed data).

---

## What this portfolio demonstrates

This portfolio shows how to **write, profile, and optimise** analytical SQL queries on the
`readwell` PostgreSQL 16 database. It contains:

- **8 analytical queries** (`01_queries.sql`) covering:
  available-copy lookup (Q1), monthly most-borrowed rankings with `RANK()` (Q2),
  overdue-loans report (Q3), unpaid-fines per member (Q4), average loan length per
  category (Q5), branch activity in the last 30 days (Q6), top-10 members in the last
  year (Q7), and most-reserved titles (Q8), plus two selective lookups added after
  testing: one member's loan history (Q9) and today's desk loans (Q10). CTEs,
  window functions, `date_trunc`, and `FILTER` clauses are used where appropriate.
- **`02_explain_before.sql`** - `EXPLAIN (ANALYZE, BUFFERS)` of Q1-Q6, Q9 and Q10 on a
  true baseline: Portfolio 1's helper indexes on `loan` are dropped first and
  statistics refreshed with `ANALYZE`, so `Seq Scan` is expected on `loan`.
- **`03_indexes.sql`** - `CREATE INDEX IF NOT EXISTS` for the indexes that speed up each
  query: a covering index on `loan(loan_date) INCLUDE (member_id, copy_id)`, partial
  indexes for overdue loans, unpaid fines and pending reservations, an expression index
  on `lower(book.title)`, a composite index on `copy(status, book_id, branch_id)`, etc.
  A `\echo` comment before each index explains which query it helps.
- **`04_explain_after.sql`** - the same `EXPLAIN (ANALYZE, BUFFERS)` statements as in
  `02_explain_before.sql`, to be run *after* `03_indexes.sql` so the student can compare
  plans and timings.
- **`p2_timing_summary.md`** (written by `run_p2.sh`) - before/after scan and real
  `Execution Time` for every explained query, plus `explain_before.txt` /
  `explain_after.txt` with the full plans. `05_results_table.md` explains the columns.

**Honest reading of the results:** Q1-Q6 aggregate most of the loan table, so even
after indexing PostgreSQL correctly keeps a `Seq Scan` / `Hash Join` (reading every
row in order is cheaper than thousands of index look-ups); their timings move only
by run-to-run noise. The indexes pay off on selective queries such as Q3 (overdue
loans), Q9 (one member) and Q10 (last 24 hours), where the plan changes to an
Index or Bitmap scan.

## Codespaces run commands

The schema and seed data must already exist (created by Portfolio 1). From this
portfolio-2 directory run:

```bash
chmod +x run_p2.sh
./run_p2.sh
```

`run_p2.sh` runs each file in order using the Unix socket (never TCP, never `sudo -u postgres`):

```bash
sudo runuser -u postgres -- psql -d readwell -f 01_queries.sql   # the analytical queries
sudo runuser -u postgres -- psql -d readwell -f 02_explain_before.sql  # EXPLAIN ANALYZE before
sudo runuser -u postgres -- psql -d readwell -f 03_indexes.sql   # create the new indexes
sudo runuser -u postgres -- psql -d readwell -f 04_explain_after.sql   # EXPLAIN ANALYZE after
```

Files can also be run individually with the same `sudo runuser -u postgres -- psql -d readwell -f <file>` command.

> **Connect via the Unix socket only.** Never use TCP logins. Never use `sudo -u postgres`; always use `sudo runuser -u postgres --`.

## What to screenshot

For each of **Q1-Q6** take **two** screenshots straight from the Codespaces terminal:

1. **Before** - the `EXPLAIN (ANALYZE, BUFFERS)` output from `02_explain_before.sql`.
   Capture the plan shape (Seq Scan / Hash Join / etc.), the `actual time`, the `rows`,
   and the `Execution Time` line at the bottom.
2. **After** - the `EXPLAIN (ANALYZE, BUFFERS)` output from `04_explain_after.sql`.
   Capture the new plan shape (Index Scan / Index Only Scan / Bitmap Heap Scan),
   the `Buffers` reads (shared hit / read), and the `Execution Time` line.

Then fill `05_results_table.md` with the real numbers and plan names. **Do not invent
timings or plan names.** Where you have not yet captured real output, leave the cell as
`[paste real output here]`.

## git commit

```bash
cd /workspaces/<your-repo>
git add portfolio-2-query-optimisation/
git commit -m "Portfolio 2: analytical queries + EXPLAIN ANALYZE before/after indexes"
git push
```

## Study session

This portfolio covers **Study Session 4: Query Optimisation - Execution Plans, Cost
Estimation, File Organisation / Indexes** of the MIT 8103 course material.
