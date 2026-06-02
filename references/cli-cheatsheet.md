# Coolify CLI Command Quick Reference

> This is a command reference for the `coolify` CLI (coollabsio/coolify-cli, the Go version). The CLI is continuously evolving, so **flags should be taken from the actual output of `coolify <cmd> --help`**. This table is a quick reference for commonly used items.

## Table of Contents

- [Context (connection management)](#context-connection-management)
- [Resource overview](#resource-overview)
- [App](#app)
- [Deploy](#deploy)
- [Env](#env)
- [Database](#database)
- [Service](#service)
- [Server](#server)
- [Output formats & global flags](#output-formats--global-flags)
- [Troubleshooting table](#troubleshooting-table)

## Context (connection management)

```bash
coolify context add <name> <url> <token> -d   # add and set as default; -d can be omitted
coolify context list                          # list all
coolify context get <name>                     # details
coolify context use <name>                     # switch default
coolify context set-token <name> <new-token>   # change token
coolify context update <name> --url <new-url>  # change URL
coolify context delete <name>                  # delete
coolify context verify                          # verify current context connectivity + auth
coolify context version                         # check Coolify backend version
```

Temporarily switch between multiple contexts (without changing the default): `coolify --context=<name> <command>`

## Resource overview

```bash
coolify resources list          # see all resources (app+db+service) and their status at once
coolify projects list           # list projects
coolify projects get <uuid>     # environments under a project
coolify server list             # list servers
```

## App

```bash
coolify app list                          # list all apps
coolify app get <uuid>                     # details
coolify app start|stop|restart <uuid>      # lifecycle
coolify app delete <uuid>                  # delete (dangerous, requires confirmation; do not proactively add -f)
coolify app logs <uuid>                     # runtime logs (container stdout)

# Create a new app from a git repo / Dockerfile / image (pick the source subcommand)
coolify app create public      --server-uuid <s> --project-uuid <p> --environment-name <env> \
  --git-repository <url> --git-branch <branch> --build-pack nixpacks --ports-exposes 3000
coolify app create github      --server-uuid <s> --project-uuid <p> --environment-name <env> \
  --github-app-uuid <uuid> --git-repository <user/repo> --git-branch <branch> --ports-exposes 3000
coolify app create deploy-key  ...    # private repo via SSH deploy key
coolify app create dockerfile  ...    # build from a custom Dockerfile
coolify app create dockerimage --server-uuid <s> --project-uuid <p> --environment-name <env> \
  --docker-registry-image-name <image:tag> --ports-exposes 80

# Change config of an EXISTING app (update, not create)
coolify app update <uuid> \
  --git-branch <branch> \
  --git-repository <url> \
  --domains <comma-separated> \
  --build-command <cmd> \
  --start-command <cmd> \
  --install-command <cmd> \
  --base-directory <path> \
  --publish-directory <path> \
  --docker-image <image> --docker-tag <tag> \
  --ports-exposes <ports> \
  --health-check-enabled --health-check-path <path>
```

### Deployment logs (build/startup phase)

```bash
coolify app deployments list <app-uuid>                  # past deployments
coolify app deployments logs <app-uuid>                  # all logs from the most recent deployment
coolify app deployments logs <app-uuid> -f               # follow in real time (tail -f style)
coolify app deployments logs <app-uuid> -n 100           # last 100 lines
coolify app deployments logs <app-uuid> <deployment-uuid> # a specific deployment
```

**Difference between runtime logs vs deployment logs**: `app logs` shows the container's stdout after it is up and running (for troubleshooting runtime crashes); `app deployments logs` shows the build → push → startup process (for troubleshooting deployment failures).

## Deploy

```bash
coolify deploy name <app-name>           # deploy by name (recommended, easy to remember)
coolify deploy uuid <uuid>               # deploy by UUID
coolify deploy batch <a>,<b>,<c>         # batch deploy multiple
coolify deploy name <app-name> -f        # force deploy (deploy even with no changes; use with caution)
coolify deploy list                       # all deployment records
coolify deploy get <deployment-uuid>      # single deployment details
coolify deploy cancel <deployment-uuid>   # cancel an in-progress deployment
```

> **`deploy list --format=json` fields** (verified against coolify-cli v1.6.2 — `internal/models/deployment.go`): `id`, `deployment_uuid`, `application_id`, `application_name`, `server_name`, `status`, `commit`, `commit_message`, `deployment_url`, `finished_at`, `created_at`, `updated_at`. To correlate a deployment to an app, match `application_id` (the app UUID) or `application_name` — there is **no** `application_uuid` or `resource_uuid`.

## Env

> The env subcommands for app and service are identical; the example below uses app.

```bash
coolify app env list <app-uuid>
coolify app env get <app-uuid> <env-uuid-or-key>
coolify app env create <app-uuid> --key KEY --value VAL [--build-time] [--preview] [--is-literal] [--is-multiline]
coolify app env update <app-uuid> <env-uuid> --value NEW
coolify app env delete <app-uuid> <env-uuid>

# Batch sync from .env (most common)
coolify app env sync <app-uuid> --file .env
coolify app env sync <app-uuid> --file .env.production --build-time
```

**sync behavior**: updates existing + creates missing, and **does not delete** variables not present in the file.
**flag meanings**: `--build-time` available at build time; `--preview` available for preview deployments; `--is-literal` no variable interpolation (use when the value contains `$`); `--is-multiline` multi-line values.

## Database

```bash
coolify database list
coolify database get <uuid>
coolify database create <type> \
  --server-uuid <uuid> --project-uuid <uuid> \
  --environment-name <name> \
  --name <db-name> \
  [--instant-deploy] [--is-public --public-port <port>] \
  [--limits-memory 512m] [--limits-cpus 0.5]
# type: postgresql|mysql|mariadb|mongodb|redis|keydb|clickhouse|dragonfly

coolify database start|stop|restart <uuid>
coolify database delete <uuid>   # dangerous, requires confirmation

# backup
coolify database backup list <db-uuid>
coolify database backup create <db-uuid> \
  --frequency "0 2 * * *" --enabled \
  [--save-s3 --s3-storage-uuid <uuid>] \
  [--retention-days-locally 7] [--retention-amount-locally 5]
coolify database backup trigger <db-uuid> <backup-uuid>       # back up immediately
coolify database backup executions <db-uuid> <backup-uuid>    # backup execution records
```

> Backup flags verified against coolify-cli v1.6.2. Local retention uses the **`-locally`** suffix (`--retention-days-locally` / `--retention-amount-locally`) — there is **no** `--retention-*-local`. S3 has the matching `--retention-days-s3` / `--retention-amount-s3`, plus `--retention-max-storage-locally` / `--retention-max-storage-s3`, `--databases-to-backup`, `--disable-local-backup`, `--dump-all`, and `--timeout`.

cron quick notes: `"0 2 * * *"` = every day at 02:00; `"0 */6 * * *"` = every 6 hours.

## Service

```bash
coolify service list
coolify service get <uuid>
coolify service create <type> --server-uuid <s> --project-uuid <p> --environment-name <env> [--name <n>] [--instant-deploy]
coolify service create --list-types      # list all one-click types (wordpress, ghost, n8n, supabase, ...)
coolify service start|stop|restart <uuid>
coolify service delete <uuid>            # dangerous, requires confirmation
coolify service env sync <uuid> --file .env
```

## Server

```bash
coolify server list
coolify server get <uuid>                # details
coolify server get <uuid> --resources    # including the resources on that server and their status
coolify server validate <uuid>           # validate connection
coolify server domains <uuid>            # domains on that server
```

## Output formats & global flags

```bash
--format=table      # default, for humans
--format=json       # for scripts/Agents to parse, used with jq
--format=pretty     # indented JSON, for debugging

--context=<name>    # temporarily specify a context
--host <fqdn>       # temporarily override the URL
--token <token>     # temporarily override the token (CI scenarios)
-s, --show-sensitive # show sensitive info (token/IP)
--debug             # print the full HTTP request/response (troubleshooting lifesaver)
-f, --force         # skip confirmation (only use after the user has explicitly agreed)
```

Common jq recipes:

```bash
# find an app's uuid by name
coolify app list --format=json | jq -r '.[] | select(.name=="my-app") | .uuid'

# list all resources in a non-running state
coolify resources list --format=json | jq -r '.[] | select(.status!="running") | "\(.name): \(.status)"'
```

## Troubleshooting table

| Symptom | Possible cause | Action |
|---|---|---|
| `connection refused` / timeout | Wrong URL; VPS firewall not opened; Coolify not running | First test the web entry point with `curl -I <url>`; check the VPS firewall ports |
| `401 Unauthorized` | Token wrong or deleted | Regenerate the token in the Web UI, update with `coolify context set-token` |
| `403 Forbidden` | Token is missing a required ability (`read`/`deploy`/`write`/`read:sensitive`) | Re-run with `--debug` and read the 403 body — it lists the **missing permissions**. Add that ability to the token in the Web UI; never escalate to a `root` token. See `references/safety-rules.md` |
| `certificate verify failed` | HTTPS certificate not configured properly | **Preferably** configure TLS in Coolify before connecting. ⚠️ Downgrading to `http://` sends the Bearer Token in plaintext over the wire; only for trusted internal networks/temporary troubleshooting, and the token should be rotated afterward |
| Command can't find a resource | UUID expired/misremembered | Run `<resource> list --format=json` again to get the UUID |
| Unsure about a flag | CLI version differences | `coolify <cmd> --help` to see the actual flags for the current version |
| Want to see request details | — | Prepend `--debug` to any command |
