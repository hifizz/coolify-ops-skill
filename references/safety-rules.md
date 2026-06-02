# Destructive-operation red lines

This skill operates on **real resources in production environments**. The following operations are irreversible or affect live services. **Before executing, you must restate to the user what is about to happen and wait for explicit confirmation.** **Never proactively add a confirmation-skipping flag** — `--force` (or its `-f` short) on `app delete`, or `--force` on `deploy`. ⚠️ Note `-f` is overloaded: on `{app,service,database} env sync` it means `--file` (the `.env` path, required) and is completely safe — don't avoid *that* one. There is no global `--force` in v1.6.2; see the per-command breakdown in `references/cli-cheatsheet.md` (Output formats & global flags).

## Severity tiers

### 🔴 Red line: irreversible, must confirm + restate the impact before executing

| Operation | Consequence | Must do before executing |
|---|---|---|
| `coolify database delete <uuid>` | Deletes the database; data may be permanently lost | 1. Confirm there is a recent backup: `coolify database backup executions <db-uuid> <backup-uuid>`; 2. Restate the database name to the user; 3. Wait for an explicit "confirm delete" |
| `coolify app delete <uuid>` | Deletes the app and its configuration | Restate the app name + confirm; remind about associated data/volumes |
| `coolify service delete <uuid>` | Deletes the service | Restate the service name + confirm |
| `coolify context delete <name>` | Deletes the local connection config | Confirm whether you still need to manage that instance |
| `coolify app env delete <app-uuid> <env-uuid>` | Deletes an environment variable | Confirm that the variable has no references in use |
| Any command with `--delete-volumes` | Deletes data volumes | This is data destruction, the highest level of confirmation |

### 🟡 Caution: affects live availability, requires confirmation in production

| Operation | Consequence |
|---|---|
| `coolify app stop` / `service stop` / `database stop` (production) | The live service goes offline, visible to users |
| `coolify deploy name\|uuid ... --force` (force deploy) | May overwrite a working version; first confirm that forcing is genuinely needed (`--force` only — no `-f` short) |
| `coolify app restart` (production peak hours) | Brief interruption; safer during off-peak hours |
| `coolify database backup delete` | Deletes a backup, reducing recoverability |
| `coolify database create/update ... --is-public` (public database port) | Exposes the database TCP port to the public internet, visible to internet-wide scanners; Coolify databases **do not enable TLS** by default, so plaintext credentials/data are at risk of leaking. **Never default to this**; first follow the standard procedure below |

### 🟢 Safe: read-only or reversible, can be executed directly

- All `list` / `get` / `logs` / `verify` / `version`
- `coolify app env list` / `sync` (sync only adds/updates and never deletes, safe to run repeatedly)
- `coolify deploy name <app>` (non-forced, a normal deploy)
- `coolify database backup trigger` (one extra backup does no harm)
- `coolify app start` / `restart` (in the direction of restoring service)

## Database-deletion standard procedure

When you receive a request to delete a database, **follow this strictly**:

1. First list backups and confirm there is a recent usable backup:
   ```bash
   coolify database list --format=json     # Confirm the target database's uuid
   coolify database backup list <db-uuid>
   coolify database backup executions <db-uuid> <backup-uuid>
   ```
2. If there is no recent backup, **first suggest triggering a backup before deleting**:
   ```bash
   coolify database backup trigger <db-uuid> <backup-uuid>
   ```
3. Restate to the user: "About to delete database `<name>` (last four of uuid: xxxx), most recent backup time <T>. Confirm deletion?"
4. Only execute the deletion after the user has explicitly replied to confirm.

## Public database port (`--is-public`) standard procedure

Before executing any database **creation or modification** that includes `--is-public`, the Agent **must** follow this, and **never default to `--is-public`**:

1. **First confirm where the connecting client is.** Ask clearly which machine the app that will connect to this database runs on:
   - If it is **on the same Coolify host** as the database → **recommend internal direct connection, exposing no port** (`references/database-access.md` §2.1). This is the default recommendation.
   - If it is on Vercel / local / another machine → **default to recommending a tunnel approach** (Cloudflare Tunnel / Tailscale, §2.2), likewise **without** opening `--is-public`.
2. **Restate the risks to the user**: a public port = scannable and probeable by the entire internet; Coolify databases **do not enable TLS** by default, so a plaintext public connection will expose the account password and data.
3. **Only after the user explicitly insists on going public and confirms awareness of the above risks** should you execute `--is-public`, and at the same time implement the hardening checklist (strong password, restrict source IPs at the firewall rather than `0.0.0.0/0`, configure TLS for the database so the connection string can use `sslmode=require`, consider a non-standard port for noise reduction) — see `database-access.md` §2.3 for details.

> The order of recommendation is always: **internal > tunnel > public hardening**. `--is-public` is the last option, and is never the default. For a full comparison of approaches, see `references/database-access.md`.

## Token permissions (least privilege) and the 403 signal

The token's abilities cap how much an agent can do — this is the primary blast-radius control, more reliable than any "the agent will be careful" promise. Coolify (Laravel Sanctum) abilities: `read` / `deploy` / `write` / `read:sensitive` / `root`.

- **Recommended scoping**: day-to-day ops = `read` + `deploy`; add `write` only to change config or create resources; **never** issue a `root` token (it bypasses every check and can toggle the API itself). See `SKILL.md` → First-Time Setup for the full table.
- **`read:sensitive` = server-side redaction.** When the token lacks it, the server redacts passwords / secrets / compose before they ever reach the wire, and `-s` / `--show-sensitive` comes back empty. This is a hard boundary, not an honor system — prefer withholding it unless secret values are genuinely needed.
- **Allowed IPs**: restrict the token's source IPs in the Coolify API settings; blank / `0.0.0.0` means anyone holding the token can use it.
- **Team scoping**: a token only sees its own team's resources; managing another team needs a separate token.
- **On `403 Forbidden`, read the response body.** Coolify's 403 lists the *missing* permissions. Run the failing command with `--debug` to see that body and identify exactly which ability the token lacks — then either add that ability in the Web UI or stop, rather than guessing. Do **not** "fix" a 403 by reaching for a `root` token.

## Meta-rules for the Agent

- **When unsure, ask.** For any operation where you cannot be certain whether it affects production, stop and ask the user instead of deciding for them.
- **Confirm batch operations one by one.** When running `deploy batch` or looping over multiple resources, first list the complete inventory for the user to review.
- **Don't leak secrets, and don't touch the token store.** Never print a token in plaintext in replies. The CLI **legitimately persists the token** at `~/.config/coolify/config.json` (file mode `0600`, directory `0750`) — that is its proper store, not something to "fix" or relocate. But the agent must never `cat` that file, echo its contents, or copy it elsewhere. To rotate a token use `coolify context set-token <name> <new-token>` (generate the replacement in the Web UI first); if the host may be compromised, revoke the token in the Web UI and rotate immediately, since anything with local read access to that file can use it. The output of `-s` / `--show-sensitive` (database passwords, connection strings, internal addresses) is shown only when the user currently needs it — **don't proactively echo it, don't write it to files, and don't copy it anywhere outside the chat**; mask passwords in connection strings with `***` before displaying whenever possible.
- **Don't silence errors.** When a command fails, give the real error to the user; don't paper over it as if "everything looks fine".
