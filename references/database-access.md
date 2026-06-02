# Accessing Databases on Coolify

How to connect, from the outside (your laptop, Vercel, another machine, someone else), to a database deployed on Coolify.
This is a high-frequency pitfall area. When the Agent receives a request like "make the database accessible to X", **read this document first, confirm with the user following the recommended order, and do not jump straight to `--is-public`**.

## Decision quick-reference

| Where the app (the connecting client) lives | Recommended approach | Need to expose the DB port to the public internet? |
|---|---|---|
| Same Coolify host as the database | **Internal direct connection** (§2.1) | ❌ No |
| Local / another VPS / any environment that can run a persistent process | **Tunnel** (Cloudflare Tunnel / Tailscale, §2.2) | ❌ No |
| **Vercel / other serverless·edge** | **Raw TCP tunnel won't work**; use an HTTP layer or a managed connection instead (§2.2 "Vercel special case" / §5) | ❌ Don't directly expose the raw DB |
| Genuinely need public direct connection, and a tunnel is not possible | **Public + hardening** (§2.3) | ⚠️ Yes, but hardening is mandatory |
| Want to manage via browser/REST API | Deploy pgweb/Adminer/PostgREST (§5) | Goes over HTTP, bind a domain normally |

---

## 1. First, get this straight: a database is not a website

This is the root of all confusion, so it must be made clear up front:

- **A database speaks its own TCP protocol, not HTTP.** PostgreSQL uses the Postgres wire protocol (default port **5432**), MySQL/MariaDB use the MySQL protocol (**3306**), and the same goes for MongoDB (**27017**), Redis (**6379**), etc. None of these is HTTP.
- **Therefore, a form like `https://db.example.com/` cannot connect to a database.** A browser, or `curl https://...`, speaks HTTP; a database will not respond to HTTP requests. Opening a database in a browser via a URL is essentially a protocol mismatch.
- **Coolify's Traefik reverse proxy only handles HTTP(S).** It dispatches HTTP traffic to the various containers based on domain/path, but it **will not** forward traffic to a container that only speaks a database protocol. Binding a Traefik domain to a database container is meaningless — the reverse-proxy layer simply does not understand the byte stream on 5432.
- **A database client uses a connection string, not a URL:**
  ```
  postgresql://user:pass@host:5432/dbname
  mysql://user:pass@host:3306/dbname
  ```
  Here `host` **can be a domain** (see §3), but: there is no `https://` prefix, it **includes a port number**, and you connect with a database client (`psql` / DataGrip / Prisma / the `pg` library …), not a browser.

In one sentence: **needing an HTTP entry point (browser/REST) and needing a database connection are two completely different requirements.** First clarify which one the user actually wants (§5 handles the former).

---

## 2. Four access approaches (ordered by recommendation)

### 2.1 Internal direct connection (most recommended)

**Applies when: the app and the database are on the same Coolify host.** This is the vast majority of self-hosting scenarios.

- Use the **internal connection address** that Coolify provides; traffic travels inside the server's Docker network and **never leaves the server**.
- **No public port exposure, no domain, no `--is-public` needed.** The attack surface is zero.
- The internal hostname/connection details can be obtained from the database details:
  ```bash
  coolify database get <uuid> --format=json -s | jq .
  # -s / --show-sensitive is required to surface sensitive fields like the password and internal connection string
  # Field names follow the actual output (e.g. internal_db_url / the internal hostname is usually the container name or service name)
  ```
- Just fill this internal connection string directly into the app's environment variables. If the app and the db are in the same project/environment, you can also use Coolify's magic variables (see `deploy-patterns.md`) to reference the password and avoid hardcoding.

> This is the default path. Only look further down when the connecting client truly is not on this machine.

### 2.2 Tunnel (recommended when the connecting client can run a persistent tunnel client)

**Applies when: the app runs on a local dev machine / another VPS / any environment that can run a persistent background process, and needs to connect to a database on this machine.**
(**Not applicable to Vercel and other serverless/edge** — they cannot run a persistent sidecar; see "⚠️ Vercel / serverless special case" at the end of this section.)

Don't open `--is-public` to shove the port onto the public internet for this. Use an encrypted tunnel instead, so the connecting client accesses the database "as if it were on the internal network". **Note: a database is raw TCP, so both approaches below require the connecting client's side to run a persistent tunnel client process**:

