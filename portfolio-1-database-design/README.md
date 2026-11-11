# Portfolio 1 — Database Design and Modelling (ReadWell Libraries)

**Student:** Nuhu Simbiat  
**Matric:** 2026/A/MIT/0955  
**Course:** MIT 8103 — Advanced Database Systems  
**University:** Miva Open University  
**Database:** `readwell` (PostgreSQL 16)  
**Study Session:** Session 1 — *Review of Traditional Relational Databases (Normalisation, Stages of DB Design)*

---

## 1. What this portfolio demonstrates

A multi-branch library book-lending database for **ReadWell Libraries** (Lagos-Yaba, Lagos-Ikeja, Abuja-Garki, Kaduna). The portfolio shows four things:

1. **ER design** — 9 entities (`branch`, `author`, `book`, `book_author`, `copy`, `member`, `loan`, `reservation`, `fine`) drawn as a Mermaid ER diagram in `er_diagram.md`.
2. **3NF normalisation** — every relation is in third normal form; per-table reasoning and a 1NF → 2NF → 3NF journey for the `loan` table are in `normalisation_notes.md`.
3. **Constraints & business rules** (declared in the shared `01_schema.sql`):
   - `book.isbn` UNIQUE
   - `fine.amount > 0` CHECK
   - EXCLUDE (GiST) so a physical copy is never on two overlapping loans
   - BEFORE triggers: `due_date = loan_date + 14 days`; `return_date >= loan_date`; max 5 active loans per member; block borrowing when unpaid fines exceed NGN 2 000.
4. **Bulk data** — `03_bulk_generator.sql` loads 3 000 members, 5 000 copies and 50 000+ loans inside the last 2 years using relative dates (`NOW() - INTERVAL '2 years'`).

## 2. Codespaces run commands

```bash
cd /workspaces/<your-repo>/portfolio-1-database-design
chmod +x run_p1.sh
./run_p1.sh
```

`run_p1.sh` runs schema → seed → bulk → constraint tests → prints row counts. Each SQL file is invoked with `sudo runuser -u postgres -- psql -d readwell -f <file.sql>` over the Unix socket (never TCP).

## 3. What to screenshot for evidence

Run the commands below *after* `run_p1.sh` finishes and screenshot each block.

**(a) Schema (`\d` outputs):**
```bash
sudo runuser -u postgres -- psql -d readwell -c "\d loan"
sudo runuser -u postgres -- psql -d readwell -c "\d fine"
sudo runuser -u postgres -- psql -d readwell -c "\d copy"
```

**(b) Constraint violation errors** — printed as NOTICEs by `04_constraint_tests.sql`:
```bash
sudo runuser -u postgres -- psql -d readwell -f 04_constraint_tests.sql
```
Capture all 7 tests: TEST A (exclusion), TEST B (max 5 active), TEST C (unpaid fines), TEST D (return < loan), TEST E (duplicate ISBN), TEST F (fine ≤ 0), TEST G (auto due_date).

**(c) Row counts** (also printed at the end of `run_p1.sh`):
```bash
sudo runuser -u postgres -- psql -d readwell -c "SELECT 'branch' t, count(*) FROM branch UNION ALL SELECT 'book', count(*) FROM book UNION ALL SELECT 'copy', count(*) FROM copy UNION ALL SELECT 'member', count(*) FROM member UNION ALL SELECT 'loan', count(*) FROM loan UNION ALL SELECT 'fine', count(*) FROM fine;"
```

**(d) Loan count ≥ 50 000:**
```bash
sudo runuser -u postgres -- psql -d readwell -c "SELECT count(*) AS total_loans FROM loan;"
```

## 4. Git commit

```bash
cd /workspaces/<your-repo>
git add portfolio-1-database-design/
git commit -m "Portfolio 1: ReadWell Libraries DB design (schema, seed, 50k loans, constraint tests, ER + 3NF notes) - Nuhu Simbiat 2026/A/MIT/0955"
```

## 5. Files in this portfolio

| File | Purpose |
|------|---------|
| `01_schema.sql` | Shared schema (provided — DO NOT modify) |
| `02_seed_data.sql` | 4 branches, 25 authors, 42 books, M:N mappings, 60 copies, 15 members |
| `03_bulk_generator.sql` | 3 000 members, 5 000 copies, 50 000+ loans, fines |
| `04_constraint_tests.sql` | 7 tests that exercise each constraint (expected to FAIL) |
| `run_p1.sh` | Runs everything in order |
| `er_diagram.md` | Mermaid ER diagram (all 9 tables) |
| `normalisation_notes.md` | 3NF reasoning per table + journey to 3NF |
| `README.md` | This file |
