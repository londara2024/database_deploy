#!/usr/bin/env bash
# Restore a dump from ./backups. Usage: ./scripts/restore.sh backups/appdb_20261021_020000.dump
set -euo pipefail

cd "$(dirname "$0")/.."
set -a; source .env; set +a

if [ $# -ne 1 ] || [ ! -f "$1" ]; then
  echo "Usage: $0 backups/<file>.dump" >&2
  exit 1
fi

read -r -p "This will overwrite objects in '$POSTGRES_DB'. Continue? [y/N] " ans
[ "$ans" = "y" ] || exit 1

docker compose exec -T postgres pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  --clean --if-exists --no-owner "/backups/$(basename "$1")"

echo "Restore finished."
