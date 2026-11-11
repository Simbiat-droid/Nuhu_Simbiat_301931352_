# Portfolio 3 — Transactions and Concurrency


> **After testing:** `bash run_p3.sh` now runs everything, including the
> six two-terminal demos via `run_race_demos.py` (two real sessions + a
> thread). Real output: `p3_output.log` and `race_demos_output.log`.
> Part 1 bug, Part 2 EXCLUDE fix, Part 3 `SELECT ... FOR UPDATE` fix,
> Part 4 SERIALIZABLE, Part 5 READ COMMITTED vs REPEATABLE READ, Part 6 deadlock.
**Student:** Nuhu Simbiat · **Matric:** 2026/A/MIT/0955 · **Course:** MIT 8103 Advanced Database Systems
**Institution:** Miva Open University
**Case study:** Library Book Lending for ReadWell Libraries
**Database:** `readwell` (PostgreSQL 16) — schema created by Portfolio 1.

---

## What this portfolio demonstrates

1. **`borrow_copy()` transaction with `COMMIT` / `ROLLBACK`**
   A PL/pgSQL function (`01_borrow_copy_function.sql`) that, inside the caller's
   transaction, locks one available `copy` row with `SELECT ... FOR UPDATE`,
   inserts a `loan`, flips the `copy.status` to `on_loan`, and `COMMIT`s. If no
   free copy exists, it inserts a `reservation` instead. Failure paths roll back
   via an `EXCEPTION WHEN OTHERS` block.

2. **COMMIT / ROLLBACK demo** (`02_commit_rollback_demo.sql`)
   A member with an unpaid fine > NGN 2 000 is blocked by the
   `trg_check_unpaid_fines` trigger. The blocked `INSERT` is wrapped in a
   `DO $$ ... EXCEPTION WHEN OTHERS ... $$` block so the script keeps running;
   the outer transaction is `ROLLBACK`ed. After paying the fine, the same
   `INSERT` + `COMMIT` succeeds.

3. **A two-terminal race condition with two fixes** (`03_race_condition_guide.md`)
   Two members grab the *last* available copy of a title at the same branch:
   - **The bug:** neither session uses `SELECT FOR UPDATE` and neither is aware
     of the exclusion constraint. Both read `status='available'`, both attempt
     `INSERT INTO loan ...` for the same copy.
   - **Fix 1:** the existing `EXCLUDE USING gist (copy_id WITH =, loan_range WITH &&)`
     on `loan` rejects the second `INSERT` (Terminal B blocks on the GiST index
     entry held by Terminal A's uncommitted loan, then fails once A commits).
   - **Fix 2:** the `borrow_copy()` function uses `SELECT ... FOR UPDATE` on the
     `copy` row, so Terminal B *waits* for Terminal A; when A commits, B's
     `SELECT` no longer matches a row (`status='on_loan'`), so B falls through
     to the reservation branch and returns `NULL` ("reserved for you").

4. **Isolation levels** (`04_isolation_levels.sql`)
   READ COMMITTED (non-repeatable read visible), REPEATABLE READ (snapshot
   isolation hides another session's insert), SERIALIZABLE (one of two
   conflicting transactions aborts with a serialization failure).

5. **Deadlock demo** (`05_deadlock_demo.sql`)
   Session A locks copy 1 then asks for copy 2; Session B locks copy 2 then
   asks for copy 1. PostgreSQL detects the cycle and aborts one transaction
   with `ERROR: deadlock detected`.

---

## Codespaces run commands

All commands use the **Unix socket** and the project-mandated `sudo runuser -u postgres` form.
**Never** use `sudo -u postgres` and **never** use a TCP login.

```bash
# One-shot: install the function + run the COMMIT/ROLLBACK demo + isolation levels
cd /workspaces/<your-repo>/portfolio-3-transactions-concurrency
bash run_p3.sh
```

Or step by step:

```bash
# 1. Install borrow_copy()
sudo runuser -u postgres -- psql -d readwell -f 01_borrow_copy_function.sql

# 2. COMMIT / ROLLBACK demo (single terminal)
sudo runuser -u postgres -- psql -d readwell -f 02_commit_rollback_demo.sql

# 3. Isolation levels (run each block in the labelled terminal)
sudo runuser -u postgres -- psql -d readwell -f 04_isolation_levels.sql

# 4. Deadlock (two terminals — follow the \echo instructions in the file)
sudo runuser -u postgres -- psql -d readwell -f 05_deadlock_demo.sql
```

For the two-terminal demos, open two psql sessions side by side:

```bash
# Terminal A
sudo runuser -u postgres -- psql -d readwell

# Terminal B
sudo runuser -u postgres -- psql -d readwell
```

Then follow `03_race_condition_guide.md` (race + two fixes) and the instructions
inside `05_deadlock_demo.sql` (deadlock).

---

## What to screenshot

| # | Screenshot subject | Where it comes from |
|---|--------------------|---------------------|
| 1 | The `ROLLBACK` error message (unpaid-fines trigger firing) | `02_commit_rollback_demo.sql` output, STEP 1 `RAISE NOTICE` |
| 2 | The race-condition bug: BOTH sessions think they borrowed the copy | `03_race_condition_guide.md` → "THE BUG", Terminal A commit + Terminal B error |
| 3 | **Fix 1:** the `EXCLUDE` exclusion-constraint error in Terminal B | `03_race_condition_guide.md` → "FIX 1", Terminal B transcript |
| 4 | **Fix 2:** Terminal B waits on `FOR UPDATE`, then returns `NULL` ("reserved for you") and a `reservation` row appears | `03_race_condition_guide.md` → "FIX 2", both terminals |
| 5 | The deadlock error log (`ERROR: deadlock detected`) | `05_deadlock_demo.sql`, the transaction that lost the deadlock |

Replace each `[paste real output here]` placeholder in the SQL / Markdown
files with the actual psql output before submitting.

---

## Git commit command

```bash
cd /workspaces/<your-repo>
git add portfolio-3-transactions-concurrency/
git commit -m "Portfolio 3: transactions & concurrency — borrow_copy(), COMMIT/ROLLBACK, race + two fixes, isolation levels, deadlock (Nuhu Simbiat, 2026/A/MIT/0955)"
```

---

## Study session

This portfolio covers:

- **Study Session 1 — ACID & Characteristics of a Good DB.**
  Atomicity (the `EXCEPTION WHEN OTHERS → ROLLBACK` in `borrow_copy()` and in
  the COMMIT/ROLLBACK demo), Consistency (the schema's triggers and exclusion
  constraint keep `copy.status` and the loan set valid), Isolation (the
  two-terminal race and the three isolation levels), Durability (`COMMIT` makes
  the loan / payment permanent).
- **Study Session 2 — Consistency Models, ACID.**
  READ COMMITTED, REPEATABLE READ, and SERIALIZABLE demonstrated in
  `04_isolation_levels.sql`; serialisability failure and the deadlock are the
  two cases where PostgreSQL trades throughput for correctness by aborting a
  transaction.