- **Cloudflare Tunnel**: run `cloudflared` on the VPS where the database lives; on the connecting client's side, also run `cloudflared access tcp --hostname db.example.com --url localhost:5432`, which starts a local port forward into the tunnel, and the app connects to `localhost:5432`.
  - ⚠️ Raw TCP (the Postgres/MySQL protocol) **must** rely on this client-side `cloudflared access` proxy — the free Cloudflare Tunnel **does not** give raw TCP a public endpoint that "any client can connect to directly without a sidecar" (that is a capability only Enterprise's **Spectrum** has).
- **Tailscale / WireGuard**: add the VPS and the connecting client into the same private network (tailnet), install `tailscaled` on the connecting client, and connect to the database using the Tailscale internal IP (`100.x.x.x`). Zero public exposure, end-to-end encrypted.

Advantages: **public port scanners cannot see the database port**, traffic is encrypted, and credentials do not travel in plaintext over the public internet.

#### ⚠️ Vercel / serverless·edge special case (important, don't trip on this)

Both tunnel approaches above require the connecting client to **run a persistent sidecar process** (`cloudflared access` or `tailscaled`). Vercel's serverless/edge functions are **short-lived, stateless, and cannot run a persistent sidecar**, so **neither of these paths works for Vercel** — doing so results in functions that simply cannot connect to the database. The viable ways for Vercel to connect to a self-hosted database are:

1. **Put a layer in front of the database that speaks HTTP**, so Vercel goes over HTTPS instead of raw TCP — this is the first choice. The most direct self-hosted option is **PostgREST** (exposes your Coolify Postgres tables as an HTTPS REST API); you can also use an HTTP data proxy like **Prisma Accelerate**. See §5 for details.
   - ⚠️ **PgBouncer is not an HTTP layer**: it is a connection pooler for the Postgres protocol, still raw TCP on the outside, so Vercel serverless cannot connect to it either; it only solves connection-count problems for "runtimes that can open TCP connections" (a persistent Node service / another VPS).
2. **Public TLS endpoint + hardening** (§2.3). But Vercel serverless **has no fixed egress IP by default**, so the "restrict source IPs at the firewall" measure in §2.3 is basically unusable, unless you use Vercel's static egress IP (Secure Compute, Enterprise).
3. **Cloudflare Spectrum** (Enterprise) gives the raw database a true public TCP endpoint, letting Vercel connect directly without a sidecar — relatively expensive, evaluate as needed.

> In one sentence: **Vercel ≠ "a machine on the outside"**. An external machine that can run a sidecar uses a tunnel; serverless like Vercel must either go through an HTTP layer (§5) or through public hardening with a static IP — do not apply the raw TCP tunnel approach to it.

### 2.3 Public + hardening (acceptable, but requires caution)

**Only when `--is-public` is genuinely needed and the tunnel approaches are not viable.** Before executing, first follow the `--is-public` red-line procedure in `safety-rules.md`. Opening a public port means scanners worldwide can discover it, so you must do ALL of the following at the same time:

- **Strong password**: never use a default/weak password. A database port on the public internet will be brute-forced by automation within hours.
- **Restrict source IPs at the firewall**: only allow known client IPs (such as your static IP, your office network range), **not `0.0.0.0/0`**. Restrict the source for the port corresponding to `--public-port` on the VPS firewall (ufw / cloud-vendor security group).
- **Configure TLS for the database**: so the connection string can use `sslmode=require` (Postgres) / `--ssl` (MySQL), avoiding plaintext transmission (see §4 — Coolify usually does not enable TLS by default, you must configure it yourself).
- **Consider switching to a non-standard port**: change the public-facing port from 5432/3306 to something else, to reduce the noise of being hit by indiscriminate scans (this is noise reduction, not a security boundary — don't treat it as the primary defense).

### 2.4 ❌ Not recommended

A port open to the entire internet (`--is-public` + firewall `0.0.0.0/0`) + no TLS + weak password.
This is equivalent to hanging the database directly on the public internet for anyone to take, and is a classic cause of ransom/database-deletion incidents. The Agent must never proactively suggest this and must never default to it.

---

## 3. The correct way to connect to a database via a domain (clarifying "can I use postgresql.zilin.im")

Yes. A domain is just one way to write the `host`; the connection still uses TCP and does not go over HTTP. But there are two key points:

### 3.1 DNS: add an A record pointing to the VPS IP

Add an **A record** for the subdomain (e.g. `db.example.com`) pointing to the public IP of the VPS where Coolify runs.

### 3.2 ⚠️ Cloudflare must turn off the orange cloud (set it to DNS only / grey cloud)

**This is the most frequent pitfall, so be sure to remind the user prominently:**

> If the domain is hosted on Cloudflare, this record's proxy status must be **DNS only (grey cloud)**, and **must not be the orange cloud (Proxied)**.

Reason: Cloudflare's orange-cloud proxy **only forwards HTTP/HTTPS (80/443) traffic**, and it **blocks the database's TCP traffic** (5432/3306, etc.). With the orange cloud on, the connection times out or is refused — it behaves "as if the port weren't open", but in reality CF is dropping the non-HTTP traffic in the middle. Turn off the orange cloud (grey cloud), so DNS only does name resolution, traffic goes straight to your VPS, and the database protocol can get through.

(This also incidentally exposes the lesson of §1: the CF orange cloud = an HTTP reverse proxy, and just like Traefik it does not understand the database protocol.)

### 3.3 Connection string format

```
postgresql://user:pass@db.example.com:5432/mydb
```

- **No `https://` prefix** — it is not a website.
- **Includes a port number** (when exposed publicly, this is the port specified by `--public-port`).
- Connect with a database client, not a browser.
- For public connections it is strongly recommended to use TLS: `postgresql://user:pass@db.example.com:5432/mydb?sslmode=require` (on the condition that TLS is already configured on the database side, see §4).

---

## 4. ⚠️ TLS / encryption warning

**The database containers Coolify starts by default usually do not have SSL/TLS enabled.** This means:

- A plaintext connection over the public internet exposes the **account, password, and query data** entirely on the wire, and any intermediate hop can sniff it.
- **Do not assume the connection is encrypted.** Writing `sslmode=require` in the connection string tells the *client* to demand TLS — if the database has no certificate configured, the connection will **fail** (which is the safe outcome). But weaker modes like `sslmode=prefer` may silently fall back to plaintext, giving a false sense of security.

Therefore:

- **Internal direct connection (§2.1) / tunnel (§2.2) inherently avoid this problem** (the tunnel itself is encrypted, and the internal network never leaves the machine) — this is also one reason they are more recommended.
- **Public direct connection (§2.3) must explicitly configure TLS for the database**, otherwise it is plaintext on the wire. When suggesting the public approach, the Agent must proactively explain this risk to the user, and not assume there is encryption.

---

## 5. Put a layer in front of the database that speaks HTTP (HTTP entry point / serverless DB access)

Two situations land here: (a) what the user actually wants is to "view/edit data in the browser" or "read/write via an HTTP API"; (b) the connecting client is **Vercel or another serverless/edge** (the §2.2 special case), which cannot run a tunnel sidecar and has no fixed egress IP, and needs to go over HTTPS instead of raw TCP. The solution in both cases is to deploy, in front of the database, a **service that speaks HTTP**:

- **Browser management UI**: deploy a web management tool like **pgweb** (Postgres) or **Adminer** (multi-database). These are HTTP services that **connect to the database over the internal network** and serve HTTPS to the outside themselves.
- **REST API**: deploy **PostgREST** (automatically exposes Postgres tables as a REST API). It is likewise an HTTP service that connects to the database over the internal network.
- **Serverless DB access (Vercel, etc.)**: the first self-hosted choice is **PostgREST** (exposes the database as an HTTPS REST API); you can also use an **HTTP data proxy** (such as Prisma Accelerate), or a database that is itself hosted on **Neon / PlanetScale** with a built-in serverless HTTP driver — so the Vercel function makes a single HTTPS request rather than maintaining a long-lived raw TCP connection.
  - ⚠️ **PgBouncer is not an HTTP layer**: it is a connection pooler for the Postgres protocol, still raw TCP on the outside; Vercel serverless connecting to it is still raw TCP (can't connect). PgBouncer only solves connection-count problems for "runtimes that can open TCP connections" (a persistent Node service / another VPS) — don't use it as an HTTPS entry point for serverless.

Only these services may bind a Traefik domain normally, go over HTTPS, and enable the orange cloud — because what they speak is HTTP. The database itself still lives only on the internal network and does not expose a TCP port to the public internet.

> On Coolify, this kind of tool is usually deployed as a standalone app/service; for the deployment and operations flow, see `deploy-patterns.md` and the standard path in SKILL.md; this HTTP service layer connects to the database using the internal address from §2.1.
