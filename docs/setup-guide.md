# Setup Guide

Complete guide to installing, configuring, and integrating the guniweb-sap-mcp server with n8n.

## Prerequisites

- **Node.js** >= 22.18.0 (LTS recommended)
- **npm** (comes with Node.js)
- **SAP system access** -- one of:
  - Direct SAP S/4HANA (On-Premise or Cloud)
  - SAP BTP Integration Suite
  - SAP API Business Hub Sandbox (free for testing)

## Installation

### From npm

```bash
npm install -g guniweb-sap-mcp
```

### Without a global install

```bash
npx guniweb-sap-mcp --transport http --port 8808
```

### Without an SAP system

```bash
npx guniweb-sap-mcp --demo                # built-in mock S/4HANA with sample data (see --demo below)
```

The package ships a single bundled file (`dist/index.js`) plus type declarations; there is no build step on your side. The source code is not public — the compiled package is free to use under the ISC license (see [SUPPORT.md](https://github.com/guniweb/guniweb-sap-mcp/blob/main/SUPPORT.md) for how the project is run).

## Configuration

Configuration is done exclusively through environment variables. The server reads them on startup via `loadConfig()`.

### Environment Variables

| Variable               | Required          | Description                                                          |
|-----------------------|-------------------|----------------------------------------------------------------------|
| `SAP_BASE_URL`        | Yes               | SAP system base URL, e.g., `https://my-s4hana.example.com`          |
| `SAP_AUTH_TYPE`       | Yes               | Authentication type: `basic`, `oauth2`, or `apikey`                  |
| `SAP_CLIENT`          | Effectively yes   | SAP client number, appended to **every** request. Without it a client-dependent Gateway answers `401 "Anmeldung fehlgeschlagen"` — which looks like a wrong password but is not one. The server warns at startup when it is unset |
| `SAP_CONNECTION_NAME` | No                | Connection name for logging (default: `default`)                     |
| `SAP_USERNAME`        | For `basic` auth  | SAP username                                                         |
| `SAP_PASSWORD`        | For `basic` auth  | SAP password                                                         |
| `SAP_CLIENT_ID`       | For `oauth2` auth | OAuth 2.0 client ID                                                  |
| `SAP_CLIENT_SECRET`   | For `oauth2` auth | OAuth 2.0 client secret                                              |
| `SAP_TOKEN_SERVICE_URL` | For `oauth2` auth | Token endpoint URL (XSUAA), e.g., `https://tenant.authentication.eu10.hana.ondemand.com/oauth/token` |
| `SAP_API_KEY`         | For `apikey` auth | SAP API Business Hub API key                                         |
| `SAP_HTTP_TIMEOUT_MS` | No                | Timeout for a **single** outbound SAP request. Default `30000`       |
| `SAP_MCP_TOOL_TIMEOUT` | No               | Time budget for a **whole tool call** in seconds. Default `30`, `0` disables. Same as `--tool-timeout` |
| `SAP_TLS_VERIFY`      | No                | `false` disables certificate validation. Every tool result then carries a warning. Prefer fixing the chain via `SAP_CA_CERT` |
| `SAP_CA_CERT`         | No                | Path to the root CA that signs your SAP certificate. Mirrored into `NODE_EXTRA_CA_CERTS` — the documented way past a corporate PKI |
| `SAP_CACHE_DIR`       | Recommended       | Directory for the catalog and metadata caches. Without it every restart refetches both from SAP |
| `SAP_CONCURRENCY`     | No                | Max simultaneous SAP requests where several are unavoidable. Default `5`   |
| `SAP_MCP_ALLOW_WRITE` | For writing       | `true` enables the write tools. Since 0.2.2 the server is **read-only by default** |
| `SAP_JWT_ISSUER`      | For principal propagation | Issuer whose JWKS verifies incoming user tokens. Without it tokens are decoded but not verified |

### Authentication Types

#### Basic Auth (Direct S/4HANA)

For direct connections to SAP S/4HANA On-Premise or Cloud systems:

```bash
export SAP_BASE_URL=https://my-s4hana.example.com
export SAP_AUTH_TYPE=basic
export SAP_USERNAME=SAP_USER
export SAP_PASSWORD=SecurePassword123
export SAP_CLIENT=100
```

The server handles CSRF token fetching automatically.

#### Personal SAP login per request (`user-basic`)

For teams where every person should act in SAP **as themselves** — SAP authorizations, change documents and audit trail on the real user, no shared technical account. The destination knows system and client only; SAP user and password arrive with each request from the caller (in n8n: the credential of the [GuniWeb SAP node](https://github.com/guniweb/n8n-nodes-guniweb-sap), fields *SAP User* / *SAP Password*):

```bash
export SAP_BASE_URL=https://my-s4hana.example.com
export SAP_AUTH_TYPE=user-basic
export SAP_CLIENT=100
guniweb-sap-mcp --transport http --port 8808 --api-key <key>      # or tokens in destinations.json
```

or as a destination: `{ "prod-s4": { "baseUrl": "https://…", "authType": "user-basic", "sapClient": "100" } }`. The caller sends `X-SAP-Username` and `X-SAP-Password` (or `X-SAP-Authorization: Basic <base64 user:pass>`) next to the Bearer token; the token still authenticates at the MCP server, selects the destination and applies its policy. Rules: without a personal login the request is answered `401` with a hint — there is **no fallback** to a technical user; a personal login sent to a destination that runs on a technical user is answered `400` (not silently ignored); passwords are never logged, the SAP user is (each tool log line carries `sapUser`); catalog and metadata caches are kept per user and never written to disk. HTTP/SSE transport only — stdio has no header to carry the login. Run it behind TLS (or inside the Docker network) like any other credential.

#### OAuth 2.0 (BTP Integration Suite)

For connections via SAP BTP Integration Suite using OAuth 2.0 Client Credentials flow:

```bash
export SAP_BASE_URL=https://my-tenant.it-cpi-rt.cfapps.eu10.hana.ondemand.com
export SAP_AUTH_TYPE=oauth2
export SAP_CLIENT_ID=sb-clone-abc123!b456|it-rt-my-tenant!b789
export SAP_CLIENT_SECRET=VerySecretValue123456
export SAP_TOKEN_SERVICE_URL=https://my-tenant.authentication.eu10.hana.ondemand.com/oauth/token
```

The server handles token retrieval, caching, and automatic refresh.

#### API Key (SAP Sandbox)

For the SAP API Business Hub Sandbox environment (great for development and testing):

```bash
export SAP_BASE_URL=https://sandbox.api.sap.com
export SAP_AUTH_TYPE=apikey
export SAP_API_KEY=YourApiKeyFromSAPAPIBusinessHub
```

Get your API key from [SAP Business Accelerator Hub](https://api.sap.com/) by signing up and navigating to your profile settings.

### CLI Options

All server behavior can be configured via command-line flags:

| Flag | Default | Description |
|------|---------|-------------|
| `--demo` | off | Start against a built-in in-memory mock S/4HANA (OData V2, sample data) instead of a real system — no `SAP_*` needed, also `SAP_MCP_DEMO=true`. Combine with `--allow-write` to try writes. Refuses to start together with `SAP_BASE_URL`/`--destinations`. Sample data only, nothing leaves the machine |
| `--transport <mode>` | `stdio` | Transport mode: `stdio`, `http`, or `sse` |
| `--port <number>` | `8808` | HTTP/SSE listening port |
| `--api-key <key>` | none | API key for HTTP transport authentication (Bearer token) |
| `--destinations <path>` | none | Named SAP connections from a `destinations.json` (also `SAP_MCP_DESTINATIONS`). See [Named destinations](#named-destinations-destinationsjson) |
| `--expose <patterns>` | all | Comma-separated glob patterns for entity set filtering |
| `--webhook-port <number>` | none | Standalone IDoc webhook port (stdio mode only) |
| `--sndpor <value>` | none | IDoc sender port |
| `--sndprt <value>` | none | IDoc sender partner type |
| `--sndprn <value>` | none | IDoc sender partner number |
| `--rcvpor <value>` | none | IDoc receiver port |
| `--rcvprt <value>` | none | IDoc receiver partner type |
| `--rcvprn <value>` | none | IDoc receiver partner number |

#### `--expose` (Selective Entity Set Registration)

By default, all entity sets discovered from SAP services are available. Use `--expose` to restrict which entity sets the LLM can see and interact with:

```bash
# Expose only specific entity sets
guniweb-sap-mcp --expose 'A_BusinessPartner,A_SalesOrder'

# Use glob patterns with wildcards
guniweb-sap-mcp --expose 'A_BusinessPartner*,A_SalesOrder*'

# Combine specific names and patterns
guniweb-sap-mcp --expose 'A_BusinessPartner,A_Customer,A_SalesOrder*'
```

**How it works:**
- Entity sets are filtered in `sap_list_services`, `sap_get_metadata`, and all CRUD operations
- Uses [minimatch](https://github.com/isaacs/minimatch) glob pattern matching
- Without `--expose`, all entity sets are accessible (default behavior)
- Useful for restricting the LLM to only the entity sets relevant to a specific workflow

**Pattern examples:**
| Pattern                     | Matches                                                     |
|----------------------------|-------------------------------------------------------------|
| `A_BusinessPartner`        | Only `A_BusinessPartner` (exact match)                      |
| `A_BusinessPartner*`       | `A_BusinessPartner`, `A_BusinessPartnerAddress`, `A_BusinessPartnerBank`, etc. |
| `A_SalesOrder*`            | `A_SalesOrder`, `A_SalesOrderItem`, `A_SalesOrderScheduleLine`, etc. |
| `*Partner*`                | Any entity set containing "Partner"                         |

### Named destinations (`destinations.json`)

`SAP_*` variables configure a single SAP system. For several systems behind one server, use a `destinations.json`:

```bash
guniweb-sap-mcp --transport http --port 8808 --destinations /config/destinations.json
```

```json
{
  "version": 1,
  "destinations": {
    "default": { "baseUrl": "https://s4prod.example.com", "authType": "basic",
                 "username": "MCP_USER", "password": "${S4PROD_PASSWORD}", "sapClient": "100" },
    "s4test":  { "baseUrl": "https://s4test.example.com", "authType": "basic",
                 "username": "MCP_USER", "password": "${S4TEST_PASSWORD}", "sapClient": "200" },
    "sandbox": { "baseUrl": "https://sandbox.api.sap.com/s4hanacloud", "authType": "apikey",
                 "apiKey": "${SAP_SANDBOX_KEY}" }
  }
}
```

| Rule | Detail |
|------|--------|
| Entry fields | Same as the `SAP_*` variables: `baseUrl`, `authType` + its credentials (all eight types, incl. `user-basic`), `sapClient`. The key is the destination name (`[A-Za-z0-9][A-Za-z0-9_.-]{0,63}`) |
| `${VARIABLE}` | Resolved from the environment when the file is loaded. Unresolvable → file invalid (named in the error). Only `${UPPER_CASE}` counts; `$VAR` stays text |
| Hot reload | Directory watch + 1 s stat polling as safety net; `SIGHUP` forces a reload. Effective on the next request (HTTP/SSE). In stdio mode the file is read once at start |
| Fail-safe | An invalid file at startup aborts with the errors listed. An invalid file **at runtime** is logged as a warning; the last valid configuration stays in force. A file that does **not exist yet** is not an error as long as `SAP_*` is set: the server starts with `default`, warns, and picks the file up as soon as it appears (so `SAP_MCP_DESTINATIONS` can be configured before the first `destinations add`) |
| `SAP_*` + file | If `SAP_BASE_URL` is set, the environment becomes destination `default` — unless the file has its own `default` (then the file wins, with a startup warning) |
| Which destination answers | With a token: the token's destination. Without: `default` if present, else the only one. Several destinations without `default` and without tokens abort at startup (API-key/open requests answer `503` if it happens through a reload) |
| `tokens` | `[{ "hash": "sha256:…", "destination": "<name>", "label"?, "policy"?, "revoked"? }]`. Plain token format `gsm_<destination>_<random>`; only the hash is stored. With ≥ 1 token every request needs a valid Bearer (`401` otherwise); `--api-key` still works alongside and serves `default`. Constant-time lookup, `revoked` effective on the next request, `429` + `Retry-After` after 10 failures/minute per client address. Tokens are never logged |
| `policy` per token | `{ "readOnly"?: boolean, "tiers"?: ["core"\|"odata"\|"idoc"\|"rfc", …] }`. Only restrictive: `readOnly: true` hides write tools for this token regardless of `--allow-write`; `tiers` is a ceiling on top of `--tiers`/`sap_enable_tools`. Applied per request (`tools/list` reflects it) |
| CLI | `guniweb-sap-mcp destinations list\|add\|remove` and `tokens list\|issue\|revoke` (`--destinations <path>` or `SAP_MCP_DESTINATIONS`). Validates like the server before writing, writes atomically (temp file + rename, new files `0600`), the running server reloads on the next request. `tokens issue` prints the plain token once on stdout — capture with `TOKEN=$(…)`. `destinations add --from-env` copies the `SAP_*` environment (migration path); `--set field=value` for any auth type; `--allow-missing-env` when a `${VAR}` only exists inside the container. In Docker: `docker compose exec sap-mcp guniweb-sap-mcp tokens issue <dest>` — the config directory must be writable by the container user (`node`) for `add`/`issue`/`revoke` |
| Docker | Mount the directory (`./sap-mcp-config:/config` — read-write if you want to run the CLI inside the container, `:ro` otherwise) and pass `SAP_MCP_DESTINATIONS=/config/destinations.json`; keep secrets in `env_file`/Docker secrets and reference them via `${...}` |
| Admin API | `--admin-token <secret>` / `SAP_MCP_ADMIN_TOKEN` (≥ 16 characters; HTTP/SSE transport with `--destinations`) exposes the CLI operations under `/admin`: `GET /admin/destinations`, `PUT /admin/destinations/:name` (JSON body = entry fields; `?allowMissingEnv=true`; 201 created / 200 replaced), `DELETE /admin/destinations/:name[?force=true]`, `GET /admin/tokens`, `POST /admin/tokens` (`{ destination, label?, readOnly?, tiers? }` → plain token **once** in the response, 201), `DELETE /admin/tokens/:ref` (label or hash prefix). Auth: `Authorization: Bearer <admin secret>` — the admin secret opens **only** `/admin`, n8n tokens and `--api-key` open **only** `/mcp`; `429` after 10 failures/minute per address; without the flag `/admin/*` is `404`. Every write validates, writes atomically and reloads the running configuration before answering (`reloaded: true`, otherwise `reloaded: false` + `reloadErrors`, last valid config stays). With `--admin-token` the server also starts when the file does not exist yet and no `SAP_*` is set (`/mcp` → `503` until the first destination/token exists) — the bootstrap path for `docker run … -e SAP_MCP_ADMIN_TOKEN=…`. Responses are `Cache-Control: no-store`; changes are logged with action/target/client address, never the token or the secret |

## Transport Modes

The server supports three transport modes for communicating with MCP clients.

### stdio (default)

Standard I/O transport -- the server reads from stdin and writes to stdout. This is the default MCP transport used when running the server as a subprocess.

```bash
guniweb-sap-mcp
```

Use this mode with the n8n MCP Client node in **command mode**. The n8n node spawns the server process and communicates over stdio.

### HTTP (Streamable HTTP)

HTTP-based transport using the MCP Streamable HTTP protocol. The server exposes an endpoint at `/mcp`.

```bash
guniweb-sap-mcp --transport http --port 8808
```

Use this mode with the n8n MCP Client node in **URL mode**. Point the node to:

```
http://localhost:8808/mcp
```

This is the recommended transport for Docker deployments and remote server setups.

### SSE (Server-Sent Events)

Legacy SSE transport. The server exposes an SSE endpoint at `/sse` and a message endpoint at `/message`.

```bash
guniweb-sap-mcp --transport sse --port 8808
```

SSE is supported for backward compatibility. Prefer HTTP (Streamable HTTP) for new deployments.

## Running the Server

### stdio (default)

```bash
# Using the installed binary
guniweb-sap-mcp

# Using npx (without global install)
npx guniweb-sap-mcp

# From source (development)
npm run dev
```

The server communicates via stdio (stdin/stdout) using the MCP protocol. Log output goes to stderr so it does not interfere with the protocol.

### HTTP with API key authentication

```bash
guniweb-sap-mcp --transport http --port 8808 --api-key mysecretkey
```

### SSE transport

```bash
guniweb-sap-mcp --transport sse
```

### With entity filtering

```bash
guniweb-sap-mcp --transport http --expose 'A_BusinessPartner*,A_SalesOrder*'
```

### With IDoc partner defaults

```bash
guniweb-sap-mcp --transport http --port 8808 \
  --sndpor MYMCPPORT --sndprt LS --sndprn MCPSERVER \
  --rcvpor SAPPORT --rcvprt LS --rcvprn SAPSYSTEM
```

## n8n Integration

The guniweb-sap-mcp server can connect to n8n via two methods: command (stdio) or URL (HTTP).

### Method 1: Command Mode (stdio)

In the n8n MCP Client node configuration:

- **Connection Type:** Command
- **Command:** `guniweb-sap-mcp`
  Or with the full path: `node /path/to/dist/index.js`
- **Arguments** (optional): `--expose 'A_BusinessPartner*'`
- **Environment Variables:** Add the SAP connection variables directly in the node's environment configuration:
  ```
  SAP_BASE_URL=https://my-s4hana.example.com
  SAP_AUTH_TYPE=basic
  SAP_USERNAME=SAP_USER
  SAP_PASSWORD=SecurePassword123
  SAP_CLIENT=100
  ```

### Method 2: URL Mode (HTTP)

Start the server with HTTP transport:

```bash
guniweb-sap-mcp --transport http --port 8808
```

In the n8n MCP Client node configuration:

- **Connection Type:** URL
- **URL:** `http://localhost:8808/mcp`
  In Docker: `http://sap-mcp:8808/mcp`
- **Authentication:** If using `--api-key`, configure a Bearer token header with the API key value

### Using SAP Tools in Your Workflow

Once connected, the MCP Client node exposes all SAP tools to the AI agent in n8n. The agent can:

1. **Discover** available SAP services and entity sets
2. **Inspect** metadata to understand data models
3. **Query** SAP data with filters, sorting, and pagination
4. **Create, update, and delete** SAP entities
5. **Call function imports** and actions
6. **Send and receive IDocs** for asynchronous document exchange

### Example Workflow

A typical n8n workflow using the SAP MCP server:

1. **Trigger** (e.g., webhook, schedule, or manual)
2. **AI Agent** node with the MCP Client connected
3. The agent uses the progressive discovery pattern:
   - `sap_list_services` to find entity sets
   - `sap_get_metadata` to understand the data model
   - `sap_query` or `sap_read` to fetch data
   - `sap_create` / `sap_update` to modify data

## Docker Deployment

### The image

```
ghcr.io/guniweb/guniweb-sap-mcp:<version>
```

Built **from the published npm package**, not from a separate build path — the container runs the same artifact `npm install` would fetch, so the two cannot drift apart. Inside the image, HTTP transport on port 8808 is the default (`SAP_MCP_TRANSPORT` / `SAP_MCP_PORT`), it runs as the non-root user `node`, carries a health check against `/healthz`, and is published for `linux/amd64` and `linux/arm64` with build provenance and an SBOM.

```bash
# A first look — mock S/4HANA inside the container, no SAP system needed
docker run --rm -p 8808:8808 -e SAP_MCP_DEMO=true ghcr.io/guniweb/guniweb-sap-mcp:latest

# Against a real system; anything after the image name is passed to the server
docker run -d --name sap-mcp -p 8808:8808 --env-file .env \
  ghcr.io/guniweb/guniweb-sap-mcp:<version> --allow-write
```

Pin the version in production. `:latest` is right for trying things out, but an unattended pull that swaps the server underneath a running workflow is not a debugging session anyone wants.

**RFC/BAPI is not in the image.** That path needs the SAP NW RFC SDK, which SAP licenses to customers only, so it cannot ship in a public image. OData V2/V4 and IDoc over HTTP/XML are complete. For RFC, install the SDK on the host and run the server from npm (see "Setup for SAP ECC" in the README).

### Quick Start with Compose

A Docker Compose file is provided at the project root (`docker-compose.yml`) for running n8n with guniweb-sap-mcp as an HTTP sidecar. n8n waits for the server's health check before it starts.

1. Copy `docker-compose.yml` to your project directory
2. Create a `.env` file with your SAP credentials:

```bash
SAP_BASE_URL=https://my-s4hana.example.com
SAP_AUTH_TYPE=basic
SAP_USERNAME=SAP_USER
SAP_PASSWORD=SecurePassword123
SAP_CLIENT=100
```

3. Start the services:

```bash
docker compose up -d
```

4. Open n8n at `http://localhost:5678`

### Configuring n8n MCP Client in Docker

In the n8n MCP Client node, use **URL mode** with:

- **URL:** `http://sap-mcp:8808/mcp`

The `sap-mcp` hostname resolves within the Docker network. HTTP transport is required for Docker deployments -- stdio cannot be used across containers.

### Using env_file

Instead of inline environment variables in `docker-compose.yml`, you can use an `.env` file. Edit `docker-compose.yml` to uncomment the `env_file` option and remove the `environment` block for the `sap-mcp` service.

### Container settings at a glance

| Setting | Default in the image | Notes |
|---|---|---|
| `SAP_MCP_TRANSPORT` | `http` | Same as `--transport`. A flag on the command line wins |
| `SAP_MCP_PORT` | `8808` | Same as `--port`. Also what the container's health check probes |
| User | `node` (uid 1000) | A mounted config directory must be writable by this user if you want to run `destinations`/`tokens` inside the container |
| Health check | `GET /healthz` every 30 s | Skipped when `SAP_MCP_TRANSPORT=stdio`, where there is no endpoint to probe |
| Write tools | off | Add `--allow-write` after the image name |

## Security

### API Key Authentication

When running with HTTP or SSE transport, you can secure the server with an API key:

```bash
guniweb-sap-mcp --transport http --port 8808 --api-key your-secret-key
```

Clients must include the API key as a Bearer token in the `Authorization` header:

```
Authorization: Bearer your-secret-key
```

### Health Check

The `/healthz` endpoint is always accessible without authentication. It returns `{"status": "ok"}` and can be used for container health checks and load balancer probes.

### Open Mode

Without `--api-key`, the server runs without authentication. This is suitable for:
- Docker internal networks where the port is not exposed to the host
- Development and testing environments
- Environments where authentication is handled by a reverse proxy

## Upgrading to 0.2.2

**The server is read-only by default.** `sap_create`, `sap_update`, `sap_delete`, `sap_function` and `sap_idoc_send` no longer appear in `tools/list` until you pass `--allow-write` (or set `SAP_MCP_ALLOW_WRITE=true`).

> This is a breaking change in a patch-level version. It is deliberate: the project is pre-1.0, and shipping a safe default sooner was judged more valuable than the version-number convention.

If your workflows write to SAP, add the flag:

```bash
guniweb-sap-mcp --transport http --port 8808 --allow-write
```

`--read-only` and `SAP_MCP_READ_ONLY` remain accepted, so existing start commands do not break — they simply describe what is now the default.

The reasoning is worth stating plainly: the first contact between an agent and a production ERP should not be able to change anything. Whoever wants to write says so.

## Troubleshooting

### Diagnosing from outside the server

These one-liners carried the original production diagnosis and are worth keeping at hand when the server itself cannot start.

```bash
# Does the container reach SAP, and are credentials and client correct?
docker compose exec sap-mcp node -e 'const e=process.env;fetch(e.SAP_BASE_URL+"/sap/opu/odata/iwfnd/catalogservice;v=2/ServiceCollection?$format=json&sap-client="+e.SAP_CLIENT,{headers:{Authorization:"Basic "+Buffer.from(e.SAP_USERNAME+":"+e.SAP_PASSWORD).toString("base64")}}).then(r=>console.log("HTTP",r.status)).catch(x=>console.log("FAILED",x.cause?.code||x.message))'

# Who issued the server certificate, and does the server send the chain?
openssl s_client -connect <host>:<port> -showcerts </dev/null 2>&1 | grep -E "^(depth|verify|subject|issuer)"

# Where is the root CA? An Active Directory PKI links it in the intermediate certificate.
openssl x509 -in subca.pem -noout -ext authorityInfoAccess
```

The first command is the fastest way to separate "the container cannot reach SAP at all" from "the MCP server has a problem". Note the `sap-client` in the URL — leave it out and the Gateway answers 401.

### Start here: `test-connection`

Since v0.4.0 the `test-connection` tool walks the whole chain and names the **first** failing stage: DNS → TLS (including the certificate chain) → authentication → client (Mandant) → catalog. That answer replaces most of the guesswork below — a bare `401` no longer leaves you choosing between certificate, user and client.

The same five stages are logged once at startup, so `docker compose logs sap-mcp` shows the state of the connection without calling anything.

Every failure carries a `guidance` field with the next action, and a `correlationId`. A `grep` on that id in the server log shows every SAP request the call produced.

**For log monitoring:** `level: 50` (error) now means something is genuinely wrong. Expected non-2xx responses — the `404`s from catalog path probing, and the V4 catalog attempt on systems without one — are logged at `info` with `"expected": true`. Measured on a production system, that false alarm used to be the only error-level entry across 96 hours of runtime, which made alerting on it useless.

### CSRF Token Errors

**Symptom:** `403 Forbidden` or "CSRF token validation failed" on write operations (create, update, delete).

**Cause:** SAP requires a valid CSRF token for all modifying requests.

**Solution:** The server handles CSRF token fetching automatically. If you see this error:
- Verify the `SAP_BASE_URL` is correct and reachable
- Ensure the SAP user has the necessary authorizations
- Check if a proxy or firewall is stripping the `x-csrf-token` header

### Connection Timeouts

**Symptom:** `ECONNREFUSED` or `ETIMEDOUT` errors, or a tool answering with `truncated: true`.

**Solution:**
- Run `test-connection` — it distinguishes "host not resolvable" from "port closed" from "TLS chain incomplete"
- Verify the SAP system is reachable from the machine running the MCP server
- Check network/firewall rules
- For BTP: ensure the Integration Suite is provisioned and the URL is correct

**On `truncated: true`:** the tool time budget expired (default 30 s). Narrow the request (`top`/`skip`, `filter`, `search`) rather than raising the budget. If you do raise it via `--tool-timeout`, keep it **below the smallest client limit** in your setup — measured in production: Cloudflare aborts at 100 s, n8n's MCP client transport at 300 s. A budget above those never takes effect, because the client gives up first.

### Cold Start After Every Restart

**Symptom:** The first tool call after a restart takes tens of seconds, or times out; the log shows the catalog being fetched again.

**Solution:** Set `--cache-dir` (or `SAP_CACHE_DIR`) to a writable directory — in Docker, a mounted volume. The catalog cache (TTL 30 min) and the metadata cache (TTL 24 h) then survive restarts.

This matters more than it sounds: n8n evicts its own MCP client entry on a transport error, so the next attempt rebuilds the connection. With purely in-memory caches, discovery starts from scratch on **every** failed attempt — two volatile caches in a row turn one hiccup into a full cold start.

```yaml
services:
  sap-mcp:
    environment:
      SAP_CACHE_DIR: /var/cache/sap-mcp
    volumes:
      - sap-mcp-cache:/var/cache/sap-mcp
volumes:
  sap-mcp-cache:
```

A corrupt cache file is discarded with a warning, never repaired — it is reconstructible from SAP at any time.

### Certificate Chain Incomplete

**Symptom:** `UNABLE_TO_GET_ISSUER_CERT_LOCALLY`, or `test-connection` reporting the `tls` stage as failed.

**Solution:** The server does not trust the issuing CA. The diagnosis names the issuer — supply its root certificate:

```bash
export SAP_CA_CERT=/etc/ssl/certs/corporate-root-ca.pem
```

(`SAP_CA_CERT` is mirrored into `NODE_EXTRA_CA_CERTS` at startup; setting the latter directly still works.)

To find the chain yourself:

```bash
# Who issued the server certificate, and does the server send the chain?
openssl s_client -connect <host>:<port> -showcerts </dev/null 2>&1 | grep -E "^(depth|verify|subject|issuer)"

# Where is the root CA? An Active Directory PKI links it in the intermediate certificate.
openssl x509 -in subca.pem -noout -ext authorityInfoAccess
```

`SAP_TLS_VERIFY=false` is **not** a fix — it disables the check. Once set it tends to stay for years, and nothing in the running system reminds you of it.

### Authentication Failures

**Symptom:** `401 Unauthorized` or `403 Forbidden` on all requests.

**Solution:**
- **First: is `SAP_CLIENT` set?** Without it a client-dependent Gateway answers `401 "Anmeldung fehlgeschlagen"`, not a client-related message. `test-connection` attributes this case to the `client` stage rather than to `auth`
- **On `403` with `/IWFND/MED/170`:** the service is not registered — activate it in `/IWFND/MAINT_SERVICE`. This is not an authorization problem, so PFCG and SU53 lead nowhere
- **Basic Auth:** Verify username/password, check user is not locked in SAP (SU01)
- **OAuth 2.0:** Verify client ID, client secret, and token service URL. Check that the service instance is bound correctly
- **API Key:** Verify the key is valid and not expired. Get a new key from [api.sap.com](https://api.sap.com/)
- Check `SAP_AUTH_TYPE` matches the credentials provided

### Entity Set Not Found

**Symptom:** Error "Entity set 'X' is not exposed" when using CRUD tools.

**Solution:**
- If using `--expose`, verify the pattern includes the entity set you need
- Run `sap_list_services` first to see which entity sets are available
- Without `--expose`, all entity sets are accessible by default

### Invalid Configuration on Startup

**Symptom:** "Invalid SAP connection configuration" error on server start.

**Solution:** The server validates all configuration on startup using Zod schemas. Check:
- `SAP_BASE_URL` is a valid URL (includes `https://`)
- `SAP_AUTH_TYPE` is one of: `basic`, `oauth2`, `apikey`
- All required variables for the chosen auth type are set
- No trailing whitespace or quotes in environment variable values
