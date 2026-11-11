# Two-Terminal Race Condition: Two Members, One Last Copy

**Portfolio 3 — Transactions and Concurrency**
**Student:** Nuhu Simbiat · **Matric:** 2026/A/MIT/0955 · **Course:** MIT 8103
**Institution:** Miva Open University
**Case study:** ReadWell Libraries (PostgreSQL 16, database `readwell`).

This guide is the centerpiece of Portfolio 3. It walks through a *real*
concurrency bug, then shows **two fixes**.

> **Automated version (added after testing):** `run_p3.sh` runs
> `run_race_demos.py`, which performs every scenario in this guide (plus the
> isolation-level and deadlock demos) with **two real PostgreSQL sessions**,
> proves the waiting session is blocked via `pg_stat_activity`, and saves the
> real transcript to `race_demos_output.log`. Part 1 of that script shows the
> bug for real on a scratch table `loan_naive` that has **no** EXCLUDE
> constraint (both members get the same copy); Part 2 repeats it on the real
> `loan` table, where the constraint rejects Terminal B. The steps below are
> the manual version of the same thing.

Open **two** psql sessions side by side (Codespaces — Unix socket, never TCP):

```bash
# Terminal A
sudo runuser -u postgres -- psql -d readwell

# Terminal B
sudo runuser -u postgres -- psql -d readwell
```

> The setup uses deterministic IDs (91xx) so the demo is reproducible. The
> cleanup block at the top deletes any leftover rows from a previous run.

---

## Setup (run ONCE in Terminal A)

Pick a book + branch that has **exactly one** available copy, and create two
members who both want it. Run this whole block in **Terminal A** only.

```sql
-- ===== Cleanup any previous run =====
DELETE FROM fine        WHERE loan_id IN (SELECT loan_id FROM loan WHERE member_id IN (9101, 9102));
DELETE FROM loan        WHERE member_id IN (9101, 9102);
DELETE FROM reservation  WHERE member_id IN (9101, 9102);
DELETE FROM copy         WHERE copy_id   IN (9101);
DELETE FROM member       WHERE member_id IN (9101, 9102);
DELETE FROM book         WHERE book_id    = 9101;
DELETE FROM branch       WHERE branch_id   = 9101;

-- ===== Fresh test data =====
INSERT INTO branch (branch_id, name, city)
VALUES (9101, 'Race Branch', 'Lagos');

INSERT INTO member (member_id, first_name, last_name, email, home_branch_id)
VALUES (9101, 'Ada',  'Race', 'ada.race@test.local',  9101),
       (9102, 'Bola', 'Race', 'bola.race@test.local', 9101);

INSERT INTO book (book_id, title, isbn, category)
VALUES (9101, 'Race Title', '978-0000-9101', 'Fiction');

-- EXACTLY ONE available copy of book 9101 at branch 9101
INSERT INTO copy (copy_id, book_id, branch_id, barcode, status)
VALUES (9101, 9101, 9101, 'RACE-9101', 'available');

-- ===== Confirm: one available copy =====
SELECT c.copy_id, c.book_id, c.branch_id, c.status
  FROM copy c
 WHERE c.book_id = 9101 AND c.branch_id = 9101
 ORDER BY c.copy_id;
```

Expected output of the last `SELECT`:

```
 copy_id | book_id | branch_id |  status
---------+---------+-----------+----------
    9101 |    9101 |      9101 | available
(1 row)
```

Note the **copy_id** (here `9101`) — every step below uses this number.

---

## THE BUG (no locking, no constraint awareness)

Both members run a *naive* borrow that:
- does **not** use `SELECT ... FOR UPDATE` on the `copy` row, and
- does **not** rely on the exclusion constraint that Portfolio 1 already put on
  `loan(copy_id, loan_range)`.

Because both sessions read `status='available'` *before* either writes, the
application code in **both** terminals believes the borrow succeeded. Only one
borrow is actually possible; the exclusion constraint is the safety net that
catches the second.

### Terminal A

```sql
BEGIN;
SELECT copy_id, status FROM copy
 WHERE book_id = 9101 AND branch_id = 9101 AND status = 'available';
-- copy_id 9101 is 'available' (A has not written yet)
```

Leave Terminal A sitting at the `readwell=#` prompt — **do not COMMIT yet**.
Switch to Terminal B.

