# Connect to the Database with Docker via Cloudflare

This guide shows how a PC on **any network** connects to our PostgreSQL database
using **Docker** and **Cloudflare Tunnel**, with DBeaver (or any Postgres client).

## How it works

```
Your PC                                   Cloudflare               Database server
┌──────────────────────────────┐                                  ┌──────────────────────┐
│ DBeaver → localhost:15432    │                                  │ cloudflared (tunnel) │
│              ↓               │   db.comshop.me.uk (TCP)         │          ↓           │
│ Docker: db-tunnel container  │ ───────────────────────────────▶ │ Postgres (Docker)    │
│ (cloudflared access tcp)     │   + service token (Access)       │                      │
└──────────────────────────────┘                                  └──────────────────────┘
```

- The database is **not** open to the internet. Only Cloudflare can reach it.
- The `db-tunnel` container on your PC opens `localhost:15432` and sends the traffic through Cloudflare.
- Cloudflare Access checks a **service token** so only our PCs can connect.

> **Important:** `db.comshop.me.uk` is **not** a website. It does not open in a browser, and you
> cannot type it into DBeaver. In DBeaver you always use **`localhost:15432`**.

---

## Part A: Admin setup (one time, in Cloudflare)

Skip this part if the admin already did it and gave you the Client ID and Client Secret.

### A1. Tunnel route for the database
Zero Trust → **Networks → Tunnels** → your tunnel → **Published application routes** → Add

| Field | Value |
|---|---|
| Subdomain | `db` |
| Domain | `comshop.me.uk` |
| Path | *(leave empty)* |
| Service URL | `tcp://SERVER_IP:POSTGRES_PORT` (e.g. `tcp://192.168.18.8:5432`) |

The Service URL must start with `tcp://`, not `http://`. The port must be the port Postgres
listens on, on the server (`sudo ss -ltnp | grep postgres` on the server shows it).

### A2. Create a service token
Zero Trust → **Access controls → Service credentials** → **Service Tokens** tab

1. Click **Create Service Token**.
2. Name: `db-client`. Duration: **Non-expiring** (or choose a length).
3. Click **Generate token** and copy both values **right away**:
   - **Client ID** → `CF_ACCESS_CLIENT_ID` (ends with `.access`)
   - **Client Secret** → `CF_ACCESS_CLIENT_SECRET`

> The secret is shown **only once**. If you lose it, create a new token
> and update the policy (A3) to use the new token.

### A3. Create a policy
Zero Trust → **Access controls → Policies**

1. Click **Add a policy**. Name: `db-service-token`.
2. **Action:** `Service Auth`.
3. **Add rules → Include:** Selector `Service Token`, Value `db-client`.
4. Click **Save**.

### A4. Protect the hostname
Zero Trust → **Access controls → Applications**

1. Click **Add an application → Self-hosted**.
2. Name: `database`. Public hostname: subdomain `db`, domain `comshop.me.uk`.
3. **Policies:** Select existing policy → `db-service-token`.
4. Save.

From now on, only clients with the token can connect. Do Part B right after this step.

---

## Part B: Connect from your PC (each user)

### B1. Requirements
- **Docker Desktop** (Windows/macOS) or **Docker Engine** (Linux), running.
- The `client` folder from this repository.
- The **Client ID** and **Client Secret** from the admin.
- The database **username and password** from the admin.

### B2. Create `client/.env`
In the `client` folder, copy `.env.example` to `.env` and fill it in:

```
DB_HOSTNAME=db.comshop.me.uk
LOCAL_PORT=15432
CF_ACCESS_CLIENT_ID=xxxxxxxxxxxxxxxx.access
CF_ACCESS_CLIENT_SECRET=yyyyyyyyyyyyyyyyyyyyyyyy
```

> Put the token **only** in `client/.env`. Never put it in `docker-compose.yml` or
> `.env.example`. Those files are committed to git; `.env` is ignored.

### B3. Start the tunnel container
```bash
cd client
docker compose up -d
docker compose logs -f
```
Look for a line like:
```
Start Websocket listener host=0.0.0.0:15432
```
Press `Ctrl+C` to stop watching the logs. The container keeps running, and it starts
again by itself after a reboot.

Check the port (PowerShell):
```powershell
Test-NetConnection localhost -Port 15432
```
`TcpTestSucceeded : True` means the tunnel is ready.

