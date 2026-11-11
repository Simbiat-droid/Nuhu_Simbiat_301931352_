#!/usr/bin/env python3
"""
run_race_demos.py - Portfolio 3, ReadWell Libraries (Nuhu Simbiat, 2026/A/MIT/0955)

Runs the SIX two-terminal concurrency demos automatically with TWO real
PostgreSQL sessions ("Terminal A" and "Terminal B") plus a thread for the
session that has to wait. A third "observer" session reads pg_stat_activity
to PROVE that B is blocked on a lock. Every line printed is real output from
the database - nothing is typed in by hand. run_p3.sh saves it to
race_demos_output.log.

  Part 1  THE BUG      naive check-then-insert, no constraint -> double loan
  Part 2  FIX 1        EXCLUDE constraint on loan rejects the second loan
  Part 3  FIX 2        borrow_copy() with SELECT ... FOR UPDATE -> B waits,
                       then gets a reservation instead of an error
  Part 4  SERIALIZABLE two writers on the same fine -> one is aborted
  Part 5  READ COMMITTED vs REPEATABLE READ (non-repeatable read / snapshot)
  Part 6  DEADLOCK     A locks 9201 then 9202, B locks 9202 then 9201

The manual step-by-step versions are still in 03_race_condition_guide.md,
04_isolation_levels.sql and 05_deadlock_demo.sql (same IDs: 91xx/92xx/93xx).

Connects through the Unix socket (/var/run/postgresql) as the Codespace
user's own PostgreSQL role (created by setup.sh) - no TCP, no password.
"""
import getpass
import sys
import threading
import time

import psycopg2

DSN = f"host=/var/run/postgresql dbname=readwell user={getpass.getuser()}"


def say(msg=""):
    print(msg, flush=True)


def session(name):
    conn = psycopg2.connect(DSN, application_name=name)
    conn.autocommit = True          # we issue BEGIN / COMMIT ourselves
    return conn


def run(conn, label, sql, params=None, fetch=True):
    """Run one statement as `label`, print it and its real result."""
    say(f"[{label}] {' '.join(sql.split())}")
    cur = conn.cursor()
    try:
        cur.execute(sql, params)
    except psycopg2.Error as e:
        say(f"[{label}] {e.pgerror.strip() if e.pgerror else e}")
        raise
    finally:
        for n in conn.notices:
            say(f"[{label}] {n.strip()}")
        del conn.notices[:]
    if fetch and cur.description:
        cols = [d[0] for d in cur.description]
        rows = cur.fetchall()
        say(f"[{label}]   -> {cols}: {rows}")
        return rows
    say(f"[{label}]   -> {cur.statusmessage}")
    return None


class Waiter(threading.Thread):
    """Runs one statement in Terminal B's session so it can block."""

    def __init__(self, conn, label, sql):
        super().__init__(daemon=True)
        self.conn, self.label, self.sql = conn, label, sql
        self.rows, self.error, self.t0, self.t1 = None, None, None, None

    def run(self):
        self.t0 = time.time()
        try:
            self.rows = run(self.conn, self.label, self.sql)
        except psycopg2.Error as e:
            self.error = e
        self.t1 = time.time()


def show_blocked(obs, who):
    rows = run(obs, "observer",
               "SELECT application_name, state, wait_event_type, wait_event "
               "FROM pg_stat_activity WHERE application_name = %s", (who,))
    if rows and rows[0][2] == "Lock":
        say(f"[observer] => {who} is BLOCKED, waiting for a lock held by the other session")
    return rows


def start_and_check_block(b, label, sql, obs, who):
    w = Waiter(b, label, sql)
    w.start()
    time.sleep(1.5)
    say(f"[{label}] (still running after 1.5 s: {w.is_alive()})")
    show_blocked(obs, who)
    return w


def header(title):
    say()
    say("=" * 74)
    say(title)
    say("=" * 74)


