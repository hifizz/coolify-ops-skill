# Coolify CLI 命令速查

> 这是 `coolify` CLI（coollabsio/coolify-cli，Go 版本）的命令参考。CLI 在持续演进，**flag 以 `coolify <cmd> --help` 的实际输出为准**，本表是常用项的快查。

## 目录

- [Context（连接管理）](#context)
- [资源总览](#资源总览)
- [应用 App](#应用-app)
- [部署 Deploy](#部署-deploy)
- [环境变量 Env](#环境变量-env)
- [数据库 Database](#数据库-database)
- [服务 Service](#服务-service)
- [服务器 Server](#服务器-server)
- [输出格式与全局 flag](#输出格式与全局-flag)
- [排障表](#排障表)

## Context

```bash
coolify context add <name> <url> <token> -d   # 添加并设为默认；-d 可省
coolify context list                          # 列出所有
coolify context get <name>                     # 详情
coolify context use <name>                     # 切默认
coolify context set-token <name> <new-token>   # 换 token
coolify context update <name> --url <new-url>  # 改 URL
coolify context delete <name>                  # 删除
coolify context verify                          # 验证当前 context 连通性 + 鉴权
coolify context version                         # 查 Coolify 后端版本
```

多 context 临时切换（不改默认）：`coolify --context=<name> <command>`

## 资源总览

```bash
coolify resources list          # 一次看到所有资源（app+db+service）及状态
coolify projects list           # 项目列表
coolify projects get <uuid>     # 项目下的 environments
coolify server list             # 服务器列表
```

## 应用 App

```bash
coolify app list                          # 列出所有 app
coolify app get <uuid>                     # 详情
coolify app start|stop|restart <uuid>      # 生命周期
coolify app delete <uuid>                  # 删除（危险，需确认；勿主动加 -f）
coolify app logs <uuid>                     # 运行时日志（容器 stdout）

# 改配置（注意：是改已有 app，不是创建）
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

### 部署日志（构建/启动阶段）

```bash
coolify app deployments list <app-uuid>                  # 历次部署
coolify app deployments logs <app-uuid>                  # 最近一次部署的全部日志
coolify app deployments logs <app-uuid> -f               # 实时跟随（tail -f 式）
coolify app deployments logs <app-uuid> -n 100           # 最后 100 行
coolify app deployments logs <app-uuid> <deployment-uuid> # 指定某次部署
```

**运行时日志 vs 部署日志的区别**：`app logs` 看容器跑起来后的 stdout（排查运行崩溃）；`app deployments logs` 看构建→推送→启动过程（排查部署失败）。

## 部署 Deploy

```bash
coolify deploy name <app-name>           # 按名字部署（推荐，好记）
coolify deploy uuid <uuid>               # 按 UUID 部署
coolify deploy batch <a>,<b>,<c>         # 批量部署多个
coolify deploy name <app-name> -f        # 强制部署（无变更也部署；慎用）
coolify deploy list                       # 所有部署记录
coolify deploy get <deployment-uuid>      # 单个部署详情
coolify deploy cancel <deployment-uuid>   # 取消进行中的部署
```

## 环境变量 Env

> app 和 service 的 env 子命令完全一致，下面以 app 为例。

```bash
coolify app env list <app-uuid>
coolify app env get <app-uuid> <env-uuid-or-key>
coolify app env create <app-uuid> --key KEY --value VAL [--build-time] [--preview] [--is-literal] [--is-multiline]
coolify app env update <app-uuid> <env-uuid> --value NEW
coolify app env delete <app-uuid> <env-uuid>

# 批量从 .env 同步（最常用）
coolify app env sync <app-uuid> --file .env
coolify app env sync <app-uuid> --file .env.production --build-time
```

**sync 行为**：更新已有 + 创建缺失，**不删除**文件中没有的变量。
**flag 含义**：`--build-time` 构建期可用；`--preview` 预览部署可用；`--is-literal` 不做变量插值（值里有 `$` 时用）；`--is-multiline` 多行值。

## 数据库 Database

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
coolify database delete <uuid>   # 危险，需确认

# 备份
coolify database backup list <db-uuid>
coolify database backup create <db-uuid> \
  --frequency "0 2 * * *" --enabled \
  [--save-s3 --s3-storage-uuid <uuid>] \
  [--retention-days-local 7] [--retention-amount-local 5]
coolify database backup trigger <db-uuid> <backup-uuid>       # 立即备份
coolify database backup executions <db-uuid> <backup-uuid>    # 备份执行记录
```

cron 速记：`"0 2 * * *"` = 每天 02:00；`"0 */6 * * *"` = 每 6 小时。

## 服务 Service

```bash
coolify service list
coolify service get <uuid>
coolify service start|stop|restart <uuid>
coolify service delete <uuid>            # 危险，需确认
coolify service env sync <uuid> --file .env
```

## 服务器 Server

```bash
coolify server list
coolify server get <uuid>                # 详情
coolify server get <uuid> --resources    # 含该服务器上的资源及状态
coolify server validate <uuid>           # 验证连接
coolify server domains <uuid>            # 该服务器的域名
```

## 输出格式与全局 flag

```bash
--format=table      # 默认，给人看
--format=json       # 给脚本/Agent 解析，配 jq 用
--format=pretty     # 缩进 JSON，调试用

--context=<name>    # 临时指定 context
--host <fqdn>       # 临时覆盖 URL
--token <token>     # 临时覆盖 token（CI 场景）
-s, --show-sensitive # 显示敏感信息（token/IP）
--debug             # 打印完整 HTTP 请求/响应（排障神器）
-f, --force         # 跳过确认（仅在用户明确同意后使用）
```

常用 jq 配方：

```bash
# 按名字找 app 的 uuid
coolify app list --format=json | jq -r '.[] | select(.name=="my-app") | .uuid'

# 列出所有非 running 状态的资源
coolify resources list --format=json | jq -r '.[] | select(.status!="running") | "\(.name): \(.status)"'
```

## 排障表

| 现象 | 可能原因 | 处理 |
|---|---|---|
| `connection refused` / 超时 | URL 错；VPS 防火墙没放行；Coolify 没起来 | 先 `curl -I <url>` 测 Web 入口；检查 VPS 防火墙端口 |
| `401 Unauthorized` | Token 错或被删 | Web UI 重新生成 token，`coolify context set-token` 更新 |
| `403 Forbidden` | Token 权限不足 | 检查该 token 在 Coolify 里的权限范围 |
| `certificate verify failed` | HTTPS 证书没配好 | 临时用 http://，或先在 Coolify 配好 TLS |
| 命令找不到资源 | UUID 过期/记错 | 重新 `<resource> list --format=json` 拿 UUID |
| 不确定 flag | CLI 版本差异 | `coolify <cmd> --help` 看当前版本实际 flag |
| 想看请求细节 | — | 任意命令前加 `--debug` |
