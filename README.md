<p align="center">
  <img src="hero.svg" alt="coolify-ops — operate your self-hosted Coolify through the official CLI, in natural language" width="820">
</p>

# coolify-ops

**English** | [简体中文](README.zh-CN.md)

> A **Claude Code / Codex agent skill** — drive the official [`coolify` CLI](https://github.com/coollabsio/coolify-cli) with natural language to remotely deploy, operate, and troubleshoot apps / services / databases on a self-hosted [Coolify](https://coolify.io) instance.

**It runs entirely on top of the official CLI.** This skill never touches your server directly — it translates your natural-language intent into [coollabsio/coolify-cli](https://github.com/coollabsio/coolify-cli) commands, and the CLI talks to Coolify's REST API over a Bearer token (not your server's SSH login). Because the CLI keeps evolving, the skill has the agent run `coolify <cmd> --help` to check flags rather than hard-coding them, avoiding version drift.

Once installed, just talk to the agent in plain language, e.g.:

- "Redeploy my-app and tell me the result when it's done"
- "The worker service looks down — pull the logs and check"
- "Sync .env.production to my-app, then redeploy"

The agent enables this skill automatically: look up the UUID → trigger the deploy → follow the logs → report back, **always confirming with you before any destructive action**.

## Requirements

- A self-hosted **Coolify** instance (typically one VPS running a few Node / Next.js / Docker services).
- A Coolify **API token** (generate it in the Web UI under `/security/api-tokens`). **Scope it least-privilege**: `read` + `deploy` for day-to-day ops, add `write` only to change config / create resources, and **never** hand an agent a `root` token. Details in [`references/safety-rules.md`](references/safety-rules.md).
- The official **coolify CLI** ([coollabsio/coolify-cli](https://github.com/coollabsio/coolify-cli), the Go build — install it with the script below).
- **Claude Code**, or any other agent that supports `SKILL.md` (e.g. Codex).

> Compatibility: tested against coolify-cli v1.6.2 / Coolify v4.1.1.

## Install

### Via [skills.sh](https://skills.sh) — recommended

With Node.js installed, add this skill to your agent in one command (no clone needed):

```bash
# Project-level — into ./.claude/skills (the default when run inside a project)
npx skills add hifizz/coolify-ops-skill
```

```bash
# Global / user-level — into ~/.claude/skills (available in every project)
npx skills add hifizz/coolify-ops-skill -g
```

```bash
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

## Capabilities

| ✅ The CLI can | 🖥️ Still nicer in the Web UI |
|---|---|
| **Create apps** from a public/private git repo, Dockerfile, or image (`app create`) | First-time visual scaffolding & browsing one-click templates |
| **Create one-click services** (`service create --list-types`) | Live dashboards, metrics & resource graphs |
| Create & back up databases | A few advanced / visual-only settings |
| Deploy / redeploy, follow logs, troubleshoot | |
| Sync environment variables (`env sync`, batch upsert) | |
| Lifecycle management (start / stop / restart) | |
| Decide how a database is exposed (internal / tunnel / hardened public) | |

> The CLI now covers resource creation end-to-end; the Web UI remains handy for visual setup, dashboards, and a few advanced settings.

## Things to watch out for

- **Destructive actions are confirmed.** Deleting a database/app, stopping production, force-deploying, and the like — the agent restates the impact and waits for your confirmation, and **never adds `-f` to skip confirmation on its own**. See [`references/safety-rules.md`](references/safety-rules.md).
- **Don't expose databases to the public carelessly.** When a database needs external access, the order of preference is **internal > tunnel > hardened public**, and `--is-public` is off by default. To connect over a domain, turn off Cloudflare's orange cloud, and note that Coolify databases ship **without TLS** by default (a plaintext public connection leaks credentials). Full guide: [`references/database-access.md`](references/database-access.md).
- **Credentials stay private.** The agent won't print tokens in its replies or copy them out of the CLI's own config store (`~/.config/coolify/config.json`, mode `0600`, where the CLI legitimately keeps them); passwords / connection strings surfaced by `--show-sensitive` are redacted as needed.
- **Trust `--help` over the cheatsheet.** The CLI evolves; if a flag or JSON field ever looks off, confirm with `coolify <cmd> --help` before relying on it.

## Project layout

```
coolify-ops/
├── SKILL.md                    # Entry point: principles + decision tree + resource creation
├── references/
│   ├── cli-cheatsheet.md       # Full command reference + jq recipes + troubleshooting table
│   ├── deploy-patterns.md      # Node/Next/Docker/static deploy templates + env layering + magic vars
│   ├── database-access.md      # Database external access: protocol basics + internal/tunnel/hardened public + domains
│   └── safety-rules.md         # Destructive-operation red lines & confirmation checklist
└── scripts/
    ├── doctor.sh               # Preflight: CLI version / jq / connectivity / token abilities
    ├── install-cli.sh          # Cross-platform installer for the official CLI
    ├── health-check.sh         # One-shot health check (CLI / context / resource status)
    ├── deploy-and-watch.sh     # Deploy + follow logs until success / failure
    └── gen-reference.sh        # Dump this CLI version's full reference → references/_generated/
```

## License

[MIT](LICENSE) © 2026 hifizz

