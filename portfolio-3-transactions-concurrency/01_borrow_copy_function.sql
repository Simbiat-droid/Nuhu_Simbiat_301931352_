-- =============================================================================
-- 01_borrow_copy_function.sql
-- Portfolio 3 — Transactions and Concurrency
-- Student: Nuhu Simbiat · 2026/A/MIT/0955 · MIT 8103 · Miva Open University
-- Case study: ReadWell Libraries
-- =============================================================================
--
-- Installs a single PL/pgSQL function:
--
--     borrow_copy(p_member_id BIGINT,
--                p_book_id   BIGINT,
--                p_branch_id BIGINT)
--        RETURNS BIGINT
--
-- Behaviour
-- ---------
--   The function is meant to be called *inside* the caller's transaction:
--
--       BEGIN;
--       SELECT borrow_copy(<member>, <book>, <branch>);
--       COMMIT;
--
--   Inside the function:
--     1. SELECT one available copy of the book at the branch, locking the row
--        with FOR UPDATE so concurrent callers serialise on the same copy.
--     2. If a free copy was found:
--          INSERT INTO loan (copy_id, member_id, loan_date, due_date)
--          -- the BEFORE-INSERT triggers (Portfolio 1) enforce:
--          --   * due_date = loan_date + 14 days
--          --   * loan_range is built
--          --   * member has < 5 active loans
--          --   * member has unpaid fines <= NGN 2,000
--          UPDATE copy SET status='on_loan' WHERE copy_id = ...;
--          RETURN the copy_id.
--     3. If no free copy was found:
--          INSERT INTO reservation (book_id, member_id, branch_id, reserved_at)
--          RETURN NULL.   -- NULL acts as the "reserved for you" marker
--     4. On ANY error, an EXCEPTION WHEN OTHERS block lets the function roll
--        back its internal sub-transaction (the savepoint the EXCEPTION block
--        establishes) and then RE-RAISES so the caller can ROLLBACK the
--        outer transaction.
--
-- The exclusion constraint loan_copy_id_loan_range_excl is the LAST line of
-- defence: even if two callers somehow selected the same copy without the
-- FOR UPDATE serialising them, the second INSERT would be rejected.
-- =============================================================================

DROP FUNCTION IF EXISTS borrow_copy(BIGINT, BIGINT, BIGINT);

CREATE OR REPLACE FUNCTION borrow_copy(
    p_member_id BIGINT,
    p_book_id   BIGINT,
    p_branch_id BIGINT
) RETURNS BIGINT AS $$
DECLARE
    v_copy_id   BIGINT;
    v_loan_id   BIGINT;
BEGIN
    ------------------------------------------------------------------
    -- 1) Pick one available copy at the branch and lock the row.
    --    ORDER BY copy_id gives deterministic selection (deterministic
    --    is useful for demos). FOR UPDATE blocks other callers on the
    --    same copy until this transaction COMMITs / ROLLBACKs.
    ------------------------------------------------------------------
    SELECT c.copy_id
      INTO v_copy_id
      FROM copy c
     WHERE c.book_id   = p_book_id
       AND c.branch_id = p_branch_id
       AND c.status    = 'available'
     ORDER BY c.copy_id
     LIMIT 1
     FOR UPDATE;

    ------------------------------------------------------------------
    -- 2) Branch on whether a free copy was found.
    ------------------------------------------------------------------
    IF v_copy_id IS NOT NULL THEN
        -- Borrow it.
        INSERT INTO loan (copy_id, member_id, loan_date, due_date)
        VALUES (v_copy_id, p_member_id, NOW(), NOW() + INTERVAL '14 days')
        RETURNING loan_id INTO v_loan_id;

        -- Mark the physical copy as on loan.
        UPDATE copy
           SET status = 'on_loan'
         WHERE copy_id = v_copy_id;

        -- Return the copy_id so the caller knows which physical copy
        -- was handed to the member.
        RETURN v_copy_id;
    ELSE
        -- No free copy at this branch right now: reserve the title for
        -- the member so they are notified when a copy comes back.
        INSERT INTO reservation (book_id, member_id, branch_id, reserved_at)
        VALUES (p_book_id, p_member_id, p_branch_id, NOW());

        -- NULL is the "reserved for you" marker.
        RETURN NULL;
    END IF;

    ------------------------------------------------------------------
    -- 3) Error handling: any failure (max-loans trigger, unpaid-fines
    --    trigger, exclusion constraint, FK violation, ...) is caught
    --    here. The EXCEPTION block establishes an internal sub-transaction
    --    (savepoint); on entry to the handler the sub-transaction is
    --    already rolled back, so partial INSERTs/UPDATEs above are undone.
    --    We RE-RAISE so the caller's outer transaction is also marked
    --    aborted, and the caller can then ROLLBACK.
    ------------------------------------------------------------------
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'borrow_copy failed: %', SQLERRM;
        RAISE;   -- re-raise; caller's BEGIN; ... ; COMMIT/ROLLBACK decides
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- Usage example (uncomment to try):
--
--   BEGIN;
--   SELECT borrow_copy(<member_id>, <book_id>, <branch_id>);
--   COMMIT;
--
-- Concrete example using the test data created by 02_commit_rollback_demo.sql
-- (member 9001, book 9001, branch 9001, copy 9001). It expects copy 9001 to
-- be 'available' first — re-run 02_commit_rollback_demo.sql to reset, or:
--   UPDATE copy SET status='available' WHERE copy_id=9001;
--   DELETE FROM loan WHERE copy_id=9001 AND return_date IS NULL;
--
--   BEGIN;
--   SELECT * FROM borrow_copy(9001, 9001, 9001);
--   COMMIT;
--
-- Expected return when a copy is free:  9001   (the copy_id that was borrowed)
-- Expected return when no copy is free: (NULL) — and a reservation row appears:
--   SELECT * FROM reservation WHERE member_id = 9001 ORDER BY reserved_at DESC LIMIT 1;
-- =============================================================================
