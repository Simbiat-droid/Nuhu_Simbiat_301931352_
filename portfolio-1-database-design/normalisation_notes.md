# Normalisation Notes — ReadWell Libraries (Portfolio 1)

**Student:** Nuhu Simbiat — 2026/A/MIT/0955
**Database:** `readwell` (PostgreSQL 16)
**Study Session:** Session 1 — Review of Traditional Relational Databases (Normalisation, Stages of DB Design)

---

## What 3NF means in this document

A relation is in **Third Normal Form (3NF)** when:

1. It is in 1NF (every attribute holds atomic values; there is a primary key).
2. It is in 2NF (every non-key attribute depends on the *whole* primary key, not just part of it — only relevant for composite keys).
3. It has **no transitive dependencies**: every non-key attribute depends *only* on the primary key, not on another non-key attribute.

The classic test (Boyce-Codd reformulation): *every non-trivial functional dependency has a super-key on its left-hand side.*

The 9 tables below all satisfy 1NF + 2NF + 3NF.

---

## 1. `branch`

| Attribute | Type | Key |
|-----------|------|-----|
| branch_id | BIGINT | PK |
| name | TEXT | |
| city | TEXT | |
| address | TEXT | |
| phone | TEXT | |
| created_at | TIMESTAMPTZ | |

- **Primary key:** `branch_id`
- **Foreign keys:** none
- **3NF note:** Every non-key attribute (`name`, `city`, `address`, `phone`, `created_at`) describes the branch directly and depends only on `branch_id`. There is no transitive dependency (e.g. `city` is not derived from `name`).

## 2. `author`

| Attribute | Type | Key |
|-----------|------|-----|
| author_id | BIGINT | PK |
| name | TEXT | |
| country | TEXT | |
| created_at | TIMESTAMPTZ | |

- **Primary key:** `author_id`
- **Foreign keys:** none
- **3NF note:** `name` and `country` are properties of the author alone; `country` is *not* derived from `name` (two authors can share a name but come from different countries), so no transitive dependency exists.

## 3. `book`

| Attribute | Type | Key |
|-----------|------|-----|
| book_id | BIGINT | PK |
| title | TEXT | |
| isbn | TEXT | UK |
| category | TEXT | |
| publisher | TEXT | |
| publication_year | INT | |
| created_at | TIMESTAMPTZ | |

- **Primary key:** `book_id` (surrogate); `isbn` is a UNIQUE candidate key
- **Foreign keys:** none
- **3NF note:** `title`, `category`, `publisher`, `publication_year` each describe the book and depend only on `book_id` (or equivalently on `isbn`). `publisher` is *not* derived from `category` (a publisher publishes many categories), so there is no transitive dependency.

## 4. `book_author` (junction)

| Attribute | Type | Key |
|-----------|------|-----|
| book_id | BIGINT | PK, FK → book.book_id |
| author_id | BIGINT | PK, FK → author.author_id |

- **Primary key:** composite `(book_id, author_id)`
- **Foreign keys:** `book_id` → `book`, `author_id` → `author`
- **3NF note:** There are **no non-key attributes** in this table at all, so 2NF and 3NF hold vacuously. This is the canonical pattern for a many-to-many relationship — the table exists only to record that a given author wrote a given book.

## 5. `copy`

| Attribute | Type | Key |
|-----------|------|-----|
| copy_id | BIGINT | PK |
| book_id | BIGINT | FK → book.book_id |
| branch_id | BIGINT | FK → branch.branch_id |
| barcode | TEXT | UK |
| status | TEXT | CHECK |
| acquired_at | TIMESTAMPTZ | |

- **Primary key:** `copy_id`; `barcode` is a UNIQUE candidate key
- **Foreign keys:** `book_id` → `book`, `branch_id` → `branch`
- **3NF note:** `barcode`, `status`, `acquired_at` all describe the physical copy and depend only on `copy_id`. The `book_id` and `branch_id` are FK references, not derived data; attributes of the book (e.g. `title`) are *not* repeated here, so there is no transitive dependency.

## 6. `member`

| Attribute | Type | Key |
|-----------|------|-----|
| member_id | BIGINT | PK |
| first_name | TEXT | |
| last_name | TEXT | |
| email | TEXT | UK |
| phone | TEXT | |
| home_branch_id | BIGINT | FK → branch.branch_id |
| joined_at | TIMESTAMPTZ | |

- **Primary key:** `member_id`; `email` is a UNIQUE candidate key
- **Foreign keys:** `home_branch_id` → `branch`
- **3NF note:** Personal attributes (`first_name`, `last_name`, `email`, `phone`) describe the member directly. `home_branch_id` is a reference (not a denormalised copy of branch data), so no transitive dependency exists.

## 7. `loan`

| Attribute | Type | Key |
|-----------|------|-----|
| loan_id | BIGINT | PK |
| copy_id | BIGINT | FK → copy.copy_id |
| member_id | BIGINT | FK → member.member_id |
| loan_date | TIMESTAMPTZ | |
| due_date | TIMESTAMPTZ | (set by trigger = loan_date + 14 days) |
| return_date | TIMESTAMPTZ | (nullable) |
| loan_range | TSTZRANGE | (set by trigger) |