def setup(c):
    header("SETUP - demo rows (IDs 91xx race, 92xx deadlock, 93xx isolation)")
    for sql in [
        "DROP TABLE IF EXISTS loan_naive",
        "DELETE FROM fine WHERE loan_id IN (SELECT loan_id FROM loan WHERE member_id IN (9101,9102,9301))",
        "DELETE FROM loan WHERE member_id IN (9101,9102,9301) OR copy_id IN (9101,9201,9202,9301,9302)",
        "DELETE FROM reservation WHERE member_id IN (9101,9102,9301)",
        "INSERT INTO branch (branch_id,name,city) VALUES (9101,'Race Branch','Lagos'),(9301,'Iso Branch','Lagos') ON CONFLICT (branch_id) DO NOTHING",
        "INSERT INTO member (member_id,first_name,last_name,email,home_branch_id) VALUES "
        "(9101,'Adaeze','Okafor','adaeze.race@test.local',9101),(9102,'Bolaji','Adeyemi','bolaji.race@test.local',9101),"
        "(9301,'Iso','Member','iso.member@test.local',9301) ON CONFLICT (member_id) DO NOTHING",
        "INSERT INTO book (book_id,title,isbn,category) VALUES (9101,'Race Title','978-0000-9101','Fiction'),"
        "(9201,'Deadlock Title','978-0000-9201','Fiction'),(9301,'Iso Book 1','978-0000-9301','Fiction') ON CONFLICT (book_id) DO NOTHING",
        "INSERT INTO copy (copy_id,book_id,branch_id,barcode,status) VALUES "
        "(9101,9101,9101,'RACE-9101','available'),(9201,9201,9101,'DL-9201','available'),"
        "(9202,9201,9101,'DL-9202','available'),(9301,9301,9301,'ISO-9301','available') "
        "ON CONFLICT (copy_id) DO UPDATE SET status='available'",
        # old returned loan on copy 9301 + an unpaid NGN 1,500 fine for the isolation demos
        "INSERT INTO loan (copy_id,member_id,loan_date,due_date,return_date) "
        "VALUES (9301,9301,NOW()-INTERVAL '40 days',NULL,NOW()-INTERVAL '20 days')",
        "INSERT INTO fine (loan_id,amount,paid) SELECT loan_id,1500.00,FALSE FROM loan WHERE member_id=9301",
    ]:
        run(c, "setup", sql)
    run(c, "setup", "SELECT copy_id, book_id, branch_id, status FROM copy WHERE copy_id=9101")


def part1_bug(a, b):
    header("PART 1 - THE BUG: check-then-insert with NO constraint (loan_naive)\n"
           "loan_naive is a copy of loan's columns WITHOUT the EXCLUDE constraint,\n"
           "i.e. what the database would allow if Portfolio 1 had not added it.")
    run(a, "setup", "CREATE TABLE loan_naive (LIKE loan INCLUDING DEFAULTS)")
    run(a, "Terminal A", "BEGIN")
    run(a, "Terminal A", "SELECT count(*) AS active_loans_on_9101 FROM loan_naive WHERE copy_id=9101 AND return_date IS NULL")
    run(b, "Terminal B", "BEGIN")
    run(b, "Terminal B", "SELECT count(*) AS active_loans_on_9101 FROM loan_naive WHERE copy_id=9101 AND return_date IS NULL")
    say("-- both sessions saw 0 active loans, so both 'decide' the copy is free --")
    ins = ("INSERT INTO loan_naive (copy_id,member_id,loan_date,due_date,loan_range) VALUES "
           "(9101,{m},NOW(),NOW()+INTERVAL '14 days',tstzrange(NOW(),NOW()+INTERVAL '14 days'))")
    run(a, "Terminal A", ins.format(m=9101))
    run(a, "Terminal A", "COMMIT")
    run(b, "Terminal B", ins.format(m=9102))
    run(b, "Terminal B", "COMMIT")
    rows = run(a, "check", "SELECT copy_id, member_id, loan_range FROM loan_naive WHERE copy_id=9101 ORDER BY member_id")
    say(f"RESULT PART 1: {len(rows)} overlapping loans of ONE physical copy -> "
        f"{'BUG REPRODUCED (lost update / double booking)' if len(rows) == 2 else 'not reproduced'}")
    run(a, "cleanup", "DROP TABLE loan_naive")


def part2_exclude(a, b, obs):
    header("PART 2 - FIX 1: the EXCLUDE constraint on loan(copy_id, loan_range)")
    run(a, "Terminal A", "BEGIN")
    run(a, "Terminal A", "SELECT copy_id, status FROM copy WHERE copy_id=9101 AND status='available'")
    run(b, "Terminal B", "BEGIN")
    run(b, "Terminal B", "SELECT copy_id, status FROM copy WHERE copy_id=9101 AND status='available'")
    run(a, "Terminal A", "INSERT INTO loan (copy_id,member_id,loan_date,due_date) VALUES (9101,9101,NOW(),NULL)")
    run(a, "Terminal A", "UPDATE copy SET status='on_loan' WHERE copy_id=9101")
    w = start_and_check_block(b, "Terminal B",
                              "INSERT INTO loan (copy_id,member_id,loan_date,due_date) VALUES (9101,9102,NOW(),NULL)",
                              obs, "Terminal B")
    run(a, "Terminal A", "COMMIT")
    w.join(10)
    say(f"[Terminal B] waited {w.t1 - w.t0:.2f} s, then: "
        f"{'REJECTED by ' + w.error.diag.constraint_name if w.error else 'INSERTED (unexpected)'}")
    run(b, "Terminal B", "ROLLBACK")
    rows = run(a, "check", "SELECT member_id, copy_id FROM loan WHERE copy_id=9101 AND return_date IS NULL")
    say(f"RESULT PART 2: {len(rows)} active loan on copy 9101 (only Terminal A's) - no double loan")


