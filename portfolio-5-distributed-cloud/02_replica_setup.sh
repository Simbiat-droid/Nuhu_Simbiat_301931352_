#!/usr/bin/env bash
# =============================================================================
# 02_replica_setup.sh - Portfolio 5
# Set up a PostgreSQL 16 streaming READ replica for ReadWell's online
# catalogue search. The replica runs on port 5433 against the same host
# (Codespaces dev container) - it is the offline/branch-search stand-in.
#
# Student  : Nuhu Simbiat
# Matric   : 2026/A/MIT/0955
# Database : readwell  (PostgreSQL 16)
#
# Called by run_p5.sh (it can also be run on its own):
#
#     bash portfolio-5-distributed-cloud/02_replica_setup.sh
#
# PREREQUISITES
#   * Portfolio 1 schema applied to `readwell`.
#   * Portfolio 5 / 01_partitioning.sql applied (loan is now partitioned).
#   * Codespaces: you have root via `sudo`.
#
# CODESPACES RULES FOLLOWED
#   * sudo only as root - we always use `sudo runuser -u postgres -- ...`
#     (never `sudo -u postgres`).
#   * PostgreSQL 16 config:  /etc/postgresql/16/main/
#   * pg_ctl:                /usr/lib/postgresql/16/bin/pg_ctl
#   * pg_basebackup:         /usr/lib/postgresql/16/bin/pg_basebackup
#   * pg_hba.conf trust lines go at the TOP of the file.
#   * Connect via Unix socket; no TCP logins.
#   * No postgres_fdw.
#
# WHAT THIS SCRIPT DOES (high level)
#   1. Edit /etc/postgresql/16/main/postgresql.conf on the PRIMARY for
#      wal_level=replica, max_wal_senders=10, max_replication_slots=10,
#      listen_addresses='localhost'.
#   2. PREPEND replication trust lines to the TOP of pg_hba.conf on primary.
#   3. Restart the primary.
#   4. Stop any leftover replica cluster; wipe /var/lib/postgresql/16/replica.
#   5. pg_basebackup with -R -C -S replica_slot to clone the primary into
#      the replica data dir.
#   6. Write a SEPARATE postgresql.conf at /etc/postgresql/16/replica/
#      (port=5433, data_directory, hot_standby=on).
#   7. Write the replica's pg_hba.conf allowing local trust.
#   8. Start the replica with pg_ctl (NOT systemctl - it is not a registered
#      service).
#   9. Print status checks on primary (pg_stat_replication) and on replica
#      (pg_is_in_recovery() == true).
# =============================================================================

set -euo pipefail

PGVER=16
DB=readwell
SLOT=replica_slot
REPLICA_PORT=5433

PGDATA_PRIMARY=/var/lib/postgresql/${PGVER}/main
PGDATA_REPLICA=/var/lib/postgresql/${PGVER}/replica
PGCONF_PRIMARY=/etc/postgresql/${PGVER}/main/postgresql.conf
PGHBA_PRIMARY=/etc/postgresql/${PGVER}/main/pg_hba.conf
# FIX: keep the replica's config INSIDE its data dir. A folder under
# /etc/postgresql/16/ is picked up by Ubuntu's postgresql-common as a second
# "cluster" and confuses pg_lsclusters / service postgresql start.
PGCONF_REPLICA_DIR=/var/lib/postgresql/${PGVER}/replica
PGCONF_REPLICA=${PGCONF_REPLICA_DIR}/postgresql.conf
PGHBA_REPLICA=${PGDATA_REPLICA}/pg_hba.conf
PGCTL=/usr/lib/postgresql/${PGVER}/bin/pg_ctl
PGBASEBACKUP=/usr/lib/postgresql/${PGVER}/bin/pg_basebackup
SOCKET_DIR=/var/run/postgresql

