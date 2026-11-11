-- =============================================================================
-- 01_partitioning.sql - Portfolio 5
-- Convert the `loan` table into a RANGE-partitioned table partitioned by month
-- on `loan_date`, then migrate the existing rows from the renamed `loan_old`.
--
-- Student  : Nuhu Simbiat
-- Matric   : 2026/A/MIT/0955
-- Database : readwell  (PostgreSQL 16)
-- Run      : sudo runuser -u postgres -- psql -d readwell -f 01_partitioning.sql
-- =============================================================================
-- DESIGN NOTES (read before running)
-- -----------------------------------------------------------------------------
-- 1. PostgreSQL 16 requires exclusion constraints on a partitioned table to
--    include the partition key column in the constraint expression. We
--    partition by RANGE(loan_date), so the EXCLUDE must reference loan_date.
--    Final constraint:
--        EXCLUDE USING gist (copy_id WITH =, loan_range WITH &&, loan_date WITH =)
--
-- 2. The trigger trg_set_loan_dates() (created by Portfolio 1, retained here)
--    sets loan_range = tstzrange(loan_date, COALESCE(return_date, due_date), '[)')
--    so loan_date IS the lower bound of loan_range. Two rows that share copy_id
--    AND an overlapping loan_range AND the same loan_date are therefore
--    guaranteed to land in the same monthly partition, where the per-partition
--    EXCLUDE constraint catches the conflict and rejects the second INSERT.
--    (Loans started on different days but with overlapping active ranges are
--    a separate concern; ReadWell's business rule is "a copy can only leave
--    the shelf once per day", which is preserved by this design.)
--
-- 3. The PRIMARY KEY on a partitioned table must also include the partition
--    key, so PK becomes (loan_id, loan_date) - explicitly named loan_pk_new so
--    it does not collide with the original `loan_pkey` constraint that now
--    lives on the renamed `loan_old` table.
--
-- 4. The original `fine` table has a single-column FK:
--        fine.loan_id REFERENCES loan(loan_id)
--    When `loan` is renamed to `loan_old`, that FK follows the renamed table
--    and continues to enforce referential integrity for HISTORICAL fines.
--    A standalone UNIQUE(loan_id) is NOT allowed on a partitioned table (it
--    would have to include loan_date), so the new partitioned loan cannot be
--    the target of a single-column FK. In production we would migrate `fine`
--    to a composite FK (loan_id, loan_date) -> loan(loan_id, loan_date); for
--    this portfolio we RETAIN `loan_old` as a read-only backup so existing
--    fine FKs keep working. New loans go into the partitioned `loan`.
-- =============================================================================

\set ON_ERROR_STOP on

-- FIX: re-run guard. If loan is ALREADY partitioned, skip the migration
-- (a second run used to fail on "loan_old already exists").
SELECT EXISTS (SELECT 1 FROM pg_class WHERE relname = 'loan' AND relkind = 'p') AS already_partitioned \gset
\if :already_partitioned
  \echo 'loan is already partitioned - skipping migration, showing partitions only.'
\else

\echo '================================================================'
\echo ' STEP 1 - Rename the existing loan table to loan_old'
\echo '================================================================'
-- The IF EXISTS guards make this safe to re-run.
ALTER TABLE IF EXISTS loan RENAME TO loan_old;

-- Drop the OLD triggers from loan_old so they don't fire when we read it.
-- The trigger FUNCTIONS (trg_set_loan_dates, trg_check_max_active_loans,
-- trg_check_unpaid_fines) defined in Portfolio 1 are REUSED - we don't drop
-- the functions, only the triggers bound to loan_old.
-- FIX: "ALTER TABLE ... DROP TRIGGER" is not valid SQL (syntax error).
DROP TRIGGER IF EXISTS loan_set_dates          ON loan_old;
DROP TRIGGER IF EXISTS loan_check_max_active   ON loan_old;
DROP TRIGGER IF EXISTS loan_check_unpaid_fines ON loan_old;
-- give loan_old's constraints/sequence their own names so the new table can reuse them
ALTER TABLE loan_old RENAME CONSTRAINT loan_pkey TO loan_old_pkey;
ALTER SEQUENCE loan_loan_id_seq RENAME TO loan_old_loan_id_seq;
-- FIX: loan_old kept the index NAMES idx_loan_*, so the
-- "CREATE INDEX IF NOT EXISTS idx_loan_member ON loan" lines below were
-- silently skipped and the partitioned table got NO indexes. Rename them.
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT indexrelid::regclass::text AS idx FROM pg_index
              WHERE indrelid = 'loan_old'::regclass AND indexrelid::regclass::text LIKE 'idx_loan%' LOOP
        EXECUTE format('ALTER INDEX %I RENAME TO %I', r.idx, 'old_' || r.idx);
    END LOOP;
END $$;

\echo
\echo 'loan_old now holds the historical data; the old triggers are detached.'
\echo 'The FK from `fine` still references loan_old.loan_id (FKs follow renames).'

\echo '================================================================'
\echo ' STEP 2 - Create the new partitioned parent table loan'
\echo '================================================================'
-- Constraint names are EXPLICIT to avoid colliding with the originals
-- (loan_pkey, loan_copy_id_loan_range_excl) that now live on loan_old.
CREATE TABLE loan (
    loan_id      BIGSERIAL,
    copy_id      BIGINT NOT NULL REFERENCES copy(copy_id),
    member_id    BIGINT NOT NULL REFERENCES member(member_id),
    loan_date    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    due_date     TIMESTAMPTZ NOT NULL,
    return_date  TIMESTAMPTZ,
    loan_range   TSTZRANGE NOT NULL,
    -- The primary key of a partitioned table must include the partition key.
    CONSTRAINT loan_pk_new      PRIMARY KEY (loan_id, loan_date)
    -- FIX: PostgreSQL 16 rejects EXCLUDE constraints on a partitioned table
    -- ("exclusion constraints are not supported on partitioned tables"), and
    -- adding "loan_date WITH =" would only stop overlaps with the SAME
    -- loan_date - useless. The no-double-loan rule is enforced instead by the
    -- trg_no_overlapping_loan trigger in STEP 5 (works across partitions).
) PARTITION BY RANGE (loan_date);

\echo '================================================================'
\echo ' STEP 3 - Create monthly partitions: last 24 months + next 2 months'
\echo '================================================================'
-- Use a PL/pgSQL DO loop so we generate partitions for a moving 26-month
-- window. Each partition is named loan_YYYYMM (e.g. loan_202409).
-- generate_series walks month boundaries; FOR VALUES FROM [) is half-open.
DO $$
DECLARE
    m          DATE;
    part_name  TEXT;
    start_ts   TIMESTAMPTZ;
    end_ts     TIMESTAMPTZ;
BEGIN
    FOR m IN
        -- FIX: start at the OLDEST real loan month (not a fixed 24 months),
        -- so every migrated row has a monthly partition; end 2 months ahead.
        SELECT generate_series(
            LEAST(date_trunc('month', (SELECT MIN(loan_date) FROM loan_old)),
                  date_trunc('month', NOW()))::timestamp,
            (date_trunc('month', NOW()) + INTERVAL '2 months')::timestamp,
            INTERVAL '1 month'
        )::date
    LOOP
        part_name := 'loan_' || to_char(m, 'YYYYMM');
        start_ts  := date_trunc('month', m::timestamptz);
        end_ts    := start_ts + INTERVAL '1 month';
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF loan FOR VALUES FROM (%L) TO (%L)',
            part_name, start_ts, end_ts
        );
    END LOOP;
