# coolify-ops

一个让 Claude Code / Codex 通过官方 `coolify` CLI 远程操控自托管 Coolify 实例的 Agent Skill。

针对场景：本地 macOS + 远端 VPS（已装 Coolify），部署/运维 Node、Next.js、Docker 类服务。

## 安装

放到 Claude Code 的 skills 目录即可自动加载：

```bash
# 全局（对所有项目生效）
cp -r coolify-ops ~/.claude/skills/

# 或项目级（只对当前项目）
cp -r coolify-ops .claude/skills/
```

Codex 等其他支持 SKILL.md 的 Agent，放到对应的 skills 目录。

## 首次使用

第一次让 Agent 操作前，确保 CLI 装好、context 配好：

```bash
bash ~/.claude/skills/coolify-ops/scripts/install-cli.sh
coolify context add my-vps https://coolify.your-domain.com <token> -d
coolify context verify
```

token 在 Coolify Web UI 的 `/security/api-tokens` 生成。

之后直接对 Agent 说自然语言即可，例如：
- "把 my-app 重新部署一下，部署完跟我说结果"
- "线上那个 worker 服务好像挂了，帮我查一下"
- "把 .env.production 同步到 my-app 然后重新部署"

## 结构

```
coolify-ops/
├── SKILL.md                    # 主入口：原则 + 操作决策树 + 能力边界
├── references/
│   ├── cli-cheatsheet.md       # 全量命令速查 + jq 配方 + 排障表
│   ├── deploy-patterns.md      # Node/Next/Docker/静态站部署模板 + env 分层 + magic vars
│   └── safety-rules.md         # 危险操作红线与确认清单
└── scripts/
    ├── install-cli.sh          # 跨平台安装 CLI
    ├── health-check.sh         # 一键体检
    └── deploy-and-watch.sh     # 部署 + 自动跟日志直到 success/fail
```

## 设计取舍

- **不硬编码易变的 flag**：CLI 在演进，skill 鼓励 Agent 用 `coolify <cmd> --help` 自查，避免版本漂移。
- **安全优先**：所有 delete/stop/强制操作都要求 Agent 先确认，绝不主动 `-f`。
- **部署闭环**：部署不止"触发"，而是触发→跟日志→报结果的完整链路。

## 维护

CLI 出新版后，主要可能需要更新 `references/cli-cheatsheet.md` 里的命令；SKILL.md 的原则和决策树通常无需改动。
