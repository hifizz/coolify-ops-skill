# coolify-ops

**English** | [简体中文](README.zh-CN.md)

> A **Claude Code / Codex agent skill** — drive the official [`coolify` CLI](https://github.com/coollabsio/coolify-cli) with natural language to remotely deploy, operate, and troubleshoot apps / services / databases on a self-hosted [Coolify](https://coolify.io) instance.

**It runs entirely on top of the official CLI.** This skill never touches your server directly — it translates your natural-language intent into [coollabsio/coolify-cli](https://github.com/coollabsio/coolify-cli) commands, and the CLI talks to Coolify's REST API over a Bearer token (nothing to do with SSH). Because the CLI keeps evolving, the skill has the agent run `coolify <cmd> --help` to check flags rather than hard-coding them, avoiding version drift.

Once installed, just talk to the agent in plain language, e.g.:

- "Redeploy my-app and tell me the result when it's done"
- "The worker service looks down — pull the logs and check"
- "Sync .env.production to my-app, then redeploy"

The agent enables this skill automatically: look up the UUID → trigger the deploy → follow the logs → report back, **always confirming with you before any destructive action**.

## Requirements

- A self-hosted **Coolify** instance (typically one VPS running a few Node / Next.js / Docker services).
- A Coolify **API token** (generate it in the Web UI under `/security/api-tokens`).
- The official **coolify CLI** ([coollabsio/coolify-cli](https://github.com/coollabsio/coolify-cli), the Go build — install it with the script below).
- **Claude Code**, or any other agent that supports `SKILL.md` (e.g. Codex).

> Compatibility: Tested against coolify-cli vX.X.X / Coolify vX.X.X (fill in the versions you actually verified).

## Install

### Via [skills.sh](https://skills.sh) — recommended

With Node.js installed, add this skill to your agent in one command (no clone needed):

```bash
# Project-level — into ./.claude/skills (the default when run inside a project)
npx skills add hifizz/coolify-ops-skill

# Global / user-level — into ~/.claude/skills (available in every project)
npx skills add hifizz/coolify-ops-skill -g

# Target a specific agent explicitly (defaults to the detected one)
npx skills add hifizz/coolify-ops-skill --agent claude-code
```

This pulls the `coolify-ops` skill from this repo. Manage it later with:

```bash
npx skills list                 # list installed skills
npx skills update coolify-ops   # update to the latest version
npx skills remove coolify-ops   # uninstall
```

> `skills.sh` works with any compatible agent — Claude Code, Codex, Cursor, Copilot, Windsurf, and more. Browse the directory at [skills.sh](https://skills.sh).

### Manual install

Prefer not to use `npx`? Clone and copy the skill folder into your agent's skills directory (the folder must be named `coolify-ops`, matching the skill's `name`):

```bash
git clone https://github.com/hifizz/coolify-ops-skill

# Claude Code · global (all projects)
cp -r coolify-ops-skill ~/.claude/skills/coolify-ops

# Claude Code · per-project (current project only)
cp -r coolify-ops-skill .claude/skills/coolify-ops
```

For Codex and other agents, place it in their respective skills directory.

## First-time setup

Before letting the agent operate anything, install the CLI and configure a connection (context):

```bash
# 1) Install the official coolify CLI (auto-detects macOS / Linux; skips if already present)
#    Path depends on install scope: ~/.claude/skills/... if global, ./.claude/skills/... if project-level.
bash ~/.claude/skills/coolify-ops/scripts/install-cli.sh

# 2) Add a context and set it as default (generate the token in the Coolify Web UI: /security/api-tokens)
coolify context add my-vps https://coolify.your-domain.com <token> -d

# 3) Verify connectivity and auth
coolify context verify
```

## Usage

Once configured, you don't need to memorize commands — describe what you want in natural language and the agent enables this skill and runs it. Common cases:

- **Deploy / redeploy**: "Redeploy my-app", "Ship this change"
- **Troubleshooting**: "xxx service is throwing 502, take a look", "Why did the last deploy fail?"
- **Environment variables**: "Sync .env.production to my-app", "Add a `NEXT_PUBLIC_API_URL` to it"
- **Lifecycle**: "Restart that database", "Stop the worker for now"
- **Databases & backups**: "Set up a daily 2am backup for my-db", "Let me connect to this database from my laptop"
- **Domains / resources**: "Bind a domain to it", "Bump memory to 1G"

## Capabilities (can / can't)

| ✅ Can do | ❌ Can't do (use the Web UI) |
|---|---|
| Deploy / redeploy existing apps & services | **Create an app from scratch** (bind a Git repo, set build commands) — not fully supported by the CLI |
| Operate & troubleshoot (runtime / deploy logs, status) | **Create one-click services** (template services) — pick the template in the Web UI |
| Sync environment variables (`env sync`, batch upsert) | |
| Create & back up databases | |
| Lifecycle management (start / stop / restart) | |
| Decide how a database is exposed (internal / tunnel / hardened public) | |

> Convention: build the "skeleton" in the Web UI (a new app / one-click service), then let the CLI take over configuration, deployment, and operations.

## Things to watch out for

- **Destructive actions are confirmed.** Deleting a database/app, stopping production, force-deploying, and the like — the agent restates the impact and waits for your confirmation, and **never adds `-f` to skip confirmation on its own**. See [`references/safety-rules.md`](references/safety-rules.md).
- **Don't expose databases to the public carelessly.** When a database needs external access, the order of preference is **internal > tunnel > hardened public**, and `--is-public` is off by default. To connect over a domain, turn off Cloudflare's orange cloud, and note that Coolify databases ship **without TLS** by default (a plaintext public connection leaks credentials). Full guide: [`references/database-access.md`](references/database-access.md).
- **Credentials stay private.** The agent won't print tokens in its replies or write them to files; passwords / connection strings surfaced by `--show-sensitive` are redacted as needed.
- **Trust `--help` over the cheatsheet.** The CLI evolves; a few flags marked ⚠️ in the cheatsheet are unverified — confirm them with `coolify <cmd> --help` before relying on them.

## Project layout

```
coolify-ops/
├── SKILL.md                    # Entry point: principles + decision tree + capability boundaries
├── references/
│   ├── cli-cheatsheet.md       # Full command reference + jq recipes + troubleshooting table
│   ├── deploy-patterns.md      # Node/Next/Docker/static deploy templates + env layering + magic vars
│   ├── database-access.md      # Database external access: protocol basics + internal/tunnel/hardened public + domains
│   └── safety-rules.md         # Destructive-operation red lines & confirmation checklist
└── scripts/
    ├── install-cli.sh          # Cross-platform installer for the official CLI
    ├── health-check.sh         # One-shot health check (CLI / context / resource status)
    └── deploy-and-watch.sh     # Deploy + follow logs until success / failure
```

## License

[MIT](LICENSE) © 2025 hifizz

---

> Documentation is available in [English](README.md) and [简体中文](README.zh-CN.md).
