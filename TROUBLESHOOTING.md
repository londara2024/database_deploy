# Troubleshooting

## `FATAL: password authentication failed for user "appuser"`

### Cause
`POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` are applied **only on the first start**, when the
data volume is empty. If the container was started once (e.g. with the default
`change_me_to_a_strong_password`) and `.env` was edited afterwards, the user still has the **old** password.
Restarting does not change it.

### 1. Check (on the server)
```bash
cd /opt/database_hosting
docker compose exec postgres env | grep POSTGRES_
docker compose exec postgres psql -U appuser -d appdb -c "select 1"
```
Inside the container, `psql` uses local trust auth, so it works even when the password is wrong.

### 2. Fix — choose one

**A. Keep data: set the password to the one in `.env`**
```bash
docker compose exec postgres psql -U appuser -d appdb \
  -c "ALTER USER appuser WITH PASSWORD 'your_password_from_env';"
```

**B. Reset everything (DELETES ALL DATA)** — only if the DB is empty/unimportant
```bash
docker compose down -v
docker compose up -d
```

> **Many compose projects on the same server?** `down -v` only affects the project in the
> current folder (project name = folder name) and only the volumes declared in *this*
> `docker-compose.yml` (`postgres16_data`). Other projects are not touched, as long as:
> - you run it inside `/opt/database_hosting` (or use `-f /opt/database_hosting/docker-compose.yml`);
> - no other project uses the same folder name or the same volume name `postgres16_data`.
>
> Check first:
> ```bash
> docker compose ls                 # all compose projects on the server
> docker compose config --volumes   # volumes THIS project will delete
> ```

### 3. Also check the client (DBeaver / pgAdmin / app)
- **Host/port**
  - `POSTGRES_BIND=127.0.0.1` (default) → use an SSH tunnel
    (DBeaver **SSH** tab, or `ssh -L 5432:127.0.0.1:337 user@SERVER_IP`), Host = `localhost`.
  - `POSTGRES_BIND=0.0.0.0` → Host = server IP.
  - If PostgreSQL is also installed on your PC, local port 5432 is taken and you may be hitting
    **your local Postgres** instead. Tunnel to another port: `ssh -L 15432:127.0.0.1:337 user@SERVER_IP`
    and connect to `localhost:15432`.
- **Database** = `appdb` (your `POSTGRES_DB`).
- **Special characters**: `$`, `#`, quotes in the password can be mangled by Docker Compose when reading `.env`
  (`$` is treated as a variable). Use letters + digits only, or wrap the value in single quotes:
  `POSTGRES_PASSWORD='p@ss$word'`. Then apply it with fix **A**.

---

## Container keeps restarting / not `healthy`
```bash
docker compose ps
docker compose logs --tail=100 postgres
```
Common causes: `.env` missing (`cp .env.example .env`), `POSTGRES_PASSWORD` empty,
or port 337 already used on the server (`sudo ss -ltnp | grep 337`) → change `POSTGRES_PORT`.

## `Connection refused` / timeout from PC

### Test the port from Windows (PowerShell)
```powershell
Test-NetConnection SERVER_IP -Port 337
# example: Test-NetConnection 192.168.18.8 -Port 337
```
- `TcpTestSucceeded : True` → port is reachable; if login still fails, it's a password/user/database problem
  (see the password section above).
- `TcpTestSucceeded : False` → network problem: wrong IP, container not running, `POSTGRES_BIND=127.0.0.1`,
  or a firewall blocking 337.

Using an SSH tunnel? Test the local end instead: `Test-NetConnection localhost -Port 5432`.

From Linux / the server itself:
```bash
nc -zv SERVER_IP 337
sudo ss -ltnp | grep 337     # on the server: shows 0.0.0.0:337 or 127.0.0.1:337
```

### Common causes
- Default bind is `127.0.0.1` → you must use an SSH tunnel (see above).
- With `0.0.0.0`, open port 337 in the cloud provider's firewall / security group for your IP.
  Note: Docker bypasses `ufw`, so ufw rules do not affect published ports.

## `init/*.sql` did not run
Init scripts only run on the first start with an empty volume. Either run the SQL manually:
```bash
docker compose exec -T postgres psql -U appuser -d appdb < init/01-init.sql
```
or reset with `docker compose down -v && docker compose up -d` (**deletes data**).

## Scripts fail with `/usr/bin/env: 'bash\r'`
The file has Windows (CRLF) line endings. Fix on the server:
```bash
sed -i 's/\r$//' scripts/*.sh
```
