#!/bin/bash
# seed-from-dump.sh — restore a Postgres custom-format dump into a
# container on the sandbox VM. Streams over Tailscale SSH (no temp file
# on either side, no /tmp filling up).
#
# Usage:
#   ./seed-from-dump.sh <local-dump-file> <db-name> [container-name]
#
# Examples:
#   ./seed-from-dump.sh ~/work/deepreel/db-backup/v2_deepreel_staging_latest.pgdump deepreel_staging
#   ./seed-from-dump.sh ./dump.pgdump deepreel_staging dp-pg
#
# Behaviour:
#   - Uses pg_restore --clean --if-exists, so re-runs replace existing
#     objects (idempotent for the data, no manual DROP DATABASE needed)
#   - --no-owner --no-acl strip role/grant statements (avoids restore
#     errors when the dump was taken with different roles)
#   - Single-threaded (parallel pg_restore -j requires a seekable file,
#     which stdin isn't). 100MB+ dumps still finish in ~30-60s.
#   - Reports table count + top tables by row count when done

set -euo pipefail

if [ $# -lt 2 ]; then
  cat >&2 <<USAGE
Usage: $0 <local-dump-file> <db-name> [container-name]
  local-dump-file   Postgres custom-format dump (.pgdump / .dump / .Fc)
  db-name           target DB inside the container (e.g. deepreel_staging)
  container-name    docker container running postgres (default: dp-pg)
USAGE
  exit 1
fi

DUMP="$1"
DB="$2"
CONTAINER="${3:-dp-pg}"

[ -f "$DUMP" ] || { echo "[seed] dump not found: $DUMP" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TF_DIR="$ROOT/hosts/aws-ec2/terraform"
HOSTNAME="$(cd "$TF_DIR" && terraform output -raw tailnet_hostname)"
SIZE_HUMAN="$(ls -lh "$DUMP" | awk '{print $5}')"

echo "[seed] dump:      $DUMP ($SIZE_HUMAN)"
echo "[seed] target:    $HOSTNAME → $CONTAINER → DB '$DB'"
echo "[seed] streaming + pg_restore (single-threaded; --clean --if-exists)..."
echo

cat "$DUMP" | tailscale ssh "agent@$HOSTNAME" "
  docker exec -i '$CONTAINER' pg_restore \
    -U postgres -d '$DB' \
    --no-owner --no-acl --clean --if-exists \
    2>&1 | tail -5
  echo
  echo '--- top 10 tables by row count ---'
  docker exec '$CONTAINER' psql -U postgres -d '$DB' -c '
    SELECT relname, n_live_tup
    FROM pg_stat_user_tables
    ORDER BY n_live_tup DESC
    LIMIT 10;'
"

echo
echo "[seed] done."
