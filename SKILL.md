---
name: coolify-ops
description: 通过官方 coolify CLI 远程操控 Coolify 实例，完成应用/服务/数据库的部署、运维、排障。Use this skill whenever the user wants to deploy, restart, redeploy, roll back, check logs or deployment status, scale or adjust resources, bind a domain, add/change/sync environment variables, create or back up databases, expose a database port, or troubleshoot any resource on a Coolify instance — including phrases like "部署到 Coolify"、"重启那个服务"、"看下部署日志"、"查部署状态"、"同步环境变量到线上"、"加个环境变量"、"给它绑个域名"、"扩容/调一下资源"、"备份数据库"、"回滚到上一个版本"、"把数据库端口暴露出去"、"Coolify 上那个 app 挂了"，or when they mention a Coolify app/service/database UUID and want an operation performed. Also trigger when the user wants to set up the coolify CLI for the first time or add a new Coolify context.
---

# Coolify Ops

通过官方 `coolify` CLI（Go 版本，coollabsio/coolify-cli）远程操控 Coolify 实例。本 skill 假设操作对象是用户自己的自托管 Coolify（典型：一台 VPS + 已部署若干 Node/Next.js/Docker 服务）。

## 核心原则

1. **CLI 是 HTTP API 客户端，不是 SSH。** 所有操作通过 Bearer Token 调 Coolify REST API，跟服务器的 SSH 凭证无关。如果命令连不上，先怀疑 API 可达性和 Token，而不是 SSH。

2. **CLI 自带文档，优先 `--help` 而非记忆。** CLI 版本在演进，flag 会变。不确定子命令或参数时，先跑 `coolify <command> --help` 再动手，不要凭记忆猜 flag。常见层级：
   ```bash
   coolify --help
   coolify app --help
   coolify app deployments --help
   coolify database --help
   ```

3. **给自己用 JSON，给人看用 table。** 需要解析输出（拿 UUID、判断状态）时一律加 `--format=json`，再用 `jq` 提取。直接给用户看状态时用默认 table。

4. **危险操作先确认。** `delete`、`stop`（生产）、强制部署等不可逆或影响线上的操作，执行前必须向用户复述将要做什么并等确认。详见 `references/safety-rules.md`。**绝不主动加 `-f` 跳过确认。**

5. **UUID 永远靠查，不靠猜。** 任何针对具体资源的操作前，先 `coolify <resource> list --format=json` 拿到真实 UUID。绝不编造或复用记忆里的 UUID。

## 首次配置（仅当 CLI 未安装或无 context 时）

```bash
# 1. 检查是否已安装
coolify --version || bash scripts/install-cli.sh

# 2. 检查是否已有 context
coolify context list

# 3. 若无，引导用户去 Coolify Web UI 的 /security/api-tokens 生成 token，然后：
coolify context add <name> <url> <token> -d
#   <name>: 自取，如 my-vps
#   <url> : 完整 URL 带 https://，不带末尾斜杠
#   -d    : 设为默认

# 4. 验证
coolify context verify
```

连不上时按 `references/cli-cheatsheet.md` 的"排障"小节逐项排查。

## 操作决策树

收到一个运维请求后，先判断类型，再走对应路径：

### A. 部署 / 重新部署一个已有资源

最高频场景。流程：

1. `coolify app list --format=json`（或 service/database）确认资源存在、拿到 name/uuid
2. 如果用户改了环境变量，先 `coolify app env sync <uuid> --file <.env>`（见路径 D）
3. 触发部署：优先用 name（好记），`coolify deploy name <app-name>`
4. **部署后必须跟进**：用 `scripts/deploy-and-watch.sh <app-uuid>` 自动追日志直到 success/fail，或手动 `coolify app deployments logs <uuid> -f`
5. 报告结果：成功则确认；失败则把关键错误行摘出来，结合 `references/deploy-patterns.md` 给出修复建议

按项目类型（Node / Next.js / Docker / 静态站）的部署配置差异，见 `references/deploy-patterns.md`。

### B. 排查一个挂掉/异常的资源

