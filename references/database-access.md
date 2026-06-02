# 访问 Coolify 上的数据库

如何从外部（本地、Vercel、另一台机器、其它人）连到部署在 Coolify 上的数据库。
这是高频踩坑区，Agent 收到"让数据库被 X 访问"类请求时，**先读本文档，按推荐顺序与用户确认，不要直接 `--is-public`**。

## 决策速查

| 应用（连库方）在哪 | 推荐方案 | 要不要公网暴露数据库端口 |
|---|---|---|
| 与数据库同一台 Coolify | **内网直连**（§2.1） | ❌ 不需要 |
| 本地 / 另一台 VPS / 任何能常驻进程的环境 | **隧道**（Cloudflare Tunnel / Tailscale，§2.2） | ❌ 不需要 |
| **Vercel / 其它 serverless·edge** | **裸 TCP 隧道走不通**；改走 HTTP 层或托管连接（§2.2「Vercel 特例」/ §5） | ❌ 不直接暴露裸库 |
| 确需公网直连、且无法用隧道 | **公网 + 加固**（§2.3） | ⚠️ 是，但必须加固 |
| 想用浏览器/REST API 管理 | 部署 pgweb/Adminer/PostgREST（§5） | 走 HTTP，正常绑域名 |

---

## 1. 先搞清楚：数据库不是网站

这是所有困惑的根源，必须先讲明白：

- **数据库说的是自己的 TCP 协议，不是 HTTP。** PostgreSQL 用 Postgres wire protocol（默认端口 **5432**），MySQL/MariaDB 用 MySQL 协议（**3306**），MongoDB（**27017**）、Redis（**6379**）等同理。这些都不是 HTTP。
- **所以 `https://db.example.com/` 这种形式连不上数据库。** 浏览器、`curl https://...` 说的是 HTTP；数据库不会回应 HTTP 请求。用网址在浏览器里打开一个数据库，本质上是协议不匹配。
- **Coolify 的 Traefik 反向代理只处理 HTTP(S)。** 它根据域名/路径把 HTTP 流量分发给各容器，但它**不会**把流量转发给一个只会说数据库协议的容器。给数据库容器绑一个 Traefik 域名是无意义的——反代层根本不理解 5432 上的字节流。
- **数据库客户端用的是连接串，不是网址：**
  ```
  postgresql://user:pass@host:5432/dbname
  mysql://user:pass@host:3306/dbname
  ```
  这里的 `host` **可以是域名**（见 §3），但：没有 `https://` 前缀、**带端口号**、用数据库客户端（`psql` / DataGrip / Prisma / `pg` 库 …）连接，而不是浏览器。

一句话：**要 HTTP 入口（浏览器/REST）和要数据库连接，是两类完全不同的需求。** 先问清楚用户到底想要哪种（§5 处理前者）。

---

## 2. 四种访问方案（按推荐度排序）

### 2.1 内网直连（最推荐）

**适用：应用与数据库在同一台 Coolify。** 这是绝大多数自托管场景。

- 用 Coolify 提供的**内部连接地址**，流量在服务器内部的 Docker 网络里走，**不出服务器**。
- **无需公网暴露端口，无需域名，无需 `--is-public`。** 攻击面为零。
- 内部主机名/连接信息可从数据库详情里取：
  ```bash
  coolify database get <uuid> --format=json -s | jq .
  # -s / --show-sensitive 才会带出密码、内部连接串等敏感字段
  # 字段名以实际输出为准（如 internal_db_url / 内部主机名通常是容器名或服务名）
  ```
- 在应用的环境变量里直接填这个内部连接串即可。若 app 与 db 在同一 project/environment，还可以用 Coolify 的 magic variables（见 `deploy-patterns.md`）引用密码，避免硬编码。

> 默认就该走这条。只有当连库方确实不在这台机器上时，才往下看。

### 2.2 隧道（连库方能常驻一个隧道客户端时推荐）

**适用：应用跑在本地开发机 / 另一台 VPS / 任何能常驻一个后台进程的环境，需要连这台机器上的库。**
（**Vercel 等 serverless/edge 不适用**——它们跑不了常驻 sidecar，见本节末「⚠️ Vercel / serverless 特例」。）

不要为此开 `--is-public` 把端口怼到公网。改用加密隧道，让连库方"像在内网一样"访问。**注意：数据库是裸 TCP，下面两种方案都要求连库方那侧常驻一个隧道客户端进程**：

