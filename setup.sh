#!/usr/bin/env bash
# =============================================================================
# setup.sh - ReadWell Libraries portfolio environment setup (Ubuntu/Codespaces)
# Student: Nuhu Simbiat - 2026/A/MIT/0955
# Run once at the start of a fresh Codespace:  bash setup.sh
# Safe to run again (every step checks first).
#
# Codespaces rules followed: no systemd (pg_ctlcluster / mongod --fork instead
# of systemctl), sudo is root-only (sudo runuser -u postgres, never
# sudo -u postgres), Unix sockets only (no TCP passwords).
# =============================================================================
set -euo pipefail

echo "==== ReadWell Libraries portfolio setup ===="

# 0. The yarn apt source has an expired key and breaks apt-get update.
sudo rm -f /etc/apt/sources.list.d/yarn.list

. /etc/os-release
CODENAME="${VERSION_CODENAME:-jammy}"
echo "Ubuntu codename: $CODENAME"

# FIX (after first student run): one broken third-party apt source (expired
# key) makes "apt-get update" return an error and set -e aborted setup.
# The Ubuntu sources still update, so carry on with a warning.
apt_update() { sudo apt-get update -y || echo "WARNING: some apt sources failed to update - continuing"; }
apt_update
sudo apt-get install -y gnupg curl ca-certificates lsb-release

# ---------------------------------------------------------------------------
# 1. PostgreSQL 16 (from the PostgreSQL apt repo if Ubuntu does not ship 16)
# ---------------------------------------------------------------------------
echo "==== Installing PostgreSQL 16 ===="
PG_CAND="$(apt-cache policy postgresql-16 2>/dev/null || true)"
if ! echo "$PG_CAND" | grep -q 'Candidate: [0-9]'; then
    echo "postgresql-16 not in this Ubuntu release - adding apt.postgresql.org"
    sudo install -d /usr/share/postgresql-common/pgdg
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | sudo gpg --dearmor --yes -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg] https://apt.postgresql.org/pub/repos/apt ${CODENAME}-pgdg main" \
        | sudo tee /etc/apt/sources.list.d/pgdg.list >/dev/null
    apt_update
fi
sudo apt-get install -y postgresql-16 postgresql-client-16 postgresql-contrib

# FIX: "systemctl enable --now postgresql" aborts here (no systemd in Codespaces)
sudo pg_ctlcluster 16 main start 2>/dev/null || true
pg_lsclusters

# readwell database + a superuser role for the Codespace user (used by
# Portfolio 3's run_race_demos.py over the Unix socket, peer authentication)
if ! sudo runuser -u postgres -- psql -X -tAc "SELECT 1 FROM pg_database WHERE datname='readwell'" | grep -q 1; then
    echo "Creating database 'readwell'..."
    sudo runuser -u postgres -- createdb readwell
fi
ME="$(whoami)"
if ! sudo runuser -u postgres -- psql -X -tAc "SELECT 1 FROM pg_roles WHERE rolname='$ME'" | grep -q 1; then
    echo "Creating PostgreSQL role '$ME'..."
    sudo runuser -u postgres -- createuser -s "$ME"
fi

# Load the master schema (Portfolio 1 owns it; run_p1.sh reloads it)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_FILE="$SCRIPT_DIR/portfolio-1-database-design/01_schema.sql"
if [ -f "$SCHEMA_FILE" ]; then
    echo "Loading master schema ..."
    sudo runuser -u postgres -- psql -X -q -v ON_ERROR_STOP=1 -d readwell -f - < "$SCHEMA_FILE"
fi

# ---------------------------------------------------------------------------
# 2. MongoDB 8.0 (official repo; focal / jammy / noble packages exist)
# ---------------------------------------------------------------------------
echo "==== Installing MongoDB 8 ===="
case "$CODENAME" in
    focal|jammy|noble) MONGO_REPO_CODENAME="$CODENAME" ;;
    *)                 MONGO_REPO_CODENAME="jammy" ;;
esac
if [ ! -f /usr/share/keyrings/mongodb-server-8.0.gpg ]; then
    curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
        sudo gpg --dearmor --yes -o /usr/share/keyrings/mongodb-server-8.0.gpg
fi
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${MONGO_REPO_CODENAME}/mongodb-org/8.0 multiverse" | \
    sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list > /dev/null
apt_update
sudo apt-get install -y mongodb-org

# Start mongod directly (no systemd in Codespaces)
if ! pgrep -x mongod >/dev/null; then
    sudo mkdir -p /data/db
    sudo mongod --dbpath /data/db --fork --logpath /var/log/mongod.log --bind_ip 127.0.0.1
fi
mongosh --quiet --eval 'print("MongoDB " + db.version() + " is up")'

# ---------------------------------------------------------------------------
# 3. Python driver for Portfolio 3's two-session demo
# ---------------------------------------------------------------------------
if ! python3 -c "import psycopg2" 2>/dev/null; then
    python3 -m pip install --user -q psycopg2-binary \
      || python3 -m pip install --user -q --break-system-packages psycopg2-binary \
      || sudo apt-get install -y python3-psycopg2
fi
python3 -c "import psycopg2; print('psycopg2', psycopg2.__version__)"

# ---------------------------------------------------------------------------
# 4. Summary
# ---------------------------------------------------------------------------
echo ""
echo "==== Setup complete ===="
sudo runuser -u postgres -- psql -X -tAc "SELECT version()"
echo "PostgreSQL: sudo runuser -u postgres -- psql -d readwell   (Unix socket)"
echo "MongoDB:    mongosh readwell_catalog"
echo "Next: run portfolios 1-5 in order (run_p1.sh ... run_p5.sh)."
