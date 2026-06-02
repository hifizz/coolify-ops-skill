# Coolify 部署模式参考

按项目类型给出 Coolify 的典型配置。Coolify 用 Nixpacks 自动检测大多数项目，所以很多时候不需要手动设构建命令；下面标注哪些需要手动覆盖。

## 目录

- [构建方式：Nixpacks vs Dockerfile](#构建方式)
- [Node.js / API 服务](#nodejs--api-服务)
- [Next.js](#nextjs)
- [Docker / Docker Compose](#docker--docker-compose)
- [静态站点](#静态站点)
- [环境变量分层惯例](#环境变量分层惯例)
- [Coolify Magic Variables](#coolify-magic-variables)
- [部署失败排查清单](#部署失败排查清单)

## 构建方式

Coolify 支持几种 build pack：

- **Nixpacks**（默认）：自动检测语言和框架，零配置最省心。Node/Next/Python/Go 大多能直接识别。
- **Dockerfile**：项目里有 Dockerfile 时用，控制力最强。
- **Docker Compose**：多容器编排。
- **Static**：纯静态产物。

选择优先级：**能用 Nixpacks 就用 Nixpacks**；需要精确控制运行时/系统依赖时上 Dockerfile。

## Node.js / API 服务

Nixpacks 通常自动识别。需要手动覆盖时：

```bash
coolify app update <uuid> \
  --install-command "pnpm install --frozen-lockfile" \
  --build-command "pnpm build" \
  --start-command "node dist/index.js" \
  --ports-exposes 3000 \
  --health-check-enabled --health-check-path /health
```

要点：
- **包管理器**：Coolify 看 lockfile 自动选 npm/yarn/pnpm。pnpm 项目确保 `pnpm-lock.yaml` 已提交。
- **端口**：`--ports-exposes` 必须跟你应用实际监听的端口一致（应用要监听 `0.0.0.0` 而非 `127.0.0.1`，否则容器外访问不到）。
- **健康检查**：长跑服务建议开，给一个轻量的 `/health` 路由返回 200。

## Next.js

Next.js 在 Coolify 上有两种跑法：

**A. Standalone（推荐，镜像小）**
`next.config.js` 设 `output: 'standalone'`，然后：
```bash
coolify app update <uuid> \
  --build-command "pnpm build" \
  --start-command "node .next/standalone/server.js" \
  --ports-exposes 3000
```

**B. 默认 next start**
```bash
coolify app update <uuid> \
  --build-command "pnpm build" \
  --start-command "pnpm start" \
  --ports-exposes 3000
```

要点：
- `NEXT_PUBLIC_*` 变量是**构建期注入**的，必须用 `--build-time` 同步，否则前端拿不到：
  ```bash
  coolify app env sync <uuid> --file .env.production --build-time
  ```
- 服务端运行时变量（数据库连接串、API key）正常 sync 即可，不需要 `--build-time`。
- 注意区分：同一个 `.env` 里如果既有 `NEXT_PUBLIC_*` 又有服务端密钥，可能需要分两次 sync（一次带 `--build-time` 只给前端变量，一次不带给后端），或全部 build-time 也行但密钥会进构建层，权衡安全性。

## Docker / Docker Compose

项目有 Dockerfile：
```bash
coolify app update <uuid> \
  --dockerfile "$(cat Dockerfile)" \
  --ports-exposes 8080
```
更常见的是让 Coolify 直接读仓库里的 Dockerfile（在 Web UI 选 Dockerfile build pack，CLI 端确保 `--ports-exposes` 对）。

直接用现成镜像：
```bash
coolify app update <uuid> \
  --docker-image ghcr.io/me/my-service \
  --docker-tag latest \
  --ports-exposes 8080
```

## 静态站点

构建产物目录是关键：
```bash
coolify app update <uuid> \
  --build-command "pnpm build" \
  --publish-directory dist        # Vite→dist；Next export→out；CRA→build
```

## 环境变量分层惯例

推荐的本地 → Coolify 映射：

| 本地文件 | 用途 | 同步命令 |
|---|---|---|
| `.env.local` | 本地开发，**不提交、不同步** | 不 sync |
| `.env.production` | 生产配置（不含密钥的部分） | `coolify app env sync <uuid> --file .env.production` |
| 密钥 | 数据库串/API key 等 | 单独 `env create`，或放进一个 gitignore 的 `.env.secrets` 单独 sync |

红线：
- **密钥永远不进 Git**。`.env.production` 如果含密钥，加进 `.gitignore`；只把不敏感的配置提交。
- sync 不会删除变量，所以反复 sync 安全；但要清理废弃变量得手动 delete。
- 改完 env **必须重新部署**才生效：`coolify deploy name <app>`（运行时变量重启即可，构建期变量必须重新构建）。

## Coolify Magic Variables

Coolify 在部署一组关联资源（如 app + 它的数据库）时，提供一批自动注入的"魔法变量"，省得手填连接信息。常见前缀：

- `SERVICE_URL_<NAME>` — 某服务的可访问 URL
- `SERVICE_FQDN_<NAME>` — 某服务的完全限定域名
- `SERVICE_PASSWORD_<NAME>` — 自动生成的密码
- `SERVICE_USER_<NAME>` — 自动生成的用户名
- `SERVICE_BASE64_<NAME>` — 生成 base64 随机值

用法：在 env 值里直接引用，例如数据库密码用 `${SERVICE_PASSWORD_POSTGRES}`，Coolify 部署时替换。这能避免把生成的密码硬编码进配置。具体可用变量名取决于你在同一 project/environment 里部署了哪些服务，不确定时在 Web UI 的 Environment Variables 面板能看到候选。

## 部署失败排查清单

按这个顺序查：

1. `coolify app deployments logs <uuid>` — 看部署日志，定位失败在哪一阶段
2. **install 阶段失败** → lockfile 没提交，或包管理器识别错（检查 `--install-command`）
3. **build 阶段失败** → 构建命令错，或缺构建期环境变量（`NEXT_PUBLIC_*` 没加 `--build-time`）
4. **启动后立刻退出** → `--start-command` 错，或端口没监听 `0.0.0.0`，或缺运行时环境变量
5. **构建成功但访问 502** → `--ports-exposes` 跟应用实际端口不一致；或健康检查路径返回非 200
6. **健康检查一直 unhealthy** → `--health-check-path` 指向的路由不存在或返回错误码

每修一项后重新 `coolify deploy name <app>` 并用 `deploy-and-watch.sh` 跟进。