- **Primary key:** `loan_id`
- **Foreign keys:** `copy_id` → `copy`, `member_id` → `member`
- **3NF note:** `loan_date`, `due_date`, `return_date` and `loan_range` are facts about *this specific loan event* and depend only on `loan_id`. `due_date` is technically derivable from `loan_date`, but it is materialised so the system can record what the member was told at the time (the rule could change tomorrow without rewriting history); it is therefore a column of the loan, not a transitive dependency. Crucially, **fine data lives in a separate `fine` table** — see the journey below.

## 8. `reservation`

| Attribute | Type | Key |
|-----------|------|-----|
| reservation_id | BIGINT | PK |
| book_id | BIGINT | FK → book.book_id |
| member_id | BIGINT | FK → member.member_id |
| branch_id | BIGINT | FK → branch.branch_id |
| reserved_at | TIMESTAMPTZ | |
| fulfilled_at | TIMESTAMPTZ | (nullable) |
| fulfilled_by_copy_id | BIGINT | FK → copy.copy_id (nullable) |

- **Primary key:** `reservation_id`
- **Foreign keys:** `book_id` → `book`, `member_id` → `member`, `branch_id` → `branch`, `fulfilled_by_copy_id` → `copy`
- **3NF note:** `reserved_at` and `fulfilled_at` describe the reservation event and depend only on `reservation_id`. All four FK columns are references, not duplicated data. The `fulfilled_by_copy_id` is initially NULL and only set when a copy is assigned, so it does not introduce a transitive dependency on `book_id`.

## 9. `fine`

| Attribute | Type | Key |
|-----------|------|-----|
| fine_id | BIGINT | PK |
| loan_id | BIGINT | FK → loan.loan_id |
| amount | NUMERIC(10,2) | CHECK > 0 |
| paid | BOOLEAN | |
| created_at | TIMESTAMPTZ | |
| paid_at | TIMESTAMPTZ | (nullable) |

- **Primary key:** `fine_id`
- **Foreign keys:** `loan_id` → `loan`
- **3NF note:** `amount`, `paid`, `created_at` and `paid_at` all describe the fine itself and depend only on `fine_id`. The amount is *not* stored as a derived column on `loan` (which would create a transitive dependency `loan_id → amount`), so the model is properly normalised.

---

## Journey to 3NF for the `loan` table

This section walks through 1NF → 2NF → 3NF for the loan concept, showing why `fine_amount` does **not** belong in `loan` and why it must live in its own `fine` table.

### Unnormalised starting point

A librarian's first spreadsheet might record each loan on one row, with everything about the member, the book, the copy and the fine mashed together:

```
loan_id | copy_barcode | book_title         | book_isbn     | member_name     | member_email            | loan_date | due_date | return_date | fine_amount | fine_paid
--------+--------------+--------------------+---------------+-----------------+-------------------------+-----------+----------+-------------+-------------+----------
  101   | RW00000042   | Things Fall Apart  | 9789780230012 | Aisha Bello     | aisha.bello@example.com | 2025-1-3  | 2025-1-17| 2025-1-25   |   400.00    | TRUE
```

### 1NF — atomic values + a primary key

The row above already has atomic values and a primary key (`loan_id`), so it is in **1NF**. The composite fact "the member who borrowed this loan is Aisha Bello at aisha.bello@example.com" is still embedded in the loan row, which is the problem.

### 2NF — remove partial dependencies

If we promoted `(loan_id, member_email)` to a composite key, `member_name` would depend on `member_email` alone (a *partial* dependency). Even with a single-column key `loan_id`, the spirit of 2NF applies: attributes that describe the *member* (not the loan) belong in a `member` table, and attributes that describe the *book* (not the loan) belong in a `book` table. After splitting:

```
loan   : loan_id, copy_id, member_id, loan_date, due_date, return_date, fine_amount, fine_paid
member : member_id, first_name, last_name, email, phone, home_branch_id
copy   : copy_id, book_id, branch_id, barcode, status
book   : book_id, title, isbn, category, publisher, publication_year
```

This is **2NF**: every non-key attribute in `loan` depends on the whole key `loan_id`.

### 3NF — remove transitive dependencies

In the 2NF `loan` table, `fine_amount` and `fine_paid` are transitively dependent on `loan_id` *through the act of returning late*: `loan_id → (return_date - due_date) → fine_amount`. If a librarian corrects a return date, every fine attribute has to be recomputed, and we cannot model the case where a single loan incurs *several* fines (e.g. late fee + processing fee). To fix this we extract `fine` into its own table keyed by `fine_id`:

```
loan : loan_id, copy_id, member_id, loan_date, due_date, return_date, loan_range
fine : fine_id, loan_id, amount, paid, created_at, paid_at
```

Now `loan` holds only facts about the borrowing event, and `fine` holds only facts about a fine. `fine_amount` is computed at fine-creation time (in the bulk generator: `days_late × 50 NGN`) and stored once on the `fine` row. There are no transitive dependencies left, so the model is in **3NF**.

The same argument applies to `due_date`: it is derived from `loan_date`, but we still store it because the lending rule may change (14 days today, 21 days next year) and the historical record must reflect what the member was told at the time. Storing a derived snapshot is a deliberate, well-understood denormalisation — it does not introduce a transitive dependency because `due_date` is not used to derive any *other* column.
