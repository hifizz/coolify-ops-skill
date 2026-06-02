# 危险操作红线

本 skill 操作的是**生产环境的真实资源**。以下操作不可逆或会影响线上服务，**执行前必须向用户复述将要做的事并等待明确确认**。**绝不主动加 `-f`/`--force` 跳过确认。**

## 分级

### 🔴 红线：不可逆，执行前必须确认 + 复述影响

| 操作 | 后果 | 执行前必做 |
|---|---|---|
| `coolify database delete <uuid>` | 删库，数据可能永久丢失 | 1. 确认有最新备份：`coolify database backup executions`；2. 复述库名给用户；3. 等明确"确认删除" |
| `coolify app delete <uuid>` | 删应用及其配置 | 复述 app 名 + 确认；提醒关联数据/卷 |
| `coolify service delete <uuid>` | 删服务 | 复述服务名 + 确认 |
| `coolify context delete <name>` | 删本地连接配置 | 确认是否还要管理该实例 |
| `coolify app env delete` | 删环境变量 | 确认该变量无在用引用 |
| 任何带 `--delete-volumes` 的命令 | 删数据卷 | 这是数据销毁，最高级别确认 |

### 🟡 注意：影响线上可用性，生产环境需确认

| 操作 | 后果 |
|---|---|
| `coolify app stop` / `service stop` / `database stop`（生产） | 线上服务下线，用户可见 |
| `coolify deploy ... -f`（强制部署） | 可能覆盖正常版本；先确认确实需要强制 |
| `coolify app restart`（生产高峰） | 短暂中断；低峰期更安全 |
| `coolify database backup delete` | 删除备份，降低可恢复性 |

### 🟢 安全：只读或可逆，可直接执行

- 所有 `list` / `get` / `logs` / `verify` / `version`
- `coolify app env list` / `sync`（sync 只增改不删，反复执行安全）
- `coolify deploy name <app>`（非强制，正常部署）
- `coolify database backup trigger`（多备一次无害）
- `coolify app start` / `restart`（恢复服务方向）

## 删库标准流程

收到删除数据库请求时，**严格按此走**：

1. 先列备份，确认有近期可用备份：
   ```bash
   coolify database list --format=json     # 确认目标库 uuid
   coolify database backup list <db-uuid>
   coolify database backup executions <db-uuid> <backup-uuid>
   ```
2. 如果没有近期备份，**先建议触发一次备份再删**：
   ```bash
   coolify database backup trigger <db-uuid> <backup-uuid>
   ```
3. 向用户复述："即将删除数据库 `<名字>`（uuid 末四位 xxxx），最近备份时间 <T>。确认删除吗？"
4. 仅在用户明确回复确认后执行删除。

## 给 Agent 的元规则

- **拿不准就问。** 任何无法确定是否影响生产的操作，停下来问用户，而不是替他决定。
- **批量操作逐一确认。** `deploy batch` 或循环操作多个资源时，先列出完整清单让用户过目。
- **不替用户记 token。** 不在回复里明文打印 token；不把 token 写进任何文件。
- **错误不静默。** 命令失败时把真实报错给用户，不要"看起来没问题"地糊弄过去。
