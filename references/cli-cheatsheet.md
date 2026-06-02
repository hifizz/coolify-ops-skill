# Coolify CLI Command Quick Reference

> This is a command reference for the `coolify` CLI (coollabsio/coolify-cli, the Go version). The CLI is continuously evolving, so **flags should be taken from the actual output of `coolify <cmd> --help`** — or, for a version-exact dump, from `references/_generated/` (run `bash scripts/gen-reference.sh`, which calls `coolify docs markdown` / `coolify docs llms`). **That generated reference is authoritative; this table is only a high-frequency quick reference** for commonly used items, jq recipes, and troubleshooting.

## Table of Contents

- [Context (connection management)](#context-connection-management)
- [Resource overview](#resource-overview)
- [App](#app)
- [Deploy](#deploy)
- [Env](#env)
- [Database](#database)
- [Service](#service)
- [Server](#server)
- [GitHub App integrations](#github-app-integrations)
- [Private keys](#private-keys)
- [Storage (persistent volumes)](#storage-persistent-volumes)
- [Teams](#teams)
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
coolify app logs <uuid> -f                  # follow runtime logs (tail -f style)
coolify app logs <uuid> -n 100              # last N lines (-n/--lines, default 100)
coolify app previews delete <uuid> <pr-id>  # clean up a PR preview deployment

# Create a new app from a git repo / Dockerfile / image (pick the source subcommand)
coolify app create public      --server-uuid <s> --project-uuid <p> --environment-name <env> \
  --git-repository <url> --git-branch <branch> --build-pack nixpacks --ports-exposes 3000
coolify app create github      --server-uuid <s> --project-uuid <p> --environment-name <env> \
  --github-app-uuid <uuid> --git-repository <user/repo> --git-branch <branch> --build-pack nixpacks --ports-exposes 3000
coolify app create deploy-key  ...    # private repo via SSH deploy key
coolify app create dockerfile  ...    # build from a custom Dockerfile
coolify app create dockerimage --server-uuid <s> --project-uuid <p> --environment-name <env> \
  --docker-registry-image-name <image> --docker-registry-image-tag <tag> --ports-exposes 80

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
coolify app deployments logs <app-uuid> -n 100           # last N lines (-n/--lines, 0 = all)
coolify app deployments logs <app-uuid> --debuglogs      # include hidden/internal build commands
coolify app deployments logs <app-uuid> <deployment-uuid> # a specific deployment
```

> Both `app logs` and `app deployments logs` share `-f`/`--follow` and `-n`/`--lines`. Difference: `app logs` defaults to 100 lines; `app deployments logs` defaults to `0` = all, and additionally supports `--debuglogs`.

**Difference between runtime logs vs deployment logs**: `app logs` shows the container's stdout after it is up and running (for troubleshooting runtime crashes); `app deployments logs` shows the build → push → startup process (for troubleshooting deployment failures).

## Deploy

```bash
coolify deploy name <app-name>           # deploy by name (recommended, easy to remember)
coolify deploy uuid <uuid>               # deploy by UUID
coolify deploy batch <a>,<b>,<c>         # batch deploy multiple
coolify deploy name <app-name> --force   # force deploy (deploy even with no changes; --force only, no -f short)
coolify deploy list                       # all deployment records
coolify deploy get <deployment-uuid>      # single deployment details
coolify deploy cancel <deployment-uuid>   # cancel an in-progress deployment
```

> **`deploy list --format=json` fields** (verified against coolify-cli v1.6.2 — `internal/models/deployment.go`): `id`, `deployment_uuid`, `application_id`, `application_name`, `server_name`, `status`, `commit`, `commit_message`, `deployment_url`, `finished_at`, `created_at`, `updated_at`. To correlate a deployment to an app, match `application_id` (the app UUID) or `application_name` — there is **no** `application_uuid` or `resource_uuid`.

## Env

> The env subcommands exist for **app, service, and database**. App and service share the full flag set (incl. `--build-time` / `--runtime` / `--preview`). **Database env is reduced** — a database has no build step, so `database env sync` only takes `-f`/`--file` + `--is-literal`, and `database env create` has no `--build-time`/`--runtime`/`--preview` either (passing them errors with `unknown flag`). The examples below use app.

```bash
coolify app env list <app-uuid>
coolify app env get <app-uuid> <env-uuid-or-key>
coolify app env create <app-uuid> --key KEY --value VAL [--build-time] [--preview] [--is-literal] [--is-multiline]
coolify app env update <app-uuid> <env-uuid> --value NEW
coolify app env delete <app-uuid> <env-uuid>

# Batch sync from .env (most common)
coolify app env sync <app-uuid> --file .env
coolify app env sync <app-uuid> --file .env.public --build-time=true    # frontend / build-time vars
coolify app env sync <app-uuid> --file .env.secret --build-time=false   # runtime-only, keep out of build layer
```

**sync behavior**: updates existing + creates missing, and **does not delete** variables not present in the file.
**sync flags**: `--build-time` (default **true**) available at build time; `--runtime` (default **true**) available at runtime; `--preview` available in preview deployments; `--is-literal` no variable interpolation (use when the value contains `$`); `-f`/`--file` is the **path** (required), not `--force`.

> ⚠️ **`--help` default vs. real behavior**: the help shows `--build-time (default: true)` and `--runtime (default: true)`, but a value is only sent when you **explicitly** pass the flag — a bare `sync` leaves both to the server default. So don't assume "bare sync = everything build-time", and don't assume "omitting `--build-time` keeps secrets out of the build layer". When you need a specific behavior, set it explicitly (`--build-time=false` / `--build-time=true`). And `sync` applies **one flag set to the entire file**, so split sensitive vs. non-sensitive into separate files/passes.

> `env create` carries the same `--build-time` / `--runtime` (both default true), plus `--is-multiline` and `--comment`.

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

# databases also have env (reduced flags — no --build-time/--runtime/--preview) and storage:
coolify database env list <db-uuid>
coolify database env sync <db-uuid> --file .env               # only -f/--file + --is-literal
coolify database storage list <db-uuid>                       # see Storage section
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
coolify server add <name> <ip> <private-key-uuid> [-p 22] [-u root] [--validate]   # register a new server
coolify server remove <uuid>             # remove a server (dangerous, requires confirmation)
```

## GitHub App integrations

For deploying **private** GitHub repos; `app create github` needs the resulting App UUID (`--github-app-uuid`). Aliases: `gh`, `github-app`, `github-apps`.

```bash
coolify github list                                  # list GitHub App integrations
coolify github get <app-uuid>                         # details
coolify github repos <app-uuid>                       # repos the App can access
coolify github branches <app-uuid> <owner/repo>       # branches of a repo
coolify github create --name <n> --api-url https://api.github.com --html-url https://github.com \
  --app-id <id> --installation-id <id> --client-id <id> --client-secret <secret> \
  --private-key-uuid <uuid>                            # register a GitHub App (all listed flags required)
coolify github update <app-uuid> ...                  # update integration
coolify github delete <app-uuid>                      # delete integration (dangerous)
```

## Private keys

SSH private keys for server auth and `app create deploy-key` private-repo deploys. Aliases: `private-keys`, `key`, `keys`.

```bash
coolify private-key list                                   # list keys
coolify private-key add <key-name> <private-key-or-file>   # add a key (inline value or a file path)
coolify private-key remove <uuid>                          # remove a key (dangerous)
```

## Storage (persistent volumes)

Persistent volumes / file mounts for stateful resources — same shape for `app` / `database` / `service` (alias: `storages`).

```bash
coolify app storage list <app-uuid>
coolify app storage create <app-uuid> --type persistent --name <vol> --mount-path /data
coolify app storage create <app-uuid> --type file --mount-path /etc/app/config.yml --content "$(cat config.yml)"
coolify app storage update <app-uuid> --uuid <storage-uuid> --type persistent --mount-path /data   # update: storage id is --uuid, NOT a 2nd positional
coolify app storage delete <app-uuid> <storage-uuid>       # delete: storage id IS a 2nd positional (dangerous: may delete persisted data)

# database / service are identical — just swap the noun:
coolify database storage list <db-uuid>
coolify service storage list <service-uuid>
```

## Teams

Tokens are **team-scoped** (see `references/safety-rules.md`); these show which team you're acting as. Alias: `team`.

```bash
coolify teams list             # all teams visible to the token
coolify teams current          # the currently authenticated team
coolify teams get <id>         # team details
coolify teams members list     # members of the current team
```

## Output formats & global flags

```bash
--format=table      # default, for humans
--format=json       # for scripts/Agents to parse, used with jq
--format=pretty     # indented JSON, for debugging

--context=<name>    # temporarily target a different context (the only ad-hoc way to switch instance)
--token <token>     # temporarily override the token (CI scenarios)
-s, --show-sensitive # show sensitive info (token/IP)
--debug             # print the full HTTP request/response (troubleshooting lifesaver)
```

> **`-f` is overloaded and per-command — there is no global `--force`/`-f` in v1.6.2:**
> - `coolify app delete <uuid> -f` / `--force` → **skips the delete confirmation prompt** (never add on your own initiative).
> - `coolify deploy name|uuid <x> --force` → **force a redeploy** (note: `--force` only, **no `-f` short form** here).
> - `coolify {app,service,database} env sync <x> -f <file>` → here `-f` is `--file`, the `.env` **path** (required) — completely safe, use it freely.
> - `coolify database delete` has **no** force flag (instead: `--delete-volumes` / `--delete-configurations` / … , all default `true` — see `references/safety-rules.md`).

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