- **Cloudflare Tunnel**：库这侧的 VPS 上跑 `cloudflared`；连库方那侧再跑 `cloudflared access tcp --hostname db.example.com --url localhost:5432`，在本地起一个端口转发进隧道，应用连 `localhost:5432`。
  - ⚠️ 裸 TCP（Postgres/MySQL 协议）**必须**靠客户端这个 `cloudflared access` 代理——Cloudflare 免费隧道**不会**给裸 TCP 一个"任意客户端无需 sidecar 即可直连"的公网端点（那是 Enterprise 的 **Spectrum** 才有的能力）。
- **Tailscale / WireGuard**：把 VPS 和连库方加进同一个私有网络（tailnet），连库方装 `tailscaled`，用 Tailscale 内网 IP（`100.x.x.x`）连库。零公网暴露，端对端加密。

优点：**公网端口扫描器看不到数据库端口**，流量加密，凭据不在公网明文裸奔。

#### ⚠️ Vercel / serverless·edge 特例（重要，别踩）

上面两种隧道都要求连库方**常驻一个 sidecar 进程**（`cloudflared access` 或 `tailscaled`）。Vercel 的 serverless/edge 函数是**短生命周期、无状态、跑不了常驻 sidecar**，所以**这两条路对 Vercel 都走不通**——照做的结果是函数根本连不上库。Vercel 连自托管数据库的可行姿势是：

1. **在库前面挂一个会说 HTTP 的层**，让 Vercel 走 HTTPS 而不是裸 TCP——这是首选。自托管最直接的是 **PostgREST**（把你的 Coolify Postgres 表暴露成 HTTPS REST）；也可用 **Prisma Accelerate** 这类 HTTP 数据代理。详见 §5。
   - ⚠️ **PgBouncer 不算 HTTP 层**：它是 Postgres 协议的连接池，对外仍是裸 TCP，Vercel serverless 连它一样连不上；它只对"能开 TCP 连接的运行时"（常驻 Node 服务 / 另一台 VPS）解决连接数问题。
2. **公网 TLS endpoint + 加固**（§2.3）。但 Vercel serverless **默认无固定出口 IP**，§2.3 的"防火墙限制来源 IP"基本使不上，除非用 Vercel 的静态出口 IP（Secure Compute，Enterprise）。
3. **Cloudflare Spectrum**（Enterprise）给裸库一个真正的公网 TCP 端点，Vercel 无需 sidecar 直连——成本较高，按需评估。

> 一句话：**Vercel ≠ "在外部的机器"**。能跑 sidecar 的外部机器走隧道；Vercel 这类 serverless 要么走 HTTP 层（§5），要么走带静态 IP 的公网加固，别套用裸 TCP 隧道。

### 2.3 公网 + 加固（可接受，但需谨慎）

**仅当确实需要 `--is-public`、且隧道方案不可行时。** 执行前先走 `safety-rules.md` 的 `--is-public` 红线流程。开放公网端口意味着全世界的扫描器都能发现它，必须同时做到以下全部：

- **强密码**：绝不用默认/弱口令。公网上的数据库端口几小时内就会被自动化爆破。
- **防火墙限制来源 IP**：只放行已知的客户端 IP（如你的固定 IP、办公网段），**不要 `0.0.0.0/0`**。在 VPS 防火墙（ufw / 云厂商安全组）上限制 `--public-port` 对应端口的来源。
- **给数据库配 TLS**：让连接串能用 `sslmode=require`（Postgres）/ `--ssl`（MySQL），避免明文传输（见 §4——Coolify 默认通常不开 TLS，需自己配）。
- **考虑换非标准端口**：把对外端口从 5432/3306 换成别的，降低被无差别扫描命中的噪音（这是降噪，不是安全边界，别当成主要防护）。

### 2.4 ❌ 不推荐

端口对全网开放（`--is-public` + 防火墙 `0.0.0.0/0`）+ 无 TLS + 弱口令。
这等于把数据库直接挂到公网任人取用，是被勒索/删库的典型成因。Agent 绝不主动建议、绝不默认走这条。

---

## 3. 用域名连库的正确做法（澄清"能不能用 postgresql.zilin.im"）

能。域名只是 `host` 的一种写法，连库照样用 TCP，不走 HTTP。但有两个关键点：

### 3.1 DNS：加 A 记录指向 VPS IP

