-- =============================================================================
-- ReadWell Libraries - Master Schema (Portfolio 1, used by P2, P3, P5)
-- Case study: Library Book Lending for ReadWell Libraries
--   Branches: Lagos (Yaba, Ikeja), Abuja (Garki), Kaduna
--   Members borrow physical copies, reserve out-of-stock titles, return or pay fines
--   Members can borrow from any branch.
-- Student: Nuhu Simbiat - 2026/A/MIT/0955
-- Connect via Unix socket:  sudo runuser -u postgres -- psql -d readwell
--                  or:     psql "host=/var/run/postgresql dbname=readwell"
-- =============================================================================

-- Required extensions ---------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- for the EXCLUDE constraint
CREATE EXTENSION IF NOT EXISTS pgcrypto;     -- for gen_random_uuid() if needed

-- Drop in reverse dependency order (idempotent re-runs) -----------------------
DROP TABLE IF EXISTS fine        CASCADE;
DROP TABLE IF EXISTS reservation CASCADE;
DROP TABLE IF EXISTS loan        CASCADE;
DROP TABLE IF EXISTS copy        CASCADE;
DROP TABLE IF EXISTS book_author CASCADE;
DROP TABLE IF EXISTS book        CASCADE;
DROP TABLE IF EXISTS author      CASCADE;
DROP TABLE IF EXISTS member      CASCADE;
DROP TABLE IF EXISTS branch      CASCADE;

DROP FUNCTION IF EXISTS trg_set_loan_dates();
DROP FUNCTION IF EXISTS trg_check_max_active_loans();
DROP FUNCTION IF EXISTS trg_check_unpaid_fines();