1. `coolify resources list --format=json` 看整体状态
2. `coolify app get <uuid> --format=json` 看目标资源详情
3. `coolify app logs <uuid>` 看运行时日志（容器 stdout）
4. `coolify app deployments logs <uuid>` 看最近一次部署日志（构建/启动阶段）
5. 区分故障阶段：构建失败看部署日志，运行崩溃看运行时日志，起不来看健康检查配置
6. 给出诊断 + 修复方案，修复后 `coolify app restart <uuid>` 并重新验证

### C. 生命周期操作（start / stop / restart）

```bash
coolify app start|stop|restart <uuid>
coolify service start|stop|restart <uuid>
coolify database start|stop|restart <uuid>
```

`stop` 生产资源前必须确认（见安全规则）。

### D. 环境变量管理

优先用 `.env` 文件批量同步，而非逐个 create：

```bash
coolify app env list <uuid> --format=json          # 先看现状
coolify app env sync <uuid> --file .env.production # 增量同步
```

**关键语义**：`env sync` 是增量的 —— 覆盖已有、创建缺失，**但不删除文件里没有的变量**。要完全镜像需先 list 再逐个 delete（删除属危险操作，需确认）。
构建时需要的变量加 `--build-time`；预览环境用 `--preview`。env 分层惯例见 `references/deploy-patterns.md`。

### E. 数据库与备份

```bash
coolify database list --format=json
coolify database create postgresql --server-uuid <s> --project-uuid <p> \
  --environment-name production --name <n> --instant-deploy
coolify database backup create <db-uuid> --frequency "0 2 * * *" --enabled --retention-days-local 7
coolify database backup trigger <db-uuid> <backup-uuid>   # 立即备份
```

支持类型：postgresql / mysql / mariadb / mongodb / redis / keydb / clickhouse / dragonfly。
**删库前**务必走安全规则里的检查清单。

**对外访问分支**：当请求涉及"让数据库对外 / 被其他机器 / 被 Vercel 访问"，或"用域名连库""暴露数据库端口"时，**先读 `references/database-access.md`**，按其推荐顺序（**内网 > 隧道 > 公网加固**）与用户确认，**不要直接 `--is-public`**。要点：数据库说 TCP 协议、不走 HTTP（`https://db.example.com` 连不上）；连库方与库同机就走内网、在外部就用隧道；确需公网先走 `safety-rules.md` 的 `--is-public` 标准流程并提醒默认无 TLS。

## 已知能力边界

- **从零创建应用**（绑 Git 仓库、设构建命令）目前 CLI 支持不完整：`app update` 能改字段，但完整的 `app create` 尚未公开。第一次创建新应用通常仍需在 Web UI 完成，CLI 接管后续运维。遇到"创建新 app"请求时，明确告诉用户这一限制，引导他在 UI 建好骨架后再用 CLI 配置和部署。
- **一键服务的创建**同理，需在 Web UI 选模板，CLI 负责创建后的 env 同步和生命周期管理。

## 参考文件

- `references/cli-cheatsheet.md` — 全量命令速查 + 排障表 + 输出格式与全局 flag。需要查具体命令语法时读它。
- `references/deploy-patterns.md` — Node / Next.js / Docker / 静态站四类项目的部署配置模板、env 分层惯例、Coolify magic variables（SERVICE_URL_* / SERVICE_PASSWORD_*）。部署或排构建问题时读它。
- `references/safety-rules.md` — 危险操作红线与确认清单。执行任何 delete/stop/强制操作前读它。
- `references/database-access.md` — 如何从外部访问 Coolify 上的数据库：协议认知、内网/隧道/公网加固四级方案、用域名连库（Cloudflare 灰云）、TLS 警告。涉及"让数据库对外访问/暴露端口/用域名连库"时读它。

## 脚本

- `scripts/install-cli.sh` — 跨平台安装官方 CLI（macOS/Linux，自动检测架构）。
- `scripts/health-check.sh` — 一键体检：CLI 是否在、context 是否通、各资源状态。排查"整体怎么样"时先跑它。
- `scripts/deploy-and-watch.sh <app-uuid-or-name>` — 触发部署并自动跟随日志，直到部署 success 或 failed 才返回。部署的默认推荐方式。
