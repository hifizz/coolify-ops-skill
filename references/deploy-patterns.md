# Coolify Deployment Patterns Reference

Typical Coolify configurations by project type. Coolify uses Nixpacks to auto-detect most projects, so much of the time you don't need to set build commands manually; below we note which ones require a manual override.

## Table of Contents

- [Build pack: Nixpacks vs Dockerfile](#build-pack-nixpacks-vs-dockerfile)
- [Node.js / API services](#nodejs--api-services)
- [Next.js](#nextjs)
- [Docker / Docker Compose](#docker--docker-compose)
- [Static sites](#static-sites)
- [Environment variable layering conventions](#environment-variable-layering-conventions)
- [Coolify Magic Variables](#coolify-magic-variables)
- [Deployment failure checklist](#deployment-failure-checklist)

## Build pack: Nixpacks vs Dockerfile

Coolify supports several build packs:

- **Nixpacks** (default): auto-detects language and framework, the most worry-free zero-config option. Node/Next/Python/Go are mostly recognized directly.
- **Dockerfile**: used when the project has a Dockerfile; gives the most control.
- **Docker Compose**: multi-container orchestration.
- **Static**: pure static artifacts.

Selection priority: **use Nixpacks whenever you can**; switch to Dockerfile when you need precise control over the runtime/system dependencies.

## Node.js / API services

Nixpacks usually auto-detects. When you need a manual override:

```bash
coolify app update <uuid> \
  --install-command "pnpm install --frozen-lockfile" \
  --build-command "pnpm build" \
  --start-command "node dist/index.js" \
  --ports-exposes 3000 \
  --health-check-enabled --health-check-path /health
```

Key points:
- **Package manager**: Coolify auto-selects npm/yarn/pnpm based on the lockfile. For pnpm projects, make sure `pnpm-lock.yaml` is committed.
- **Port**: `--ports-exposes` must match the port your app actually listens on (the app must listen on `0.0.0.0` rather than `127.0.0.1`, otherwise it can't be reached from outside the container).
- **Health check**: recommended for long-running services; provide a lightweight `/health` route that returns 200.

## Next.js

Next.js can run on Coolify two ways:

**A. Standalone (recommended, smaller image)**
Set `output: 'standalone'` in `next.config.js`, then:
```bash
coolify app update <uuid> \
  --build-command "pnpm build" \
  --start-command "node .next/standalone/server.js" \
  --ports-exposes 3000
```

**B. Default next start**
```bash
coolify app update <uuid> \
  --build-command "pnpm build" \
  --start-command "pnpm start" \
  --ports-exposes 3000
```

Key points:
- `NEXT_PUBLIC_*` variables are **injected at build time** and must be synced with `--build-time`, otherwise the frontend won't get them:
  ```bash
  coolify app env sync <uuid> --file .env.production --build-time
  ```
- Server-side runtime variables (database connection strings, API keys) can be synced normally and don't need `--build-time`.
- Note the distinction: if a single `.env` contains both `NEXT_PUBLIC_*` and server-side secrets, you may need to sync in two passes (one with `--build-time` for just the frontend variables, one without for the backend), or you can make everything build-time, but then the secrets end up in the build layer — weigh the security tradeoff.

## Docker / Docker Compose

Project has a Dockerfile:
```bash
coolify app update <uuid> \
  --dockerfile "$(cat Dockerfile)" \
  --ports-exposes 8080
```
More commonly, you let Coolify read the Dockerfile in the repo directly (select the Dockerfile build pack in the Web UI, and on the CLI side make sure `--ports-exposes` is correct).

Use a prebuilt image directly:
```bash
coolify app update <uuid> \
  --docker-image ghcr.io/me/my-service \
  --docker-tag latest \
  --ports-exposes 8080
```

## Static sites

The build artifact directory is the key:
```bash
coolify app update <uuid> \
  --build-command "pnpm build" \
  --publish-directory dist        # Vite→dist; Next export→out; CRA→build
```

## Environment variable layering conventions

Recommended local → Coolify mapping:

| Local file | Purpose | Sync command |
|---|---|---|
| `.env.local` | Local development, **not committed, not synced** | don't sync |
| `.env.production` | Production config (the part without secrets) | `coolify app env sync <uuid> --file .env.production` |
| Secrets | Database strings/API keys, etc. | separate `env create`, or put them in a gitignored `.env.secrets` and sync separately |

Red lines:
- **Secrets never go into Git**. If `.env.production` contains secrets, add it to `.gitignore`; only commit non-sensitive config.
- sync does not delete variables, so repeated syncs are safe; but to clean up obsolete variables you have to delete them manually.
- After changing env, you **must redeploy** for it to take effect: `coolify deploy name <app>` (runtime variables only need a restart; build-time variables must be rebuilt).

## Coolify Magic Variables

When deploying a group of related resources (e.g. an app + its database), Coolify provides a set of automatically injected "magic variables" so you don't have to fill in connection info by hand. Common prefixes:

- `SERVICE_URL_<NAME>` — the accessible URL of a service
- `SERVICE_FQDN_<NAME>` — the fully qualified domain name of a service
- `SERVICE_PASSWORD_<NAME>` — an auto-generated password
- `SERVICE_USER_<NAME>` — an auto-generated username
- `SERVICE_BASE64_<NAME>` — generates a random base64 value

Usage: reference them directly in env values, e.g. use `${SERVICE_PASSWORD_POSTGRES}` for the database password, which Coolify substitutes at deploy time. This avoids hardcoding the generated password into the config. The specific variable names available depend on which services you've deployed within the same project/environment; when unsure, you can see the candidates in the Environment Variables panel in the Web UI.

## Deployment failure checklist

Check in this order:

1. `coolify app deployments logs <uuid>` — read the deployment logs to pinpoint which phase failed
2. **install phase failed** → lockfile not committed, or the package manager was detected wrong (check `--install-command`)
3. **build phase failed** → build command wrong, or missing build-time environment variables (`NEXT_PUBLIC_*` not given `--build-time`)
4. **exits immediately after startup** → `--start-command` wrong, or the port isn't listening on `0.0.0.0`, or missing runtime environment variables
5. **build succeeds but access returns 502** → `--ports-exposes` doesn't match the app's actual port; or the health check path returns non-200
6. **health check stays unhealthy** → the route pointed to by `--health-check-path` doesn't exist or returns an error code

After fixing each item, redeploy with `coolify deploy name <app>` and track it with `deploy-and-watch.sh`.