echo "================================================================"
echo " ReadWell Libraries - streaming replica setup (Portfolio 5)"
echo " Student: Nuhu Simbiat - 2026/A/MIT/0955"
echo " Primary data dir : ${PGDATA_PRIMARY}"
echo " Replica data dir : ${PGDATA_REPLICA}"
echo " Replica port     : ${REPLICA_PORT}"
echo " Replication slot : ${SLOT}"
echo "================================================================"

# ---------------------------------------------------------------------------
# STEP 1 - Configure the PRIMARY for replication
# ---------------------------------------------------------------------------
echo
echo "== STEP 1: Configure PRIMARY postgresql.conf for replication =="
echo "   wal_level=replica, max_wal_senders=10, max_replication_slots=10,"
echo "   listen_addresses='localhost'"

# One-time backup of the original config (so we can roll back if needed).
if [ ! -f "${PGCONF_PRIMARY}.orig" ]; then
    sudo cp "${PGCONF_PRIMARY}" "${PGCONF_PRIMARY}.orig"
    echo "   backed up original -> ${PGCONF_PRIMARY}.orig"
fi

# Replace any existing setting lines (commented or not) with the new values.
sudo sed -i \
    -e "s|^[#[:space:]]*wal_level .*|wal_level = replica|" \
    -e "s|^[#[:space:]]*max_wal_senders .*|max_wal_senders = 10|" \
    -e "s|^[#[:space:]]*max_replication_slots .*|max_replication_slots = 10|" \
    -e "s|^[#[:space:]]*listen_addresses .*|listen_addresses = 'localhost'|" \
    "${PGCONF_PRIMARY}"

# Belt-and-braces: if a setting is still missing (no line existed), append it.
ensure_setting () {
    local key="$1" value="$2"
    if ! sudo grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "${PGCONF_PRIMARY}"; then
        echo "${key} = ${value}" | sudo tee -a "${PGCONF_PRIMARY}" >/dev/null
    fi
}
ensure_setting wal_level             "replica"
ensure_setting max_wal_senders       "10"
ensure_setting max_replication_slots "10"
ensure_setting listen_addresses       "'localhost'"

echo "   primary postgresql.conf updated."

# ---------------------------------------------------------------------------
# STEP 2 - PREPEND replication trust lines to the TOP of pg_hba.conf
#          (must be above the existing `local all all peer` line)
# ---------------------------------------------------------------------------
echo
echo "== STEP 2: PREPEND replication trust lines to TOP of pg_hba.conf =="

if [ ! -f "${PGHBA_PRIMARY}.orig" ]; then
    sudo cp "${PGHBA_PRIMARY}" "${PGHBA_PRIMARY}.orig"
    echo "   backed up original -> ${PGHBA_PRIMARY}.orig"
fi

# Remove any previously prepended P5 block (idempotent re-runs).
sudo sed -i '/# BEGIN P5 REPLICATION TRUST/,/# END P5 REPLICATION TRUST/d' "${PGHBA_PRIMARY}"

# Build the new pg_hba.conf: P5 trust block first, then the cleaned body.
{
    sudo cat <<'EOF'
# BEGIN P5 REPLICATION TRUST  (must be at the TOP of the file)
local   replication     postgres                                  trust
host    replication     postgres        127.0.0.1/32              trust
host    replication     postgres        ::1/128                   trust
# END P5 REPLICATION TRUST
EOF
    sudo cat "${PGHBA_PRIMARY}"
} | sudo tee "${PGHBA_PRIMARY}.new" >/dev/null

sudo mv "${PGHBA_PRIMARY}.new" "${PGHBA_PRIMARY}"
sudo chown postgres:postgres "${PGHBA_PRIMARY}"
sudo chmod 640 "${PGHBA_PRIMARY}"
echo "   pg_hba.conf trust block now at the TOP of the file."

# ---------------------------------------------------------------------------
# STEP 3 - Restart the primary so the new settings take effect
# ---------------------------------------------------------------------------
echo
echo "== STEP 3: Restart PostgreSQL primary =="
# FIX: Codespaces has no systemd, so "systemctl restart" fails under set -e.
sudo pg_ctlcluster ${PGVER} main restart
sleep 2
echo "   primary restarted."