def reset_9101(c):
    run(c, "reset", "DELETE FROM loan WHERE member_id IN (9101,9102)")
    run(c, "reset", "DELETE FROM reservation WHERE member_id IN (9101,9102)")
    run(c, "reset", "UPDATE copy SET status='available' WHERE copy_id=9101")


def part3_for_update(a, b, obs):
    header("PART 3 - FIX 2: borrow_copy() uses SELECT ... FOR UPDATE\n"
           "B waits for A, re-checks the row, finds it on_loan and is RESERVED instead")
    reset_9101(a)
    run(a, "Terminal A", "BEGIN")
    run(a, "Terminal A", "SELECT borrow_copy(9101, 9101, 9101) AS copy_borrowed")
    run(b, "Terminal B", "BEGIN")
    w = start_and_check_block(b, "Terminal B", "SELECT borrow_copy(9102, 9101, 9101) AS copy_borrowed",
                              obs, "Terminal B")
    run(a, "Terminal A", "COMMIT")
    w.join(10)
    say(f"[Terminal B] waited {w.t1 - w.t0:.2f} s, borrow_copy returned {w.rows} "
        f"(NULL = no copy left, a reservation was created)")
    run(b, "Terminal B", "COMMIT")
    run(a, "check", "SELECT member_id, book_id, branch_id, fulfilled_at FROM reservation WHERE member_id=9102")
    run(a, "check", "SELECT copy_id, status FROM copy WHERE copy_id=9101")
    run(a, "check", "SELECT member_id, copy_id FROM loan WHERE copy_id=9101 AND return_date IS NULL")
    say("RESULT PART 3: A got the copy, B got a reservation - no error, no double loan")


FINE = "(SELECT f.fine_id FROM fine f JOIN loan l ON l.loan_id=f.loan_id WHERE l.member_id=9301 LIMIT 1)"


def part4_serializable(a, b, obs):
    header("PART 4 - SERIALIZABLE: two librarians add a charge to the SAME fine")
    run(a, "reset", f"UPDATE fine SET amount=1500.00 WHERE fine_id={FINE}")
    run(a, "Terminal A", "BEGIN ISOLATION LEVEL SERIALIZABLE")
    run(a, "Terminal A", f"SELECT fine_id, amount FROM fine WHERE fine_id={FINE}")
    run(b, "Terminal B", "BEGIN ISOLATION LEVEL SERIALIZABLE")
    run(b, "Terminal B", f"SELECT fine_id, amount FROM fine WHERE fine_id={FINE}")
    run(a, "Terminal A", f"UPDATE fine SET amount = amount + 100 WHERE fine_id={FINE}")
    w = start_and_check_block(b, "Terminal B", f"UPDATE fine SET amount = amount + 200 WHERE fine_id={FINE}",
                              obs, "Terminal B")
    run(a, "Terminal A", "COMMIT")
    w.join(10)
    say(f"[Terminal B] -> {'ERROR (SQLSTATE ' + w.error.pgcode + ')' if w.error else 'succeeded'}")
    run(b, "Terminal B", "ROLLBACK")
    rows = run(a, "check", f"SELECT amount FROM fine WHERE fine_id={FINE}")
    say(f"RESULT PART 4: final amount = {rows[0][0]} (1500 + A's 100 only; B must retry, no lost update)")