### B4. Connect in DBeaver
**Database → New Database Connection → PostgreSQL → Next**, **Main** tab:

| Field | Value |
|---|---|
| Connect by | Host |
| Host | `localhost` |
| Port | `15432` |
| Database | `appdb` |
| Authentication | Database Native |
| Username | `appuser` (or your own user) |
| Password | from the admin |

Click **Test Connection** (download the driver if asked), then **Finish**.

Connection string for apps on the same PC:
```
postgresql://appuser:PASSWORD@localhost:15432/appdb
```

---

## Part C: Connect without Docker (cloudflared installed on the PC)

Same idea as Part B, but `cloudflared` runs directly on the PC instead of in a container.

### C1. Install cloudflared
| OS | Command |
|---|---|
| Windows | `winget install --id Cloudflare.cloudflared` (then close and reopen PowerShell) |
| macOS | `brew install cloudflared` |
| Ubuntu/Debian | `curl -L -o cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb && sudo dpkg -i cloudflared.deb` |

Check: `cloudflared --version`

### C2. Start the tunnel
**Windows (PowerShell):**
```powershell
cloudflared access tcp --hostname db.comshop.me.uk --url localhost:15432 `
  --service-token-id "xxxxxxxx.access" `
  --service-token-secret "yyyyyyyy"
```

**macOS / Linux:**
```bash
cloudflared access tcp --hostname db.comshop.me.uk --url localhost:15432 \
  --service-token-id "xxxxxxxx.access" \
  --service-token-secret "yyyyyyyy"
```

- Keep this window **open** while you use the database. Closing it disconnects.
- No Access application on `db.comshop.me.uk`? Leave out the two `--service-token-*` options.

### C3. Connect in DBeaver
Same as **B4**: Host `localhost`, Port `15432`, Database `appdb`.

### C4 (optional, Windows): start with one double-click
Create `db-tunnel.bat` somewhere private (not in the git repo, it holds the secret):
```bat
@echo off
title DB tunnel - keep open
cloudflared access tcp --hostname db.comshop.me.uk --url localhost:15432 ^
  --service-token-id "xxxxxxxx.access" ^
  --service-token-secret "yyyyyyyy"
pause
```
Double-click it before opening DBeaver. To start it automatically at login, press
`Win+R`, type `shell:startup`, and put a shortcut to the `.bat` file there.

### Docker vs no Docker
| | Docker (Part B) | No Docker (Part C) |
|---|---|---|
| Install | Docker Desktop | cloudflared only (small) |
| Runs in background | Yes, auto-starts after reboot | Window must stay open (or startup shortcut) |
| Token stored in | `client/.env` | command / `.bat` file |
| DBeaver settings | `localhost:15432` | `localhost:15432` |

---

## Everyday commands (in the `client` folder)

| Action | Command |
|---|---|
| Start | `docker compose up -d` |
| Status | `docker compose ps` |
| Logs | `docker compose logs -f` |
| Restart (after changing `.env`) | `docker compose up -d` |
| Stop | `docker compose down` |

---

## Troubleshooting

| Problem | Cause / Fix |
|---|---|
| DBeaver: `Connection refused` | Container not running → `docker compose ps`, then `docker compose up -d`. |
| Logs: `websocket: bad handshake` | Token wrong or missing → check `client/.env`; check policy A3 uses this token. Also check the route is `tcp://`. |
| Logs: `403 Forbidden` | Token not allowed by the Access application → check A3/A4. |
| `password authentication failed` | Wrong DB username/password, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md). |
| `Port 15432 is already allocated` | Set `LOCAL_PORT=25432` in `.env`, `docker compose up -d`, use port 25432 in DBeaver. |
| Compose error `invalid interpolation format` | A value was typed into `docker-compose.yml` like `${CF_ACCESS_CLIENT_ID:abc}`. Keep it as `${CF_ACCESS_CLIENT_ID:-}` and put the value in `.env`. |
| Opening `https://db.comshop.me.uk` in a browser fails | Expected. It is a TCP route, not a website. |
| Lost the Client Secret | Create a new token (A2), update policy (A3), update `client/.env`. |

## Security rules
- Keep the Client Secret private, like a password. Anyone with both values can reach the database login.
- If a secret is leaked (chat, screenshot, git push), **delete that token** in Service credentials
  and create a new one.
- Give each person their own database user when possible, instead of sharing `appuser`.
