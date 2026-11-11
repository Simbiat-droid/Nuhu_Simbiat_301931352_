#!/usr/bin/env bash
# =============================================================================
# 03_replica_demo.sh - Portfolio 5 replication demo in ONE script
# ReadWell Libraries - Nuhu Simbiat - 2026/A/MIT/0955
#
# Switches between the PRIMARY (port 5432) and the READ REPLICA (port 5433)
# by itself, so every step is real output from the right server:
#   1. who is who (port, pg_is_in_recovery)
#   2. a write on the replica is REJECTED (read-only)
#   3. insert a branch on the primary -> the row ARRIVES on the replica
#   4. replication lag (bytes + seconds) and pg_stat_replication
#   5. partition pruning on the partitioned loan table (primary)
# run_p5.sh saves the output to replication_output.log.
# Replaces the copy-paste steps that used to be in 03_replica_demo.sql.
# =============================================================================
set -euo pipefail
DB=readwell
SOCK=/var/run/postgresql
P() { sudo runuser -u postgres -- psql -X -d "$DB" -h "$SOCK" -p 5432 "$@"; }
R() { sudo runuser -u postgres -- psql -X -d "$DB" -h "$SOCK" -p 5433 "$@"; }
line() { echo "----------------------------------------------------------------"; }

line; echo "1. WHO IS WHO"; line
echo "[PRIMARY]"
P -c "SELECT current_setting('port') AS port, pg_is_in_recovery() AS is_replica, now() AS checked_at;"
echo "[REPLICA]"
R -c "SELECT current_setting('port') AS port, pg_is_in_recovery() AS is_replica, now() AS checked_at;"

line; echo "2. A WRITE ON THE REPLICA IS REJECTED"; line
echo "[REPLICA] INSERT INTO branch (name, city) VALUES ('Reject Test', 'Lagos');"
if R -v ON_ERROR_STOP=1 -c "INSERT INTO branch (name, city) VALUES ('Reject Test', 'Lagos');" 2>&1; then
    echo "UNEXPECTED: the replica accepted a write"
else
    echo "=> rejected as expected: the standby is read-only"
fi

line; echo "3. INSERT ON THE PRIMARY -> ROW ARRIVES ON THE REPLICA"; line
TAG="Replica Test $(date +%H%M%S)"
echo "[PRIMARY] INSERT branch '$TAG'"
P -v ON_ERROR_STOP=1 -c "INSERT INTO branch (name, city, address) VALUES ('$TAG', 'Kaduna', 'replication demo') RETURNING branch_id, name, created_at;"
start=$(date +%s.%N)
for i in $(seq 1 50); do
    n=$(R -At -c "SELECT count(*) FROM branch WHERE name = '$TAG';")
    [ "$n" = "1" ] && break
    sleep 0.1
done
end=$(date +%s.%N)
echo "[REPLICA] SELECT ... WHERE name = '$TAG'"
R -c "SELECT branch_id, name, city, created_at FROM branch WHERE name = '$TAG';"
echo "=> row visible on the replica after about $(awk "BEGIN{printf \"%.2f\", $end-$start}") s of polling"

line; echo "4. REPLICATION LAG"; line
echo "[PRIMARY] pg_stat_replication"
P -c "SELECT application_name, client_addr, state, sync_state, sent_lsn, replay_lsn,
             pg_wal_lsn_diff(sent_lsn, replay_lsn) AS byte_lag, replay_lag
      FROM pg_stat_replication;"
echo "[REPLICA] last replayed position and delay"
R -c "SELECT pg_last_wal_receive_lsn() AS received_lsn, pg_last_wal_replay_lsn() AS replayed_lsn,
             now() - pg_last_xact_replay_timestamp() AS time_since_last_replayed_txn;"

line; echo "5. PARTITION PRUNING (PRIMARY): loans of the current month only"; line
P -c "EXPLAIN (ANALYZE, COSTS OFF, SUMMARY OFF)
      SELECT count(*) FROM loan
      WHERE loan_date >= date_trunc('month', CURRENT_DATE)
        AND loan_date <  date_trunc('month', CURRENT_DATE) + INTERVAL '1 month';"
echo "[REPLICA] the same partitioned table is readable on the replica:"
R -c "SELECT count(*) AS loans_this_month FROM loan
      WHERE loan_date >= date_trunc('month', CURRENT_DATE);"

echo
echo "Replication demo finished."