def part5_isolation(a, b):
    header("PART 5 - READ COMMITTED vs REPEATABLE READ")
    run(a, "reset", f"UPDATE fine SET amount=1500.00 WHERE fine_id={FINE}")
    say("-- 5a READ COMMITTED: A reads, B updates + commits, A reads again --")
    run(a, "Terminal A", "BEGIN ISOLATION LEVEL READ COMMITTED")
    r1 = run(a, "Terminal A", f"SELECT amount FROM fine WHERE fine_id={FINE}")
    run(b, "Terminal B", f"UPDATE fine SET amount = 2000.00 WHERE fine_id={FINE}")
    r2 = run(a, "Terminal A", f"SELECT amount FROM fine WHERE fine_id={FINE}")
    run(a, "Terminal A", "COMMIT")
    say(f"RESULT 5a: first read {r1[0][0]}, second read {r2[0][0]} inside ONE transaction "
        f"-> {'non-repeatable read' if r1 != r2 else 'same value'}")
    run(a, "reset", f"UPDATE fine SET amount=1500.00 WHERE fine_id={FINE}")
    say("-- 5b REPEATABLE READ: same steps --")
    run(a, "Terminal A", "BEGIN ISOLATION LEVEL REPEATABLE READ")
    r1 = run(a, "Terminal A", f"SELECT amount FROM fine WHERE fine_id={FINE}")
    run(b, "Terminal B", f"UPDATE fine SET amount = 2000.00 WHERE fine_id={FINE}")
    r2 = run(a, "Terminal A", f"SELECT amount FROM fine WHERE fine_id={FINE}")
    run(a, "Terminal A", "COMMIT")
    r3 = run(a, "Terminal A", f"SELECT amount FROM fine WHERE fine_id={FINE}")
    say(f"RESULT 5b: reads inside the transaction {r1[0][0]} and {r2[0][0]} (snapshot), "
        f"after COMMIT {r3[0][0]}")
    say("-- 5c REPEATABLE READ hides a phantom: B inserts an active loan for member 9301 --")
    run(a, "Terminal A", "BEGIN ISOLATION LEVEL REPEATABLE READ")
    c1 = run(a, "Terminal A", "SELECT count(*) AS active_loans FROM loan WHERE member_id=9301 AND return_date IS NULL")
    run(b, "Terminal B", "INSERT INTO loan (copy_id,member_id,loan_date,due_date) VALUES (9301,9301,NOW(),NULL)")
    c2 = run(a, "Terminal A", "SELECT count(*) AS active_loans FROM loan WHERE member_id=9301 AND return_date IS NULL")
    run(a, "Terminal A", "COMMIT")
    c3 = run(a, "Terminal A", "SELECT count(*) AS active_loans FROM loan WHERE member_id=9301 AND return_date IS NULL")
    say(f"RESULT 5c: inside REPEATABLE READ {c1[0][0]} then {c2[0][0]} (phantom hidden); new snapshot {c3[0][0]}")
    run(a, "reset", "DELETE FROM loan WHERE member_id=9301 AND return_date IS NULL")
    run(a, "reset", f"UPDATE fine SET amount=1500.00 WHERE fine_id={FINE}")


def part6_deadlock(a, b, obs):
    header("PART 6 - DEADLOCK: A locks 9201 then 9202, B locks 9202 then 9201")
    run(a, "Terminal A", "BEGIN")
    run(a, "Terminal A", "SELECT copy_id, status FROM copy WHERE copy_id=9201 FOR UPDATE")
    run(b, "Terminal B", "BEGIN")
    run(b, "Terminal B", "SELECT copy_id, status FROM copy WHERE copy_id=9202 FOR UPDATE")
    wa = Waiter(a, "Terminal A", "SELECT copy_id, status FROM copy WHERE copy_id=9202 FOR UPDATE")
    wa.start()
    time.sleep(1.5)
    say(f"[Terminal A] (still running after 1.5 s: {wa.is_alive()})")
    show_blocked(obs, "Terminal A")
    wb = Waiter(b, "Terminal B", "SELECT copy_id, status FROM copy WHERE copy_id=9201 FOR UPDATE")
    wb.start()
    wa.join(15)
    wb.join(15)
    for name, w, conn in (("Terminal A", wa, a), ("Terminal B", wb, b)):
        if w.error:
            say(f"[{name}] VICTIM: SQLSTATE {w.error.pgcode} (40P01 = deadlock_detected)")
            run(conn, name, "ROLLBACK")
        else:
            say(f"[{name}] SURVIVOR: its blocked SELECT returned {w.rows}")
            run(conn, name, "COMMIT")
    say("RESULT PART 6: PostgreSQL detected the cycle (deadlock_timeout = 1 s) and aborted one\n"
        "transaction. Prevention: always lock copies in a fixed order (lowest copy_id first).")


def main():
    say("ReadWell Libraries - Portfolio 3 two-session concurrency demos")
    a, b, obs = session("Terminal A"), session("Terminal B"), session("observer")
    run(obs, "observer", "SELECT current_user, current_database(), version()")
    setup(a)
    part1_bug(a, b)
    part2_exclude(a, b, obs)
    part3_for_update(a, b, obs)
    part4_serializable(a, b, obs)
    part5_isolation(a, b)
    part6_deadlock(a, b, obs)
    header("ALL SIX DEMOS FINISHED")
    for c in (a, b, obs):
        c.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # make a failure obvious in the log and to set -e
        say(f"DEMO FAILED: {e}")
        sys.exit(1)