-- =============================================================================
-- 1. branch  -- a physical library location
-- =============================================================================
CREATE TABLE branch (
    branch_id   BIGSERIAL PRIMARY KEY,
    name         TEXT NOT NULL,                 -- e.g. 'Yaba', 'Ikeja', 'Garki', 'Kaduna'
    city         TEXT NOT NULL,                 -- 'Lagos', 'Abuja', 'Kaduna'
    address      TEXT,
    phone        TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 2. author
-- =============================================================================
CREATE TABLE author (
    author_id    BIGSERIAL PRIMARY KEY,
    name         TEXT NOT NULL,
    country      TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 3. book  -- a logical title (an ISBN); physical copies live in `copy`
-- =============================================================================
CREATE TABLE book (
    book_id           BIGSERIAL PRIMARY KEY,
    title             TEXT NOT NULL,
    isbn              TEXT NOT NULL UNIQUE,     -- ISBN is unique (constraint)
    category          TEXT NOT NULL,            -- Fiction, Science, History, ...
    publisher         TEXT,
    publication_year  INT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 4. book_author  -- many-to-many between book and author
-- =============================================================================
CREATE TABLE book_author (
    book_id     BIGINT NOT NULL REFERENCES book(book_id)   ON DELETE CASCADE,
    author_id   BIGINT NOT NULL REFERENCES author(author_id) ON DELETE CASCADE,
    PRIMARY KEY (book_id, author_id)
);

-- =============================================================================
-- 5. copy  -- a physical book sitting on a shelf at a branch
-- =============================================================================
CREATE TABLE copy (
    copy_id      BIGSERIAL PRIMARY KEY,
    book_id      BIGINT NOT NULL REFERENCES book(book_id),
    branch_id    BIGINT NOT NULL REFERENCES branch(branch_id),
    barcode      TEXT NOT NULL UNIQUE,
    status       TEXT NOT NULL DEFAULT 'available'
                   CHECK (status IN ('available','on_loan','lost','damaged')),
    acquired_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_copy_book_branch   ON copy(book_id, branch_id);
CREATE INDEX idx_copy_status        ON copy(status) WHERE status = 'available';

-- =============================================================================
-- 6. member  -- a registered library user
-- =============================================================================
CREATE TABLE member (
    member_id        BIGSERIAL PRIMARY KEY,
    first_name       TEXT NOT NULL,
    last_name        TEXT NOT NULL,
    email            TEXT NOT NULL UNIQUE,
    phone            TEXT,
    home_branch_id   BIGINT NOT NULL REFERENCES branch(branch_id),
    joined_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 7. loan  -- a member borrows one physical copy for a period
--    Constraint (a): a copy cannot be on two overlapping loans.
--       Implemented with an EXCLUDE constraint on a tstzrange using btree_gist.
--    Constraint (d): due_date = loan_date + 14 days; return_date >= loan_date.
--       Implemented in a BEFORE trigger.
--    Constraint (b): a member can have at most 5 active loans.  (trigger)
--    Constraint (c): a member with unpaid fines > NGN 2,000 cannot borrow. (trigger)
-- =============================================================================
CREATE TABLE loan (
    loan_id      BIGSERIAL PRIMARY KEY,
    copy_id      BIGINT NOT NULL REFERENCES copy(copy_id),
    member_id    BIGINT NOT NULL REFERENCES member(member_id),
    loan_date    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    due_date     TIMESTAMPTZ NOT NULL,          -- set by trigger = loan_date + 14 days
    return_date  TIMESTAMPTZ,                    -- NULL until returned
    loan_range   TSTZRANGE NOT NULL,             -- [loan_date, return_date or due_date)
    -- (a) a copy cannot be on two overlapping loans
    EXCLUDE USING gist (copy_id WITH =, loan_range WITH &&)
);

CREATE INDEX idx_loan_member       ON loan(member_id);
CREATE INDEX idx_loan_return_null  ON loan(member_id) WHERE return_date IS NULL;
CREATE INDEX idx_loan_loan_date     ON loan(loan_date);

-- Trigger 1: enforce due_date = loan_date + 14 days and return_date >= loan_date,
--            and auto-build loan_range.
CREATE OR REPLACE FUNCTION trg_set_loan_dates() RETURNS TRIGGER AS $$
BEGIN
    -- due date is 14 days after the loan date
    IF NEW.due_date IS NULL OR NEW.due_date <> (NEW.loan_date + INTERVAL '14 days') THEN
        NEW.due_date := NEW.loan_date + INTERVAL '14 days';
    END IF;
    -- return date cannot be before the loan date
    IF NEW.return_date IS NOT NULL AND NEW.return_date < NEW.loan_date THEN
        RAISE EXCEPTION 'return_date % cannot be before loan_date %',
            NEW.return_date, NEW.loan_date;
    END IF;
    -- build the tstzrange that the exclusion constraint uses
    NEW.loan_range := tstzrange(
        NEW.loan_date,
        COALESCE(NEW.return_date, NEW.due_date),
        '[)'
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER loan_set_dates
    BEFORE INSERT OR UPDATE ON loan
    FOR EACH ROW EXECUTE FUNCTION trg_set_loan_dates();

-- Trigger 2: a member can have at most 5 active (unreturned) loans.
CREATE OR REPLACE FUNCTION trg_check_max_active_loans() RETURNS TRIGGER AS $$
DECLARE
    active_count INT;
BEGIN
    SELECT COUNT(*) INTO active_count
    FROM loan
    WHERE member_id = NEW.member_id
      AND return_date IS NULL;
    IF active_count >= 5 THEN
        RAISE EXCEPTION
            'Member % already has 5 active loans; cannot borrow again until one is returned.',
            NEW.member_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER loan_check_max_active
    BEFORE INSERT ON loan
    FOR EACH ROW EXECUTE FUNCTION trg_check_max_active_loans();

-- Trigger 3: a member with unpaid fines totalling more than NGN 2,000 cannot borrow.
CREATE OR REPLACE FUNCTION trg_check_unpaid_fines() RETURNS TRIGGER AS $$
DECLARE
    total_unpaid NUMERIC(12,2);
BEGIN
    SELECT COALESCE(SUM(f.amount), 0) INTO total_unpaid
    FROM fine f
    JOIN loan l ON l.loan_id = f.loan_id
    WHERE l.member_id = NEW.member_id
      AND f.paid = FALSE;
    IF total_unpaid > 2000 THEN
        RAISE EXCEPTION
            'Member % has unpaid fines of NGN %; borrowing blocked until fines are settled.',
            NEW.member_id, total_unpaid;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER loan_check_unpaid_fines
    BEFORE INSERT ON loan
    FOR EACH ROW EXECUTE FUNCTION trg_check_unpaid_fines();

-- =============================================================================
-- 8. reservation  -- a member reserves a title (book) for pickup at a branch
-- =============================================================================
CREATE TABLE reservation (
    reservation_id        BIGSERIAL PRIMARY KEY,
    book_id               BIGINT NOT NULL REFERENCES book(book_id),
    member_id             BIGINT NOT NULL REFERENCES member(member_id),
    branch_id             BIGINT NOT NULL REFERENCES branch(branch_id),
    reserved_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fulfilled_at          TIMESTAMPTZ,
    fulfilled_by_copy_id  BIGINT REFERENCES copy(copy_id)
);

CREATE INDEX idx_reservation_book      ON reservation(book_id) WHERE fulfilled_at IS NULL;
CREATE INDEX idx_reservation_member    ON reservation(member_id);

-- =============================================================================
-- 9. fine  -- a late-return fine on a loan.  amount > 0 enforced by CHECK.
-- =============================================================================
CREATE TABLE fine (
    fine_id     BIGSERIAL PRIMARY KEY,
    loan_id     BIGINT NOT NULL REFERENCES loan(loan_id),
    amount      NUMERIC(10,2) NOT NULL CHECK (amount > 0),   -- fine amount > 0
    paid        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    paid_at     TIMESTAMPTZ
);

CREATE INDEX idx_fine_paid ON fine(paid) WHERE paid = FALSE;
CREATE INDEX idx_fine_loan ON fine(loan_id);

-- =============================================================================
-- End of schema
-- =============================================================================