给子域（如 `db.example.com`）加一条 **A 记录**，指向 Coolify 所在 VPS 的公网 IP。

### 3.2 ⚠️ Cloudflare 必须关橙色云朵（设为 DNS only / 灰云）

**这是最高频的踩坑点，务必醒目提醒用户：**

> 如果域名托管在 Cloudflare，这条记录的代理状态必须是 **DNS only（灰色云朵）**，**不能是橙色云朵（Proxied）**。

原因：Cloudflare 的橙云代理**只转发 HTTP/HTTPS（80/443）流量**，它会**挡掉数据库的 TCP 流量**（5432/3306 等）。开着橙云，连接会超时或被拒——表现得像"端口没开"，但其实是 CF 在中间把非 HTTP 流量丢了。关掉橙云（灰云），DNS 只做名称解析，流量直达你的 VPS，数据库协议才能通。

（这也顺带暴露了 §1 的道理：CF 橙云 = 一个 HTTP 反代，和 Traefik 一样不懂数据库协议。）

### 3.3 连接串格式

```
postgresql://user:pass@db.example.com:5432/mydb
```

- **没有 `https://` 前缀**——它不是网站。
- **带端口号**（公网暴露时是 `--public-port` 指定的端口）。
- 用数据库客户端连，不是浏览器。
- 公网连接强烈建议带 TLS：`postgresql://user:pass@db.example.com:5432/mydb?sslmode=require`（前提是数据库侧已配好 TLS，见 §4）。

---

## 4. ⚠️ TLS / 加密警告

**Coolify 默认起的数据库容器通常没有开启 SSL/TLS。** 这意味着：

- 走公网的明文连接会把**账号、密码、以及查询数据**全部暴露在链路上，任何中间环节都能嗅探。
- **不要假设连接是加密的。** 连接串里写了 `sslmode=require` 不代表服务端真支持——若数据库没配证书，要么连不上，要么静默降级。

因此：

- **内网直连（§2.1）/ 隧道（§2.2）天然规避了这个问题**（隧道本身加密，内网不出机器）——这也是它们更被推荐的原因之一。
- **公网直连（§2.3）必须显式为数据库配置 TLS**，否则就是明文裸奔。Agent 在建议公网方案时，必须主动把这条风险讲给用户，不要默认有加密。

---

## 5. 在数据库前面挂一个会说 HTTP 的层（HTTP 入口 / serverless 连库）

两种情况都落到这里：(a) 用户真正想要的是"在浏览器里看/改数据""通过 HTTP API 读写"；(b) 连库方是 **Vercel 等 serverless/edge**（§2.2 特例），跑不了隧道 sidecar、也没有固定出口 IP，需要走 HTTPS 而非裸 TCP。解法都是在数据库前面再部署一个**会说 HTTP 的服务**：

- **浏览器管理界面**：部署 **pgweb**（Postgres）或 **Adminer**（多数据库）这类 Web 管理工具。它们是 HTTP 服务，**在内网连数据库**，自己对外走 HTTPS。
- **REST API**：部署 **PostgREST**（把 Postgres 表自动暴露成 REST API）。同样是 HTTP 服务，内网连库。
- **serverless 连库（Vercel 等）**：自托管首选 **PostgREST**（把库暴露成 HTTPS REST）；也可用 **HTTP 数据代理**（如 Prisma Accelerate），或本就托管在 **Neon / PlanetScale** 上、自带 serverless HTTP driver 的库——让 Vercel 函数发一次 HTTPS 请求，而不是维持一条裸 TCP 长连接。
  - ⚠️ **PgBouncer 不是 HTTP 层**：它是 Postgres 协议的连接池，对外仍是裸 TCP；Vercel serverless 连它依旧是裸 TCP（连不上）。PgBouncer 只对"能开 TCP 连接的运行时"（常驻 Node 服务 / 另一台 VPS）解决连接数问题，别拿它给 serverless 当 HTTPS 入口。

这些服务才可以正常绑 Traefik 域名、走 HTTPS、开橙云——因为它们说的就是 HTTP。数据库本身仍只在内网，不对公网暴露 TCP 端口。

> 在 Coolify 上，这类工具通常作为独立 app/service 部署，部署与运维流程见 `deploy-patterns.md` 与 SKILL.md 的常规路径；这层 HTTP 服务连库用 §2.1 的内部地址即可。