END $$;

\echo '================================================================'
\echo ' STEP 4 - Indexes on the partitioned parent'
\echo '         (PostgreSQL 16 propagates them to every partition)'
\echo '================================================================'
CREATE INDEX IF NOT EXISTS idx_loan_member       ON loan(member_id);
CREATE INDEX IF NOT EXISTS idx_loan_return_null  ON loan(member_id) WHERE return_date IS NULL;
CREATE INDEX IF NOT EXISTS idx_loan_loan_date     ON loan(loan_date);
-- FIX: a plain btree on a range column cannot help overlap tests; use GiST.
CREATE INDEX IF NOT EXISTS idx_loan_copy_range    ON loan USING gist (copy_id, loan_range);
-- safety net for any date outside the monthly partitions
CREATE TABLE IF NOT EXISTS loan_default PARTITION OF loan DEFAULT;

\echo '================================================================'
\echo ' STEP 5 - Re-create the loan triggers on the new partitioned parent'
\echo '         (functions already exist from Portfolio 1; rebind triggers)'
\echo '================================================================'
CREATE TRIGGER loan_set_dates
    BEFORE INSERT OR UPDATE ON loan
    FOR EACH ROW EXECUTE FUNCTION trg_set_loan_dates();

CREATE TRIGGER loan_check_max_active
    BEFORE INSERT ON loan
    FOR EACH ROW EXECUTE FUNCTION trg_check_max_active_loans();

