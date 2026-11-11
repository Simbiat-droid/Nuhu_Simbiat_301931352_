# Portfolio 2 - Before / After Index Comparison

**Student:** Nuhu Simbiat
**Matric:** 2026/A/MIT/0955
**Database:** `readwell` (PostgreSQL 16)

This document compares the `EXPLAIN (ANALYZE, BUFFERS)` output for queries Q1-Q6
**before** and **after** the indexes in `03_indexes.sql` were created.

> **Updated after testing:** `run_p2.sh` now writes `p2_timing_summary.md`
> automatically from the real `Execution Time` lines of this run (plus
> `explain_before.txt` / `explain_after.txt` with the full plans), and the
> "before" run is a true baseline (P1's helper indexes are dropped first and
> recreated by `03_indexes.sql`). Copy the numbers from that file into the
> table below, or simply refer to it. Q9 and Q10 were added as selective
> lookups, because Q1-Q6 aggregate most of the loan table and keep a Seq Scan.

## How to fill this in

1. Run `02_explain_before.sql` first and capture, for each Q1-Q6:
   - The top-level plan node (e.g. `Seq Scan`, `Hash Join`).
   - The final `Execution Time: X.XXX ms` line at the bottom of the EXPLAIN.
2. Run `03_indexes.sql` to create the new indexes.
3. Run `04_explain_after.sql` and capture, for each Q1-Q6:
   - The new top-level plan node (look for `Index Scan`, `Index Only Scan`,
     `Bitmap Heap Scan`, or `Bitmap Index Scan`).
   - The new `Execution Time: X.XXX ms` line.
4. Paste the real values into the table below, replacing the
   `[paste real output here]` placeholders. **Do NOT invent timings or plan
   names.** If a query was not run, leave the cell as `[paste real output here]`.

> Quick reference commands (Unix socket only, never TCP, never `sudo -u postgres`):
>
> ```bash
> sudo runuser -u postgres -- psql -d readwell -f 02_explain_before.sql
> sudo runuser -u postgres -- psql -d readwell -f 03_indexes.sql
> sudo runuser -u postgres -- psql -d readwell -f 04_explain_after.sql
> ```

## Comparison table

| Query | Before Index - Plan (Seq Scan?) | Before Execution Time | After Index - Plan (Index Scan?) | After Execution Time | Speedup (Before / After) |
|-------|----------------------------------|-----------------------|----------------------------------|----------------------|--------------------------|
| Q1 - Available copies of a title at a branch | [paste real output here] | [paste real output here] | [paste real output here] | [paste real output here] | [paste real output here] |
| Q2 - Most borrowed books per month (top 10, last 2 yrs) | [paste real output here] | [paste real output here] | [paste real output here] | [paste real output here] | [paste real output here] |
| Q3 - Overdue loans not yet returned | [paste real output here] | [paste real output here] | [paste real output here] | [paste real output here] | [paste real output here] |
| Q4 - Members with unpaid fines | [paste real output here] | [paste real output here] | [paste real output here] | [paste real output here] | [paste real output here] |
| Q5 - Average loan length per category | [paste real output here] | [paste real output here] | [paste real output here] | [paste real output here] | [paste real output here] |
| Q6 - Branch activity (last 30 days) | [paste real output here] | [paste real output here] | [paste real output here] | [paste real output here] | [paste real output here] |

## What to paste in each cell

- **Before Index - Plan (Seq Scan?):** The top-level plan line(s) for the query
  in `02_explain_before.sql`. Expected `Seq Scan` on at least one of `loan`,
  `copy`, `fine`, or `reservation`. Paste the line, e.g.
  `Seq Scan on public.loan  (cost=0.00..1234.56 rows=10000 ...)` or
  `Hash Join (cost=...)`.
- **Before Execution Time:** The `Execution Time: X.XXX ms` line at the end
  of the EXPLAIN output for that query in `02_explain_before.sql`.
- **After Index - Plan (Index Scan?):** The top-level plan line(s) for the
  query in `04_explain_after.sql`. Look for `Index Scan`, `Index Only Scan`,
  `Bitmap Index Scan`, or `Bitmap Heap Scan` on the newly created indexes
  (e.g. `idx_book_lower_title`, `idx_loan_overdue`, `idx_fine_unpaid_member`,
  `idx_loan_loan_date_covering`, `idx_copy_status_book_branch`,
  `idx_book_category`).
- **After Execution Time:** The `Execution Time: X.XXX ms` line at the end of
  the EXPLAIN output for that query in `04_explain_after.sql`.
- **Speedup:** Compute `Before Execution Time / After Execution Time` and round
  to 2 decimals. Example: `12.40 / 1.30 = 9.54x`.

## Sanity checks

- If the AFTER plan is *still* a `Seq Scan`, either (a) the table is too small
  for the planner to bother with an index (acceptable on tiny seed data), or
  (b) the index does not cover the predicate. Note which one in the cell.
- If the AFTER execution time is *higher* than the BEFORE (this happens on
  small tables where index lookup overhead dominates a sequential scan),
  paste the real numbers anyway and add a one-line note explaining why.
- Always paste the **real** numbers from your Codespaces terminal. Do **not**
  invent or estimate them.