# Sanity: confirm the settings are live.
echo "   live settings:"
sudo runuser -u postgres -- psql -d postgres -At -c \
    "SELECT name||' = '||setting FROM pg_settings WHERE name IN ('wal_level','max_wal_senders','max_replication_slots','listen_addresses') ORDER BY name;"

# ---------------------------------------------------------------------------
# STEP 4 - Stop any existing replica cluster and clean the replica data dir
# ---------------------------------------------------------------------------
echo
echo "== STEP 4: Stop any existing replica cluster on port ${REPLICA_PORT} =="

if sudo test -f "${PGDATA_REPLICA}/postmaster.pid"; then
    echo "   stopping existing replica (postmaster.pid found)..."
    sudo runuser -u postgres -- "${PGCTL}" -D "${PGDATA_REPLICA}" -m fast stop || true   # FIX: was "-m stop" (invalid mode, replica kept running)
    sleep 2
fi

# pg_basebackup requires an empty target directory; wipe and recreate.
sudo rm -rf "${PGDATA_REPLICA}"
sudo mkdir -p "${PGDATA_REPLICA}"
sudo chown postgres:postgres "${PGDATA_REPLICA}"
sudo chmod 700 "${PGDATA_REPLICA}"

# Drop the replication slot from a previous run, if it survived.
sudo runuser -u postgres -- psql -d postgres -c \
    "SELECT pg_drop_replication_slot('${SLOT}') WHERE EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name='${SLOT}');" \
    || true

echo "   replica data dir is now empty: ${PGDATA_REPLICA}"

# ---------------------------------------------------------------------------
# STEP 5 - pg_basebackup to clone the primary into the replica data dir
#          -h /var/run/postgresql  (Unix socket, never TCP login)
#          -X stream               (stream WAL during the backup)
#          -C -S replica_slot       (create a physical replication slot)
#          -R                       (write standby.signal + primary_conninfo
#                                    into postgresql.auto.conf on the replica)
# ---------------------------------------------------------------------------
echo
echo "== STEP 5: pg_basebackup (clone primary -> replica via Unix socket) =="

sudo runuser -u postgres -- "${PGBASEBACKUP}" \
    -h "${SOCKET_DIR}" \
    -D "${PGDATA_REPLICA}" \
    -U postgres \
    -X stream \
    -C -S "${SLOT}" \
    -R \
    -c fast

echo "   base backup complete."
echo "   standby.signal written by -R:"
sudo ls -l "${PGDATA_REPLICA}/standby.signal" || true
echo "   primary_conninfo recorded in postgresql.auto.conf:"
sudo grep -E "primary_conninfo|primary_slot_name" "${PGDATA_REPLICA}/postgresql.auto.conf" || true

# ---------------------------------------------------------------------------
# STEP 6 - Write a SEPARATE postgresql.conf for the REPLICA
#          (the base backup copied the primary's postgresql.conf, which would
#           conflict on ports and data_directory - so we point pg_ctl at a
#           brand new config file via -c config_file=...)
# ---------------------------------------------------------------------------
echo
echo "== STEP 6: Write replica postgresql.conf at ${PGCONF_REPLICA} =="


sudo tee "${PGCONF_REPLICA}" >/dev/null <<EOF
# Replica postgresql.conf - Portfolio 5
# Student: Nuhu Simbiat - 2026/A/MIT/0955
# Pointed at by:  pg_ctl -o "-c config_file=${PGCONF_REPLICA}"
# The data_directory below is the actual base-backup target.

data_directory        = '${PGDATA_REPLICA}'
hba_file              = '${PGHBA_REPLICA}'
ident_file            = '${PGDATA_REPLICA}/pg_ident.conf'

port                  = ${REPLICA_PORT}
listen_addresses      = 'localhost'
hot_standby           = on

wal_level             = replica
max_wal_senders       = 10
max_replication_slots = 10

