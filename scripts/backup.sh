#!/usr/bin/env bash
# Dump the database to ./backups and keep the last N days.
# Cron example (daily 02:00):
#   0 2 * * * cd /opt/database_hosting && ./scripts/backup.sh >> backups/backup.log 2>&1
set -euo pipefail

cd "$(dirname "$0")/.."
set -a; source .env; set +a

KEEP_DAYS="${KEEP_DAYS:-7}"
STAMP="$(date +%Y%m%d_%H%M%S)"
FILE="/backups/${POSTGRES_DB}_${STAMP}.dump"

docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc -f "$FILE"
find ./backups -name "*.dump" -mtime +"$KEEP_DAYS" -delete

echo "[$(date)] Backup created: backups/$(basename "$FILE")"