CREATE TRIGGER loan_check_unpaid_fines
    BEFORE INSERT ON loan
    FOR EACH ROW EXECUTE FUNCTION trg_check_unpaid_fines();

-- FIX: replaces the EXCLUDE constraint that PostgreSQL 16 cannot put on a
-- partitioned table. A transaction-level advisory lock per copy_id makes
-- concurrent borrowers of the SAME copy queue up, then the overlap check
-- runs across ALL partitions (loan ranges can cross a month boundary).
CREATE OR REPLACE FUNCTION trg_no_overlapping_loan() RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(NEW.copy_id);
    IF EXISTS (SELECT 1 FROM loan l
                WHERE l.copy_id = NEW.copy_id
                  AND l.loan_range && NEW.loan_range
                  AND l.loan_id <> NEW.loan_id) THEN
        RAISE EXCEPTION 'copy % is already on loan for an overlapping period', NEW.copy_id
              USING ERRCODE = 'exclusion_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- named "loan_z..." so it fires AFTER loan_set_dates has built loan_range
CREATE TRIGGER loan_z_no_overlap
    BEFORE INSERT OR UPDATE OF copy_id, loan_date, return_date ON loan
    FOR EACH ROW EXECUTE FUNCTION trg_no_overlapping_loan();

\echo '================================================================'
\echo ' STEP 6 - Migrate rows from loan_old into the partitioned loan'
\echo '================================================================'
-- Triggers on the new loan fire on this INSERT:
--   * trg_set_loan_dates() will rebuild loan_range from loan_date/due_date/return_date.
--   * trg_check_max_active_loans() and trg_check_unpaid_fines() re-validate.
-- We supply the existing loan_id so historical FKs from `fine` stay valid
-- against the new partitioned table too.
-- loan_old's EXCLUDE constraint already proved these rows do not overlap,
-- and the business triggers would reject historic rows (e.g. members who
-- had fines at the time), so the row triggers are paused for the copy only.
ALTER TABLE loan DISABLE TRIGGER USER;
INSERT INTO loan (loan_id, copy_id, member_id, loan_date, due_date, return_date, loan_range)
SELECT loan_id, copy_id, member_id, loan_date, due_date, return_date, loan_range
FROM   loan_old;
ALTER TABLE loan ENABLE TRIGGER USER;

\echo 'rows in loan_old vs partitioned loan (must match):'
SELECT (SELECT count(*) FROM loan_old) AS loan_old_rows, (SELECT count(*) FROM loan) AS loan_rows,
       (SELECT count(*) FROM loan_default) AS rows_in_default_partition;

