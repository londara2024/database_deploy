# PostgreSQL 16 (Alpine) on Ubuntu with Docker

> Having problems? See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
> Remote access via Cloudflare Tunnel: see [CLOUDFLARE_TUNNEL.md](CLOUDFLARE_TUNNEL.md).
> Host a Next.js app with the database: see [NEXTJS_HOSTING.md](NEXTJS_HOSTING.md).
> Connect from another PC with Docker via Cloudflare: see [DOCKER_DB_VIA_CLOUDFLARE.md](DOCKER_DB_VIA_CLOUDFLARE.md).

## 1. Copy the project to the server
```bash
scp -r database_hosting user@SERVER_IP:/opt/
ssh user@SERVER_IP
cd /opt/database_hosting
chmod +x scripts/*.sh
```

## 2. Install Docker (skip if already installed)
```bash
./scripts/install-docker-ubuntu.sh
newgrp docker
```

## 3. Configure
```bash
cp .env.example .env
nano .env        # set a strong POSTGRES_PASSWORD
chmod 600 .env
```

## 4. Start
```bash
docker compose up -d
docker compose ps          # STATUS should become "healthy"
docker compose logs -f postgres
```

## 5. Connect
From the server:
```bash
docker compose exec postgres psql -U appuser -d appdb
```

From your PC (secure, recommended — keep `POSTGRES_BIND=127.0.0.1`):
```bash
ssh -L 5432:127.0.0.1:337 user@SERVER_IP
# then connect to localhost:5432 with DBeaver / pgAdmin / your app
```

Connection string:
```
postgresql://appuser:PASSWORD@localhost:5432/appdb
```

### Public access (only if needed)
Set `POSTGRES_BIND=0.0.0.0` in `.env`, then `docker compose up -d`.

> **Warning:** Docker publishes ports by editing iptables directly, so **ufw rules do not block them**.
> Allow only trusted IPs at your cloud provider's firewall / security group,
> or keep the default `127.0.0.1` and use an SSH tunnel.

## Backups
```bash
./scripts/backup.sh                                 # creates backups/<db>_<time>.dump
./scripts/restore.sh backups/appdb_20261021_020000.dump
```
Daily backup via cron (`crontab -e`):
```
0 2 * * * cd /opt/database_hosting && ./scripts/backup.sh >> backups/backup.log 2>&1
```

## Useful commands
| Action | Command |
|---|---|
| Stop | `docker compose stop` |
| Restart | `docker compose restart` |
| Update image (16.x patch) | `docker compose pull && docker compose up -d` |
| Remove container (keeps data) | `docker compose down` |
| **Delete all data** | `docker compose down -v` |

Notes:
- Files in `init/` run only on the **first** start (empty volume).
- Data lives in the Docker volume `postgres16_data` and survives restarts/reboots.
