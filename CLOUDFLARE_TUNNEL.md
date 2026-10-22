# Access PostgreSQL through Cloudflare Tunnel

No open port on the router needed. Works with either `POSTGRES_BIND` value in `.env`:

| `POSTGRES_BIND` | Service URL | LAN access without tunnel |
|---|---|---|
| `0.0.0.0` (current setup) | `tcp://SERVER_IP:337`, e.g. `tcp://192.168.18.8:337` | Yes: `192.168.18.8:337` |
| `127.0.0.1` (most private) | `tcp://localhost:337` (cloudflared on host only) | No |

> With `0.0.0.0`: fine for a LAN server (`192.168.x.x`) **as long as the router does not
> port-forward 337**. On a server with a public IP (cloud VPS) it exposes Postgres to the
> internet and `ufw` does not block Docker ports, so use `127.0.0.1` there.

## 1. Server: add a published application to the tunnel
Cloudflare Zero Trust → Networks → Tunnels → your tunnel → **Published application routes** → Add

| Field | Value |
|---|---|
| Subdomain | `db` |
| Domain | `comshop.me.uk` |
| Path | *(empty)* |
| Service URL | `tcp://192.168.18.8:337` (bind `0.0.0.0`) or `tcp://localhost:337` (bind `127.0.0.1`) |

- Bind `0.0.0.0` + server IP → works whether `cloudflared` runs on the host or in Docker.
- Bind `127.0.0.1` + `cloudflared` in Docker → `localhost` is its own container. Use `tcp://postgres16:5432` and put
  both containers on the same Docker network:
  ```bash
  docker network create dbnet
  docker network connect dbnet postgres16
  docker network connect dbnet <cloudflared-container>
  ```

**Recommended:** in **Access**, attach a Cloudflare Access policy (e.g. allow only your email),
so only you can open the tunnel.

## 2. Client (Windows): open a local port through the tunnel
A raw TCP hostname cannot be used directly from DBeaver; the client must run `cloudflared`.

```powershell
winget install --id Cloudflare.cloudflared
cloudflared access tcp --hostname db.comshop.me.uk --url localhost:15432
```
Keep this window open (a browser login appears if Access is enabled).

Check it:
```powershell
Test-NetConnection localhost -Port 15432
```

## 3. Connect (DBeaver / pgAdmin / app)
**On the same LAN (bind `0.0.0.0`):** skip the tunnel → Host `192.168.18.8`, Port `337`.

**From outside (through the tunnel):**
| Setting | Value |
|---|---|
| Host | `localhost` |
| Port | `15432` |
| Database | `appdb` |
| Username | `appuser` |
| Password | from `.env` |

```
postgresql://appuser:PASSWORD@localhost:15432/appdb
```

## Option: open in a browser with no install (pgAdmin)
`https://db.comshop.me.uk` does **not** work in a browser or DBeaver while the route is `tcp://`.
To use a browser instead (no `cloudflared` on the client):

1. Server: add `PGADMIN_EMAIL`, `PGADMIN_PASSWORD` to `.env`, then `docker compose up -d`.
2. Cloudflare route (edit `db` or add a new subdomain like `pgadmin`):
   Service URL `http://localhost:5050` (cloudflared on host) or `http://SERVER_IP:5050`
   (needs `PGADMIN_PORT` bound to `0.0.0.0`, change in compose).
3. Open `https://db.comshop.me.uk` → log in with the pgAdmin email/password.
4. Add server in pgAdmin: Host `postgres`, Port `5432` (internal), DB `appdb`, user `appuser`.
5. Protect it with a Cloudflare Access policy (allow only your emails).

> One hostname = one service. If `db` becomes pgAdmin (http), use another subdomain
> (e.g. `pg`) for the `tcp://` route used by DBeaver + `cloudflared`.

## Troubleshooting
- `password authentication failed` → see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
- `Connection refused` on 15432 → the `cloudflared access tcp` command is not running.
- Connects then drops / `websocket: bad handshake` → check the tunnel's Service URL is `tcp://...`
  (not `http://`) and the tunnel is **Healthy** in the dashboard.
- On the server, confirm Postgres listens: `sudo ss -ltnp | grep 337` → `0.0.0.0:337` or `127.0.0.1:337`
  (must match the Service URL you chose).