-- FIX: fine.loan_id still pointed at loan_old, so any NEW fine for a NEW
-- loan would fail its foreign key. A foreign key to a partitioned table
-- must reference the full key (loan_id, loan_date), so fine gets loan_date.
ALTER TABLE fine ADD COLUMN IF NOT EXISTS loan_date TIMESTAMPTZ;
UPDATE fine f SET loan_date = l.loan_date FROM loan l WHERE l.loan_id = f.loan_id;
ALTER TABLE fine ALTER COLUMN loan_date SET NOT NULL;
ALTER TABLE fine DROP CONSTRAINT IF EXISTS fine_loan_id_fkey;
ALTER TABLE fine ADD CONSTRAINT fine_loan_fk
    FOREIGN KEY (loan_id, loan_date) REFERENCES loan (loan_id, loan_date);
-- reservation / other tables do not reference loan.

\echo '================================================================'
\echo ' STEP 7 - Sync the BIGSERIAL sequence to MAX(loan_id)'
\echo '================================================================'
SELECT setval(
    'loan_loan_id_seq',
    COALESCE((SELECT MAX(loan_id) FROM loan), 1),
    true
) AS new_seq_value;

\echo '================================================================'
\echo ' STEP 8 - Retain loan_old renamed as a backup (DO NOT DROP)'
\echo '================================================================'
-- DECISION: keep loan_old as a renamed read-only backup for the marker.
-- fine now references the partitioned loan (loan_id, loan_date), see STEP 6,
-- so loan_old can be dropped later without breaking anything:
--     DROP TABLE loan_old;

\echo '================================================================'
\endif

\echo ' STEP 9 - List the loan partitions'
\echo '================================================================'
SELECT
    n.nspname                              AS schema_name,
    c.relname                              AS partition_name,
    pg_get_expr(c.relpartbound, c.oid)     AS partition_bound,
    pg_size_pretty(pg_relation_size(c.oid)) AS size
FROM   pg_inherits  i
JOIN   pg_class     c       ON c.oid      = i.inhrelid
JOIN   pg_class     parent  ON parent.oid  = i.inhparent
JOIN   pg_namespace n       ON n.oid      = c.relnamespace
WHERE  parent.relname = 'loan'
ORDER  BY c.relname;

\echo 'rows per partition (newest 6 months):'
SELECT tableoid::regclass AS partition, count(*) AS loans
FROM loan GROUP BY 1 ORDER BY 1 DESC LIMIT 6;

\echo 'overlap guard test: a second loan of a copy that is already on loan must be rejected'
DO $$
DECLARE v_copy BIGINT; v_member BIGINT;
BEGIN
    SELECT copy_id INTO v_copy FROM loan WHERE return_date IS NULL LIMIT 1;
    SELECT m.member_id INTO v_member FROM member m
     WHERE NOT EXISTS (SELECT 1 FROM loan l WHERE l.member_id = m.member_id AND l.return_date IS NULL)
       AND NOT EXISTS (SELECT 1 FROM fine f JOIN loan l ON l.loan_id=f.loan_id WHERE l.member_id=m.member_id AND NOT f.paid)
     LIMIT 1;
    BEGIN
        INSERT INTO loan (copy_id, member_id, loan_date, due_date) VALUES (v_copy, v_member, NOW(), NULL);
        RAISE NOTICE 'OVERLAP TEST FAIL: second loan of copy % was accepted', v_copy;
    EXCEPTION WHEN exclusion_violation THEN
        RAISE NOTICE 'OVERLAP TEST PASS: %', SQLERRM;
    END;
END $$;

-- [paste real output here]

\echo '================================================================'
\echo ' STEP 10 - EXPLAIN: partition pruning on a single-month filter'
\echo '================================================================'
-- Filter to the current month so the planner scans ONLY ONE partition.
EXPLAIN (ANALYZE, SUMMARY)
SELECT loan_id, copy_id, member_id, loan_date, due_date, return_date
FROM   loan
WHERE  loan_date >= date_trunc('month', NOW())
  AND  loan_date <  date_trunc('month', NOW()) + INTERVAL '1 month';

-- [paste real output here]

\echo '================================================================'
\echo ' Partitioning complete. Next: 02_replica_setup.sh and 03_replica_demo.sh (run_p5.sh runs both).'
\echo '================================================================'