### Terminal B (run while A is still inside its BEGIN)

```sql
BEGIN;
SELECT copy_id, status FROM copy
 WHERE book_id = 9101 AND branch_id = 9101 AND status = 'available';
-- copy_id 9101 is STILL 'available' — A has not committed, so B sees the old snapshot.
```

### Terminal A — issue the borrow

```sql
INSERT INTO loan (copy_id, member_id, loan_date, due_date)
VALUES (9101, 9101, NOW(), NOW() + INTERVAL '14 days');
UPDATE copy SET status = 'on_loan' WHERE copy_id = 9101;
COMMIT;
-- COMMIT succeeds. A walks away with the book.
```

### Terminal B — issue the same borrow

```sql
INSERT INTO loan (copy_id, member_id, loan_date, due_date)
VALUES (9101, 9102, NOW(), NOW() + INTERVAL '14 days');
```

What happens here is the heart of the bug. B's `INSERT` needs to write into the
GiST index that backs the `EXCLUDE USING gist (copy_id WITH =, loan_range WITH &&)`
constraint. The index entry for copy 9101 is already held by A's *uncommitted*
loan row, so B's `INSERT` **blocks** waiting for A. The moment A `COMMIT`s
above, B's `INSERT` is unblocked — and immediately fails with the exclusion
violation:

```
ERROR:  conflicting key value violates exclusion constraint "loan_copy_id_loan_range_excl"
DETAIL:  Key (copy_id, loan_range)=(9101, ["2026-...","2026-...")) conflicts with
         existing key (copy_id, loan_range)=(9101, ["2026-...","2026-...")).
```

B's application code (if it had no error handling) would now be in a transaction
that has aborted. To finish cleanly:

```sql
ROLLBACK;
```

### Real terminal transcripts

[paste real output here]   <!-- Terminal A: BEGIN, SELECT, INSERT, UPDATE, COMMIT -->

[paste real output here]   <!-- Terminal B: BEGIN, SELECT, INSERT (blocks), then ERROR, then ROLLBACK -->

### Why this is a bug