# Cascade-replication readiness for the branch-offline design (see
# 04_cloud_architecture.md): any branch can in turn feed off this replica.
hot_standby_feedback   = on
log_connections        = on
log_min_messages       = warning
EOF

sudo chown postgres:postgres "${PGCONF_REPLICA}"
sudo chmod 640 "${PGCONF_REPLICA}"
echo "   replica config written: ${PGCONF_REPLICA}"

# ---------------------------------------------------------------------------
# STEP 7 - Write the replica's own pg_hba.conf (local trust, port 5433)
# ---------------------------------------------------------------------------
echo
echo "== STEP 7: Write replica pg_hba.conf (local trust on port ${REPLICA_PORT}) =="

sudo tee "${PGHBA_REPLICA}" >/dev/null <<'EOF'
# Replica pg_hba.conf - Portfolio 5
# BEGIN P5 REPLICA LOCAL TRUST
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
local   replication     postgres                                trust
host    replication     postgres        127.0.0.1/32            trust
host    replication     postgres        ::1/128                 trust
# END P5 REPLICA LOCAL TRUST
EOF

sudo chown postgres:postgres "${PGHBA_REPLICA}"
sudo chmod 640 "${PGHBA_REPLICA}"
echo "   replica pg_hba.conf written: ${PGHBA_REPLICA}"

# ---------------------------------------------------------------------------
# STEP 8 - Start the replica with pg_ctl (NOT systemctl - not registered)
# ---------------------------------------------------------------------------
echo
# FIX: Ubuntu keeps pg_ident.conf in /etc, so the base backup has none.
sudo cp /etc/postgresql/${PGVER}/main/pg_ident.conf "${PGDATA_REPLICA}/pg_ident.conf"
sudo chown postgres:postgres "${PGDATA_REPLICA}/pg_ident.conf"
sudo chmod 700 "${PGDATA_REPLICA}"

echo "== STEP 8: Start replica with pg_ctl (config_file override) =="

sudo runuser -u postgres -- "${PGCTL}" \
    -D "${PGDATA_REPLICA}" \
    -o "-c config_file=${PGCONF_REPLICA}" \
    -l "${PGDATA_REPLICA}/replica.log" \
    -w start

# Give the replica a moment to connect to the primary and start replaying.
sleep 5
echo "   replica started on port ${REPLICA_PORT}."
echo "   replica log: ${PGDATA_REPLICA}/replica.log"

# ---------------------------------------------------------------------------
# STEP 9 - Status checks (primary and replica)
# ---------------------------------------------------------------------------
echo
for i in $(seq 1 20); do
    n=$(sudo runuser -u postgres -- psql -X -At -d postgres -c "SELECT count(*) FROM pg_stat_replication WHERE state='streaming'")
    [ "$n" -ge 1 ] && break
    sleep 1
done

echo "== STEP 9a: On PRIMARY - pg_stat_replication (should list the replica) =="
sudo runuser -u postgres -- psql -d "${DB}" -c \
    "SELECT pid, usename, application_name, client_addr, state, sync_state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"

echo
echo "== STEP 9b: On REPLICA - pg_is_in_recovery() (must be true) =="
sudo runuser -u postgres -- psql -p "${REPLICA_PORT}" -d "${DB}" -c \
    "SELECT pg_is_in_recovery() AS in_recovery;"

echo
echo "== STEP 9c: On REPLICA - replication replay lag =="
sudo runuser -u postgres -- psql -p "${REPLICA_PORT}" -d "${DB}" -c \
    "SELECT now() - pg_last_xact_replay_timestamp() AS replay_lag;"

echo
echo "================================================================"
echo " Replica setup complete."
echo " Primary  :  sudo runuser -u postgres -- psql -d ${DB}"
echo " Replica  :  sudo runuser -u postgres -- psql -p ${REPLICA_PORT} -d ${DB}"
echo
echo " Next step: run 03_replica_demo.sql against BOTH targets and paste"
echo "            the real outputs into that file."
echo "================================================================"
