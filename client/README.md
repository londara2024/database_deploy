# Connect to the database from another PC (Docker)

Runs `cloudflared` in Docker, so DBeaver can connect through `db.comshop.me.uk`
without installing cloudflared or keeping a window open.

## Requirements
- Docker Desktop (Windows/macOS) or Docker Engine (Linux) on the PC.
- Cloudflare route `db.comshop.me.uk` with Service **`tcp://SERVER_IP:PORT`**
  (port = `POSTGRES_PORT` on the server). It must be `tcp://`, not `http://`.

## Start
Copy this `client` folder to the other PC, then:
```bash
cd client
cp .env.example .env     # optional
docker compose up -d
docker compose logs -f   # should show: Start Websocket listener host=0.0.0.0:15432
```
It starts again automatically after a reboot (`restart: unless-stopped`).

Check the port (PowerShell):
```powershell
Test-NetConnection localhost -Port 15432
```

## DBeaver
| Field | Value |
|---|---|
| Host | `localhost` |
| Port | `15432` |
| Database | `appdb` |
| Username | `appuser` |
| Password | `POSTGRES_PASSWORD` from the server `.env` |

## Cloudflare Access (if enabled)
A container cannot open the browser login, so use a **service token**:
1. Zero Trust → Access → Service Auth → Service Tokens → **Create** → copy Client ID / Secret.
2. In the Access application for `db.comshop.me.uk`, add a policy: Action **Service Auth**, Include **Service Token** = that token.
3. Put the ID/secret in `client/.env`, then `docker compose up -d`.

## Problems
| Symptom | Fix |
|---|---|
| Port 15432 already in use | Set `LOCAL_PORT=25432` in `.env`, use 25432 in DBeaver |
| DBeaver: connection refused | `docker compose ps` — container must be running |
| Logs: `websocket: bad handshake` | Route Service must be `tcp://...`; check Access/service token |
| `password authentication failed` | See [../TROUBLESHOOTING.md](../TROUBLESHOOTING.md) |

Stop: `docker compose down`
