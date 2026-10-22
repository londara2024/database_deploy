# Host a Next.js app with Cloudflare Tunnel (same server as PostgreSQL)

```
Browser → https://coffee.comshop.me.uk → Cloudflare Tunnel → localhost:3000 (Next.js)
                                                              → postgres16:5432 (Docker network "dbnet")
```
- Website = `http://` route → works in any browser, nothing to install.
- Next.js talks to Postgres **inside Docker**, so the DB does not need a public route.

## 1. Database: make sure the shared network exists
`docker-compose.yml` of this project sets `networks.default.name: dbnet`. Apply it once:
```bash
cd /opt/database_hosting
docker compose up -d
docker network ls | grep dbnet
```

## 2. Next.js project files

### `next.config.js` (or `.mjs` / `.ts`) — enable standalone build
```js
module.exports = {
  output: "standalone",
};
```

### `Dockerfile`
```dockerfile
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci

FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
# If you use Prisma, add: RUN npx prisma generate
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME=0.0.0.0
RUN addgroup -S nodejs && adduser -S nextjs -G nodejs
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
USER nextjs
EXPOSE 3000
CMD ["node", "server.js"]
```

### `.dockerignore`
```
node_modules
.next
.git
.env*
```

### `docker-compose.yml` (in the Next.js project)
```yaml
services:
  web:
    build: .
    container_name: nextjs-web
    restart: unless-stopped
    env_file: .env
    ports:
      - "127.0.0.1:3000:3000"   # only cloudflared on this server reaches it
    networks:
      - dbnet

networks:
  dbnet:
    external: true
```

### `.env` (in the Next.js project, on the server)
```
DATABASE_URL=postgresql://appuser:YOUR_PASSWORD@postgres16:5432/appdb
```
- Host = `postgres16` (container name), port = **5432** (internal port, not `POSTGRES_PORT`).
- `NEXT_PUBLIC_*` variables are baked in at **build** time; pass them as build args if needed.

## 3. Run on the server
```bash
cd /opt/my-next-app
docker compose up -d --build
curl -I http://localhost:3000      # should return HTTP 200
```

## 4. Cloudflare Tunnel route
Zero Trust → Networks → Tunnels → your tunnel → Published application routes → Add

| Field | Value |
|---|---|
| Subdomain | `coffee` |
| Domain | `comshop.me.uk` |
| Path | *(empty)* |
| Service URL | `http://localhost:3000` (cloudflared on host) |

If `cloudflared` runs in Docker: use `http://nextjs-web:3000` and connect cloudflared to `dbnet`
(`docker network connect dbnet <cloudflared-container>`), or use `http://SERVER_IP:3000`
with the port bound to `0.0.0.0`.

Open `https://coffee.comshop.me.uk` — HTTPS certificate is handled by Cloudflare.

## 5. Update the app
```bash
git pull
docker compose up -d --build
docker image prune -f
```

## Problems
| Symptom | Fix |
|---|---|
| Cloudflare `502 Bad Gateway` | App not running: `docker compose ps`, `docker compose logs web`; check Service URL/port |
| `getaddrinfo ENOTFOUND postgres16` | Web container not on `dbnet`; run step 1, then `docker compose up -d` |
| `password authentication failed` | See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| `ECONNREFUSED 127.0.0.1:5432` | `DATABASE_URL` uses `localhost`; inside Docker use `postgres16` |
| Build fails: `.next/standalone` not found | Add `output: "standalone"` to `next.config` |