- Both sessions *believed* the copy was free and proceeded to write a loan row.
- The application logic in each session would happily continue (print "borrowed
  copy 9101"), and only one of them is telling the truth.
- The `EXCLUDE` constraint on `loan` is the **only** thing preventing a
  physically impossible state (two simultaneous loans of the same physical copy).

---

## FIX 1 — The exclusion constraint (already in the schema) rejects the second loan

No new code is needed. The Portfolio 1 schema already declares:

```sql
EXCLUDE USING gist (copy_id WITH =, loan_range WITH &&)
```

on the `loan` table. With btree_gist installed, PostgreSQL can compare both the
`copy_id` (scalar equality) and the `loan_range` (a `tstzrange` overlap) inside
a single GiST index. Two rows with the same `copy_id` whose `loan_range`s
overlap cannot both exist.

### What the student sees

When Terminal B's `INSERT INTO loan` is unblocked (after A commits), PostgreSQL
returns the **exact** error message:

```
ERROR:  conflicting key value violates exclusion constraint "loan_copy_id_loan_range_excl"
DETAIL:  Key (copy_id, loan_range)=(9101, ["2026-MM-DD ...","2026-MM-DD ..."))
         conflicts with existing key (copy_id, loan_range)=(9101, ["2026-MM-DD ...","2026-MM-DD ...")).
```

[paste real output here]   <!-- Terminal B transcript showing the exclusion error -->

### Why this is "fix 1" and not the whole answer

The exclusion constraint prevents the *physically impossible* state, but it
does not give B a useful outcome — B's transaction simply aborts and the user
is told "try again later". A better application pattern would have B
**wait politely** and then fall through to a **reservation**. That is Fix 2.

---

## FIX 2 — `SELECT ... FOR UPDATE` makes B wait, then returns "reserved for you"

This fix uses the `borrow_copy(p_member_id, p_book_id, p_branch_id)` function
installed by `01_borrow_copy_function.sql`. The crucial line inside it is:

```sql
SELECT c.copy_id INTO v_copy_id
  FROM copy c
 WHERE c.book_id = p_book_id
   AND c.branch_id = p_branch_id
   AND c.status = 'available'
 ORDER BY c.copy_id
 LIMIT 1
 FOR UPDATE;          -- <<<< serialises callers on the same copy row
```

### Reset the demo

Before running Fix 2, reset the copy and loans (run in **either** terminal, then
commit / quit):

```sql
-- Tear down the loans from the previous step
DELETE FROM fine WHERE loan_id IN (SELECT loan_id FROM loan WHERE member_id IN (9101, 9102));
DELETE FROM loan WHERE member_id IN (9101, 9102);
DELETE FROM reservation WHERE member_id IN (9101, 9102);
UPDATE copy SET status = 'available' WHERE copy_id = 9101;

-- Confirm the copy is available again
SELECT copy_id, status FROM copy WHERE copy_id = 9101;
```

### Terminal A — borrows the copy

Make sure `01_borrow_copy_function.sql` has been loaded once (it is loaded by
`run_p3.sh`, or run it manually):

```bash
sudo runuser -u postgres -- psql -d readwell -f 01_borrow_copy_function.sql
```

Then in Terminal A:

```sql
BEGIN;
SELECT * FROM borrow_copy(9101, 9101, 9101);   -- (M_A, book, branch)
-- Expected: 9101   (the copy_id that was borrowed)
COMMIT;
```

Leave Terminal A **paused** between `BEGIN;` and `COMMIT;` for the next step
(run the `SELECT` line, look at the result, then **don't** type `COMMIT;`
just yet — switch to Terminal B).

### Terminal B — runs concurrently, blocks, then gets a reservation

```sql
BEGIN;
SELECT * FROM borrow_copy(9102, 9101, 9101);   -- (M_B, same book, same branch)
-- This BLOCKS here. The FOR UPDATE on copy 9101 is held by Terminal A.
-- As soon as A COMMITs, B's SELECT FOR UPDATE wakes up — but the row it
-- was trying to lock has status='on_loan' now, so it no longer matches the
-- WHERE clause. v_copy_id becomes NULL inside the function, and the
-- function falls through to the reservation branch.
-- Expected: (NULL)   -- the "reserved for you" marker
COMMIT;
```

Now switch back to Terminal A and run `COMMIT;`. Watch Terminal B unblock and
print `(NULL)`.

### Verify the reservation

In either terminal:

```sql
SELECT reservation_id, book_id, member_id, branch_id, reserved_at, fulfilled_at
  FROM reservation
 WHERE member_id = 9102
 ORDER BY reserved_at DESC
 LIMIT 1;

SELECT copy_id, status FROM copy WHERE copy_id = 9101;
```

Expected:

```
 reservation_id | book_id | member_id | branch_id |          reserved_at          | fulfilled_at
----------------+---------+-----------+-----------+-------------------------------+--------------
           <id> |    9101 |      9102 |      9101 | 2026-MM-DD HH:MI:SS...        |
(1 row)

 copy_id |  status
---------+----------
    9101 | on_loan
(1 row)
```

### Real terminal transcripts

[paste real output here]   <!-- Terminal A: BEGIN, SELECT borrow_copy, COMMIT -->

[paste real output here]   <!-- Terminal B: BEGIN, SELECT borrow_copy (blocked, then NULL), COMMIT, plus verification SELECT -->

### Why this is the right fix

- `FOR UPDATE` **serialises** access to the copy row: only one transaction can
  hold the row lock at a time.
- The second caller **waits** instead of failing fast; when it wakes, the row's
  status has changed (`available` → `on_loan`), so the `WHERE` clause no longer
  matches and the function correctly falls through to the reservation branch.
- The user gets a **useful outcome** ("the book has been reserved for you")
  instead of an error.
- The exclusion constraint is still in place as the ultimate safety net, so
  even a coding mistake in `borrow_copy()` cannot create a phantom double-loan.

---

## Clean-up (optional, run in either terminal)

```sql
DELETE FROM fine        WHERE loan_id IN (SELECT loan_id FROM loan WHERE member_id IN (9101, 9102));
DELETE FROM loan        WHERE member_id IN (9101, 9102);
DELETE FROM reservation  WHERE member_id IN (9101, 9102);
DELETE FROM copy         WHERE copy_id   = 9101;
DELETE FROM member       WHERE member_id IN (9101, 9102);
DELETE FROM book         WHERE book_id    = 9101;
DELETE FROM branch       WHERE branch_id   = 9101;
```
