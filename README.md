# GuniWeb SAP S/4HANA & ECC MCP Server

Designed for n8n, usable from any MCP host. Free to use — built and maintained by [GuniWeb](https://guniweb.de).

Connect n8n workflows to SAP S/4HANA and ECC via OData V2, V4, IDocs, and RFC/BAPI using the Model Context Protocol (MCP). Made for **AI-assisted, human-governed workflows**: the workflow author decides which SAP APIs are called and in what order; the LLM extracts, maps and fills in parameters. Writes are off by default and switched on explicitly, per server and per token.

```mermaid
graph LR
    n8n["n8n workflow<br/>AI-assisted, human-governed"] -->|MCP Protocol| MCP["guniweb-sap-mcp<br/>22 Tools &bull; 7 Auth Types"]
    MCP -->|"OData V2/V4<br/>IDoc XML<br/>RFC/BAPI"| SAP["SAP S/4HANA & ECC"]
    MCP -->|"OAuth2 / JWT"| BTP["SAP BTP"]
    BTP --> SAP

    style n8n fill:#4a90d9,color:#fff,stroke:#3a7bc8
    style MCP fill:#2d2d2d,color:#fff,stroke:#555
    style SAP fill:#1a6fb5,color:#fff,stroke:#0f5a9d
    style BTP fill:#e8a317,color:#fff,stroke:#c88d14
```

## Features

### OData & IDoc
- **OData V2 + V4 CRUD** -- Read, query, create, update, delete with auto version detection
- **Deep Insert** -- Create parent + child entities in one request
- **Function Imports (V2) & Actions/Functions (V4)** -- Trigger SAP business logic
- **Batch Operations** -- Multiple operations in a single `$batch` request
- **NL-to-OData Query** -- Natural language queries converted to structured OData filters
- **IDoc Send & Receive** -- HTTP/XML based, no RFC dependency

### Discovery & Intelligence
- **Service Discovery** -- Auto-discover OData services with 16 business domain categories
- **Progressive Metadata** -- Service catalog -> entity sets -> properties -> query
- **Smart Query Routing** -- Domain-based routing resources for LLM tool selection
- **Decision-Tree Tool Descriptions** -- "When to use / When NOT to use" blocks guide LLMs

### Governed tool visibility
- **4-Tier Tool Registry** -- Core / OData / IDoc / RFC tiers with on-demand activation
- **`sap_enable_tools`** -- LLMs activate additional tool tiers at runtime, within the limits you set
- **Read-only by default (since 0.2.2)** -- write tools require `--allow-write`
- **Per-token policy (0.3.0)** -- `readOnly` and tool-tier ceilings per Bearer token, only ever more restrictive
- **IDoc / RFC auto-disable** -- tools hidden when the corresponding configuration is missing
- **MCP Annotations** -- readOnlyHint, destructiveHint, idempotentHint on all 22 tools

### Authentication (7 Types)

```mermaid
graph TB
    subgraph Technical["Technical User Auth"]
        basic["basic<br/><i>Direct S/4HANA</i>"]
        oauth2["oauth2<br/><i>BTP Client Credentials</i>"]
        apikey["apikey<br/><i>Sandbox / Testing</i>"]
    end
    subgraph Enterprise["Enterprise Auth (OIDC)"]
        ias["ias<br/><i>SAP IAS Token</i>"]
        xsuaa["xsuaa<br/><i>SAP XSUAA Token</i>"]
    end
    subgraph Principal["Principal Propagation<br/><i>End-user identity forwarded to SAP</i>"]
        btp["btp-principal<br/><i>JWT Bearer Exchange<br/>via Destination Service</i>"]
        saml["saml-bearer<br/><i>SAML 2.0 Assertion<br/>+ RSA-SHA256 Signing</i>"]
    end

    style Technical fill:#2a5f8f,color:#fff,stroke:#1a4f7f
    style Enterprise fill:#5b8c5a,color:#fff,stroke:#4b7c4a
    style Principal fill:#8b5e3c,color:#fff,stroke:#7b4e2c
```

### Infrastructure
- **Three Transport Modes** -- stdio, Streamable HTTP, SSE
- **Named destinations (0.3.0)** -- one server, several SAP systems; a Bearer token per n8n credential selects the system and its permissions. Static API key still supported
- **Docker Ready** -- Docker Compose for n8n + SAP MCP sidecar
- **Zero telemetry** -- the server talks to the SAP/BTP endpoints you configure and to nothing else. No usage statistics, no update checks, no crash reports
- **1267 Tests** -- Unit, integration, E2E with CI/CD via GitHub Actions

## Quick Start

### 1. Install

```bash
npm install -g guniweb-sap-mcp
```

### 2. Configure

```bash
export SAP_BASE_URL=https://your-sap-system.example.com
export SAP_AUTH_TYPE=basic
export SAP_USERNAME=your-user
export SAP_PASSWORD=your-password
export SAP_CLIENT=100   # do not omit: without it a client-dependent Gateway
                        # answers 401 "Anmeldung fehlgeschlagen", which looks
                        # like a wrong password but is not one
```

### 3. Run

```bash
# stdio (default) -- for n8n MCP Client in command mode
guniweb-sap-mcp

# HTTP -- for n8n MCP Client in URL mode or Docker
guniweb-sap-mcp --transport http --port 8808

# With tool tier control
guniweb-sap-mcp --transport http --port 8808 --tiers core,odata
guniweb-sap-mcp --transport http --port 8808 --allow-write   # writes are OFF by default

# Production: authenticate the MCP endpoint AND the inbound IDoc webhook
guniweb-sap-mcp --transport http --port 8808 --api-key <mcp-key> --webhook-secret <idoc-secret>
```

#### Production hardening

| Variable / Flag               | Default        | Description                                                                                     |
|-------------------------------|----------------|-------------------------------------------------------------------------------------------------|
| `--tool-timeout` / `SAP_MCP_TOOL_TIMEOUT` | `30` (seconds) | Time budget for a **whole tool call**, however many SAP requests it makes. On expiry the client gets a valid MCP response with `truncated: true` and a plain-language reason — never a hanging connection. Paginated reads return the pages fetched so far. `0` disables the budget (logged as a warning at startup) |
| `SAP_HTTP_TIMEOUT_MS`         | `30000`        | Timeout for a **single** outbound SAP request (ms). Hanging gateways fail fast with a structured `TIMEOUT` error instead of stalling the n8n agent. Capped by whatever is left of the tool budget above |
| `--cache-dir` / `SAP_CACHE_DIR` | _(unset = in-memory only)_ | Persist the catalog and metadata caches to disk so a restart does not refetch them. Without it every restart re-reads the full catalog — on a system with 1222 services that is the cold start that breaks client timeouts. n8n evicts its own client entry on a transport error, so restarts are not rare |
| `SAP_CA_CERT` | _(unset)_ | Path to the root CA that signs your SAP certificate — the documented way past a corporate PKI. Mirrored into `NODE_EXTRA_CA_CERTS`. Prefer this over `SAP_TLS_VERIFY=false`, which disables the check rather than solving it |
| `--concurrency` / `SAP_CONCURRENCY` | `5` | Upper bound on simultaneous SAP requests where several are unavoidable |
| `--allow-write` / `SAP_MCP_ALLOW_WRITE` | _(unset = read-only)_ | **Since 0.2.2 the server is read-only by default.** `sap_create`, `sap_update`, `sap_delete`, `sap_function` and `sap_idoc_send` are not registered at all until you set this — a tool an agent cannot see is a tool it cannot call by accident. `--read-only` is still accepted and now simply describes the default |
| `SAP_JWT_ISSUER` | _(unset = no verification)_ | Issuer whose JWKS is used to verify incoming user tokens. Without it tokens are only decoded, and the resulting identity is marked `verified: false` — safe to forward to SAP (SAP verifies itself), but not safe to base a local decision on. With it, a token failing verification is rejected with `401` rather than silently downgraded to the technical user |
| `SAP_WEBHOOK_SECRET` / `--webhook-secret` | _(unset = open + startup warning)_ | Shared secret for the inbound IDoc webhook. Accepts `Authorization: Bearer <secret>` or HTTP Basic auth whose **password** equals the secret (matches SAP SM59 HTTP destinations) |
| `SAP_WEBHOOK_HOST` / `--webhook-host` | all interfaces | Bind address of the standalone IDoc webhook (stdio mode). Set `127.0.0.1` behind a reverse proxy |
| `SAP_WEBHOOK_MAX_BODY_BYTES`  | `10485760` (10 MB) | Reject larger IDoc payloads with `413` before they are buffered in memory                    |

In HTTP transport mode the `/idoc` route is mounted on the MCP port: with `--webhook-secret` it authenticates independently of `--api-key` (so SAP's Basic auth works while n8n uses the Bearer key); without it, it falls under `--api-key` if set — and is **open** if neither is configured (the server logs a warning at startup).

Both timeouts must stay **below the smallest client limit** in your setup. Measured against a production S/4HANA behind Cloudflare: Cloudflare aborts at 100 s (`524`), n8n's MCP client transport at 300 s. A budget above the smallest limit never takes effect, because the client gives up first.

#### Tracing a slow tool call

Every tool call logs one line on completion, carrying a correlation id that also appears on each SAP request it triggered:

```json
{"correlationId":"a3f19c8b2d04","tool":"sap_discover_services","outcome":"ok","durationMs":842,"sapCalls":1,"resultBytes":18422}
```

`grep a3f19c8b2d04` then shows the full story of that one call — including how many SAP requests it produced. `outcome` is one of `ok`, `error`, `timeout` (budget expired) or `aborted` (client disconnected).

**`level: 50` means something is actually wrong.** Expected non-2xx responses — the `404`s from the catalog path probing and from the V4 catalog attempt on systems that have none — are logged at `info` with `"expected": true`, not at `error`. Measured on a production system: over 96 hours of runtime that false alarm was the *only* error-level entry in the log. Alerting on `level: 50` is therefore meaningful; before, it produced nothing but noise.

#### When something breaks

`test-connection` walks the whole chain and reports the **first** failing stage — DNS, TLS (including the certificate chain), authentication, client (Mandant), catalog. Stages after the failure are reported as `skipped`, never as passed. The same five stages are logged once at startup, so the container log shows the state of the connection without calling anything.

Every error response carries a classification, the SAP error code where one exists, a plain-language message and the next action — no tool answers with `"Unknown error"`. Three cases that used to cost a separate diagnosis each:

| What SAP returns | What the server tells you |
|---|---|
| `403` with `/IWFND/MED/170` | The service is not registered — activate it in `/IWFND/MAINT_SERVICE`. **Not** an authorization problem, despite the 403 |
| `401` with an HTML logon page | Is `sap-client` set? Without it a client-dependent Gateway rejects the logon in a way that looks like a wrong password |
| `UNABLE_TO_GET_ISSUER_CERT_LOCALLY` | The certificate chain is incomplete; supply the root CA via `SAP_CA_CERT`. The message names the issuing CA |

If `SAP_TLS_VERIFY=false` is in effect, **every tool result** carries a warning about it — not just the startup log. A disabled check that nobody sees after the first day tends to stay for years; on the production system that prompted this work it was set, and nobody noticed.

#### Streamable HTTP is stateless

`--transport http` serves MCP in **stateless** mode: every request is self-contained and the server neither issues nor expects an `mcp-session-id` header. There is no server-side session to resume, so a client may reconnect at any time without losing state.

Clients that *require* a session id — they read `mcp-session-id` from the initialize response and send it back on subsequent requests — will fail against this server. The n8n MCP Client, Claude Desktop, and the MCP Inspector all work without it.

The legacy `--transport sse` mode is different: it keeps a per-connection session and expects a `?sessionId=` query parameter on `/messages`. Prefer `http` for new setups.

#### Several SAP systems: `destinations.json`

The `SAP_*` variables describe **one** SAP system. To run one server against several — a production system next to a test client, or several customers' systems behind one n8n — put the connections into a `destinations.json` and point the server at it:

```bash
guniweb-sap-mcp --transport http --port 8808 --destinations /config/destinations.json
# or: SAP_MCP_DESTINATIONS=/config/destinations.json
```

```json
{
  "version": 1,
  "destinations": {
    "default": {
      "baseUrl": "https://s4prod.example.com",
      "authType": "basic",
      "username": "MCP_USER",
      "password": "${S4PROD_PASSWORD}",
      "sapClient": "100"
    },
    "s4test": {
      "baseUrl": "https://s4test.example.com",
      "authType": "basic",
      "username": "MCP_USER",
      "password": "${S4TEST_PASSWORD}",
      "sapClient": "200"
    }
  }
}
```

- **One entry = one connection.** Every entry accepts exactly the fields the `SAP_*` variables accept (`authType` and its credentials, `sapClient`, `baseUrl`) — all seven authentication types work per destination.
- **Secrets stay out of the file.** Any string may contain `${VARIABLE}`; it is resolved from the environment at load time (Docker secrets, `.env`). A placeholder that cannot be resolved makes the file invalid — an empty password would otherwise surface as a misleading `401` from SAP.
- **Hot reload.** The file is watched; a change is picked up on the next request, no restart. `kill -HUP <pid>` forces a reload. An invalid file **never** replaces the running configuration — the error is logged and the last valid one stays in force.
- **Backwards compatible.** Without `--destinations` nothing changes: the `SAP_*` variables are the single destination `default`. With the file, `SAP_*` (if set) is added as `default` unless the file defines one — so an installation can migrate without a gap.
- **Which destination answers?** Without a token: the one named `default` (or the only one). With a token: the token's destination — see below.

**Tokens: one Bearer value per n8n credential selects the system.** The n8n MCP Client sends exactly one `Authorization` header, so a token does two jobs at once — it authenticates the request and picks the destination. SAP passwords never leave the server; n8n only holds the token.

```json
{
  "version": 1,
  "destinations": { "s4prod": { "...": "..." }, "s4test": { "...": "..." } },
  "tokens": [
    { "hash": "sha256:9f2c…", "destination": "s4prod", "label": "n8n prod workflows" },
    { "hash": "sha256:1a7e…", "destination": "s4test", "label": "n8n dev", "revoked": false }
  ]
}
```

- The file holds only the **SHA-256 hash**; the plain token (`gsm_<destination>_<random>`) is printed **once** by `tokens issue` and cannot be recovered afterwards. Put it into an n8n **Bearer Auth** credential on the MCP Client node. As soon as at least one token exists, requests without a valid token get `401` — `--api-key` keeps working alongside and serves the `default` destination.
- Lookup is constant-time over all entries; `"revoked": true` disables a token on the next request (hot reload, no restart). After 10 failed attempts within a minute the client address gets `429` with `Retry-After` — also for a valid token — as a brake on guessing (a reverse proxy with a real rate limit is still the right place for that). Tokens are never written to the log; rejections are logged with address and reason.
**Managing the file — no hand-editing needed.** The same binary carries the admin commands; every command validates the result exactly like the server does before writing (never leaves an unloadable file), writes atomically, and a running server picks the change up on the next request:

```bash
export SAP_MCP_DESTINATIONS=/config/destinations.json      # or --destinations <path> on each call

guniweb-sap-mcp destinations add s4prod --base-url https://s4prod.example.com --auth-type basic \
    --username MCP_USER --password '${S4PROD_PASSWORD}' --sap-client 100
guniweb-sap-mcp destinations add legacy --from-env         # copy the current SAP_* environment (migration)
guniweb-sap-mcp destinations list                          # names, URLs, auth type, client, token count — never secrets

guniweb-sap-mcp tokens issue s4prod --label "n8n prod" --read-only --tiers core,odata
#   → prints the plain token ONCE on stdout (everything else goes to stderr, so TOKEN=$(…) works)
guniweb-sap-mcp tokens list                                # label, destination, hash prefix, policy, status
guniweb-sap-mcp tokens revoke "n8n prod"                   # by label or ≥ 8 hex chars of the hash
guniweb-sap-mcp destinations remove s4test [--force]       # refuses while tokens point at it, unless --force
```

`--set field=value` covers any auth type (`--auth-type oauth2 --set clientId=… --set clientSecret='${BTP_SECRET}' --set tokenServiceUrl=…`); `${ENV_VAR}` values are checked against the current environment (`--allow-missing-env` to skip, e.g. when the variable only exists inside the container). In Docker, run the commands inside the container so they see the same file and environment: `docker compose exec sap-mcp guniweb-sap-mcp tokens issue s4prod`.

- **Per-token permissions** — `"policy": { "readOnly": true, "tiers": ["core", "odata"] }`. A policy only ever *restricts*: `readOnly: true` hides the write tools for that token even when the server runs with `--allow-write` (`readOnly: false` cannot open a read-only server), and `tiers` is a ceiling — tiers outside it are invisible for that token and `sap_enable_tools` cannot switch them on. `tools/list` is filtered per request, so an agent on a read-only token never sees `sap_create` in the first place.

### 4. Use with n8n

1. Add an **AI Agent** node with an **MCP Client Tool** sub-node
2. Set the MCP Client URL to `http://sap-mcp:8808/mcp` (Docker) or `http://localhost:8808/mcp`, with a Bearer Auth credential holding your API key or destination token
3. The AI Agent node discovers the SAP tools automatically. **Which** tools it sees is your decision, not the model's: read-only by default, write tools only with `--allow-write`, and per-token policies narrow it further. Design the workflow as a deterministic, human-authored sequence — the LLM fills in the parameters

## Setup for SAP ECC

ECC NetWeaver backends require additional setup beyond the [Quick Start](#quick-start). The MCP server supports ECC 6.0+ (EHP 7+) for OData V2, OData V4, IDoc HTTP/XML, and RFC/BAPI. Cloud-only S/4HANA tenants do not need this section.

### 1. Activate NetWeaver Gateway

In transaction `SICF`, activate the standard ICF services under `/sap/opu/odata/`. Then use transaction `/IWFND/MAINT_SERVICE` to register the OData services you want to expose.

The MCP server's catalog auto-discovery probes three paths in sequence and caches the first 200 hit:

- `/sap/opu/odata/IWFND/CATALOGSERVICE;v=2/ServiceCollection` (S/4HANA default)
- `/sap/opu/odata/iwfnd/CATALOGSERVICE;v=2/ServiceCollection` (lower-case ECC)
- `/sap/opu/odata/IWFND/CATALOGSERVICE/ServiceCollection` (ECC EHP 7 v=1)

Override via `ODATA_V2_CATALOG_PATH` if your gateway uses a non-standard mount.

### 2. Install SAP NW RFC SDK (RFC/BAPI tools only)

Required for the `rfc` tool tier. Skip this step if you only use OData or IDoc.

**Linux:**

```bash
tar xzf nwrfcsdk_linux.tgz -C /usr/sap/
export LD_LIBRARY_PATH=/usr/sap/nwrfcsdk/lib:$LD_LIBRARY_PATH
npm install node-rfc
```

**macOS:**

```bash
tar xzf nwrfcsdk_darwin.tgz -C /usr/sap/
export DYLD_LIBRARY_PATH=/usr/sap/nwrfcsdk/lib:$DYLD_LIBRARY_PATH
npm install node-rfc
```

`node-rfc` is declared as `optionalDependencies` -- if the SDK is missing, the server logs a Pino warning at startup and the RFC tier is skipped. OData and IDoc tools continue to work.

### 3. ECC-Specific Environment Variables

In addition to the variables documented in [Quick Start](#quick-start):

| Variable                  | Required               | Description                                                                                |
|---------------------------|------------------------|--------------------------------------------------------------------------------------------|
| `ODATA_V2_CATALOG_PATH`   | No (auto-discover)     | Override catalog path, e.g. `/sap/opu/odata/iwfnd/CATALOGSERVICE;v=2/ServiceCollection`     |
| `SAP_TLS_VERIFY`          | No (default `true`)    | Set to `false` to disable TLS certificate verification for self-signed-cert ECC scenarios   |
| `SAP_CLIENT_CERT_PATH`    | For X.509 client-cert  | Path to PEM-encoded client certificate, e.g. `/etc/sap/client.crt`                          |
| `SAP_CLIENT_KEY_PATH`     | For X.509 client-cert  | Path to PEM-encoded private key (optional passphrase via prompt)                            |
| `SAP_SNC_QOP`             | For SNC (RFC)          | SNC Quality-of-Protection level: `1` (auth-only), `2` (integrity), `3`/`8`/`9` (encryption) |
| `SAP_SNC_MYNAME`          | For SNC (RFC)          | Local SNC name, e.g. `p:CN=mcp-server, O=GuniWeb`                                           |
| `SAP_SNC_PARTNERNAME`     | For SNC (RFC)          | Backend SNC name, e.g. `p:CN=SAPSERVER, O=ACME`                                             |
| `SAP_SNC_LIB`             | For SNC (RFC)          | Path to SNC library (`.so` / `.dylib` / `.dll`), e.g. `/usr/sap/sapcrypto/libsapcrypto.so`  |

## Available Tools (22)

### Core Tier (always active)
| Tool | Description |
|------|-------------|
| `test-connection` | Stage-by-stage connection diagnosis (DNS → TLS → auth → client → catalog); names the first failing stage |
| `sap_list_services` | List entity sets in an OData service (paged, default 50) |
| `sap_discover_services` | Discover all services with category filtering and search |
| `sap_get_metadata` | Inspect entity types, properties, keys, and what SAP allows per entity set (creatable/updatable/deletable) |

### OData Tier (active by default)
| Tool | Description |
|------|-------------|
| `sap_read` | Read a single entity or collection |
| `sap_query` | Query with OData $filter, $select, $expand, paging (default `top` 50) |
| `sap_nl_query` | Natural language query with structured filters |
| `sap_create` | Create entities (supports deep insert + draft services) |
| `sap_update` | Update entities (automatic ETag handling) |
| `sap_delete` | Delete entities (automatic ETag handling) |
| `sap_function` | Call V2 function imports or V4 actions/functions |
| `sap_batch` | Execute multiple operations in a single batch |

### IDoc Tier (on-demand via `sap_enable_tools`)
| Tool | Description |
|------|-------------|
| `sap_idoc_send` | Send IDoc to SAP via HTTP/XML |
| `sap_idoc_list_received` | List received IDocs from webhook |
| `sap_idoc_status` | Check IDoc processing status |
| `sap_idoc_discover` | Discover available IDoc types |

### RFC Tier (on-demand via `sap_enable_tools`, requires SAP NW RFC SDK)
| Tool | Description |
|------|-------------|
| `sap_rfc_call` | Call any RFC-enabled function module with zod-validated parameters |
| `sap_rfc_metadata` | Fetch function-module signature (imports/exports/tables/exceptions) |
| `sap_bapi_call` | Invoke a BAPI, parse BAPIRET2 return tables, pin connection for follow-up commit |
| `sap_bapi_commit` | Invoke `BAPI_TRANSACTION_COMMIT` on the pinned session |
| `sap_rfc_search_functions` | Find function modules by name pattern via `RFC_FUNCTION_SEARCH` |

### Meta Tool
| Tool | Description |
|------|-------------|
| `sap_enable_tools` | Activate/deactivate tool tiers at runtime |

## Architecture

```mermaid
graph TB
    subgraph n8n["n8n"]
        Agent["AI Agent + LLM"]
        MCPClient["MCP Client Tool"]
        Agent --> MCPClient
    end

    subgraph Server["guniweb-sap-mcp"]
        Transport["Transport<br/>stdio | HTTP | SSE"]
        UserCtx["UserContext<br/>Extraction"]
        Registry["ToolRegistryManager<br/>Core | OData | IDoc"]
        Tools["17 MCP Tools<br/>3 Resources &bull; 3 Prompts"]
        OData["ODataClient<br/>V2/V4 Auto-Detect"]
        Discovery["Service Discovery<br/>16 Domain Categories"]
        NLQuery["NL-to-OData<br/>Filter Builder"]
        HTTP["SapHttpClient<br/>CSRF &bull; Redirect &bull; Auth"]
        Auth["Auth Layer<br/>7 Auth Types"]
        Cache["Per-User Token Cache<br/>LRU &bull; SHA-256"]

        Transport --> UserCtx
        Transport --> Registry
        Registry --> Tools
        Tools --> OData
        Tools --> Discovery
        Tools --> NLQuery
        OData --> HTTP
        Discovery --> HTTP
        NLQuery --> OData
        HTTP --> Auth
        Auth --> Cache
    end

    subgraph SAP["SAP Backend"]
        S4["S/4HANA<br/>OData V2/V4"]
        IDoc["IDoc<br/>HTTP/XML"]
        BTPSuite["BTP Integration<br/>Suite"]
        DestSvc["Destination<br/>Service"]
        TokenSvc["XSUAA / IAS<br/>Token Service"]
    end

    MCPClient -->|MCP Protocol| Transport
    HTTP -->|Direct| S4
    HTTP -->|Via BTP| BTPSuite
    BTPSuite --> S4
    HTTP --> IDoc
    Auth -->|Token Exchange| DestSvc
    Auth -->|OIDC / OAuth2| TokenSvc
    DestSvc --> S4

    style n8n fill:#e8f4fd,stroke:#4a90d9
    style Server fill:#f5f5f5,stroke:#555
    style SAP fill:#e8f0fe,stroke:#1a6fb5
```

### Integration Paths

```mermaid
graph LR
    subgraph Path1["Path 1: Direct"]
        n1["n8n"] -->|MCP| s1["MCP Server"] -->|Basic Auth| sap1["SAP S/4HANA"]
    end

    subgraph Path2["Path 2: BTP Client Credentials"]
        n2["n8n"] -->|MCP| s2["MCP Server"] -->|OAuth2| btp2["BTP Suite"] --> sap2["SAP S/4HANA"]
        s2 -->|CC Flow| tok2["XSUAA"]
    end

    subgraph Path3["Path 3: BTP Principal Propagation"]
        n3["n8n + JWT"] -->|MCP| s3["MCP Server"] -->|JWT Exchange| dest3["Destination Svc"] --> sap3["SAP S/4HANA"]
    end

    subgraph Path4["Path 4: SAML Bearer (no BTP)"]
        n4["n8n + JWT"] -->|MCP| s4["MCP Server"] -->|"SAML Assertion<br/>RSA-SHA256"| sap4["SAP OAuth2<br/>Endpoint"]
    end

    style Path1 fill:#e8f4fd,stroke:#4a90d9
    style Path2 fill:#fef9e7,stroke:#e8a317
    style Path3 fill:#eafaf1,stroke:#5b8c5a
    style Path4 fill:#fdf2e9,stroke:#8b5e3c
```

### Request Flow (OData Write)

```mermaid
sequenceDiagram
    participant LLM as LLM (via n8n)
    participant Tool as MCP Tool
    participant Registry as ToolRegistry
    participant OData as ODataClient
    participant HTTP as SapHttpClient
    participant SAP as SAP Gateway

    LLM->>Tool: sap_create(serviceUrl, entitySet, data)
    Tool->>Registry: isToolVisible?
    Registry-->>Tool: yes
    Tool->>OData: create(entitySet, data)
    OData->>HTTP: request(POST, url, data)

    Note over HTTP,SAP: CSRF Token Fetch
    HTTP->>SAP: GET /sap/opu/odata/sap/SRV/<br/>x-csrf-token: fetch<br/>sap-client: 324
    SAP-->>HTTP: x-csrf-token: TOKEN<br/>set-cookie: SESSION

    Note over HTTP,SAP: Mutating Request
    HTTP->>SAP: POST /sap/opu/odata/sap/SRV/EntitySet<br/>x-csrf-token: TOKEN<br/>Cookie: SESSION
    SAP-->>HTTP: 201 Created + entity data

    HTTP-->>OData: response
    OData-->>Tool: created entity
    Tool-->>LLM: JSON result via MCP
```

## Supported SAP Systems

The MCP server supports the following SAP backends. Connector availability depends on the target system; see footnotes for prerequisites.

| Connector             | ECC 6.0+ (EHP 7+)         | S/4HANA on-prem        | S/4HANA Cloud (Public) |
|-----------------------|---------------------------|------------------------|------------------------|
| **OData V2**          | ✅ supported [^1]         | ✅ supported           | ✅ supported           |
| **OData V4**          | ⚠️ partial [^4]           | ✅ supported           | ✅ supported           |
| **IDoc** (HTTP/XML)   | ✅ supported [^1]         | ✅ supported           | ❌ N/A [^3]            |
| **RFC/BAPI**          | ✅ supported [^1][^2][^5] | ✅ supported [^2][^5]  | ❌ N/A [^3]            |

Additionally validated against:

- SAP BTP Integration Suite (as intermediary for S/4HANA Cloud RFC/IDoc paths)
- SAP API Business Hub Sandbox

[^1]: NetWeaver Gateway ICF services must be activated (transaction `SICF`). See [Setup for SAP ECC](#setup-for-sap-ecc).
[^2]: Requires SAP NW RFC SDK 7.50+ on the host. `node-rfc` is declared as `optionalDependencies`; missing SDK degrades gracefully with a startup warning.
[^3]: S/4HANA Cloud Public Edition does not expose RFC or classic IDoc-HTTP for external consumers. Use SAP BTP Integration Suite as an intermediary.
[^4]: OData V4 in ECC is rare; most ECC NetWeaver Gateway services are V2. V4 is the default for S/4HANA.
[^5]: SNC library (`SAP_SNC_LIB`) is OS-specific (`.so` / `.dylib` / `.dll`) and must be installed separately.

## Documentation

- [Setup Guide](https://github.com/guniweb/guniweb-sap-mcp/blob/main/docs/setup-guide.md) -- Installation, all 7 auth types, CLI flags, named destinations and tokens, Docker deployment
- [Architecture](https://github.com/guniweb/guniweb-sap-mcp/blob/main/docs/architecture.md) -- Technical architecture, request flows, design decisions
- [API Reference](https://github.com/guniweb/guniweb-sap-mcp/blob/main/docs/api-reference.md) -- All 22 tools, resources, and prompts with parameters
- [Examples](https://github.com/guniweb/guniweb-sap-mcp/blob/main/docs/examples.md) -- SAP workflow examples with step-by-step instructions
- [SAP interfaces, tool by tool](https://github.com/guniweb/guniweb-sap-mcp/blob/main/docs/sap-interfaces.md) -- which SAP endpoint each of the 22 tools calls, what is bounded, what leaves your network — for Basis teams, license managers and auditors
- [Changelog](https://github.com/guniweb/guniweb-sap-mcp/blob/main/CHANGELOG.md) · [Releases](https://github.com/guniweb/guniweb-sap-mcp/releases) · [Issues](https://github.com/guniweb/guniweb-sap-mcp/issues) · [Discussions](https://github.com/guniweb/guniweb-sap-mcp/discussions)

## Governance: how this fits SAP's rules

- **Standard integration interfaces only.** The server speaks OData V2/V4 through NetWeaver Gateway, IDoc over HTTP/XML and RFC/BAPI — the documented, supported ways into an SAP system ([tool-by-tool list](https://github.com/guniweb/guniweb-sap-mcp/blob/main/docs/sap-interfaces.md)). No UI automation, no undocumented interfaces, no bulk replication of SAP data. Paging limits and time budgets are built in so a single tool call cannot turn into a load test of your Gateway.
- **The write path is governed and auditable.** Read-only by default; write tools exist only with an explicit `--allow-write`; per-token policies can only restrict, never widen; every tool call leaves one log line with a correlation id that also appears on each SAP request it triggered. That is what makes "human-governed" verifiable: the workflow author, not the model, decides where writes are possible.
- **Two things to settle before you automate document creation.** SAP's API usage policy contains terms on autonomous, generative use of its APIs — build workflows as deterministic, human-authored sequences with LLM assistance rather than open-ended autonomous agents (this server is designed for exactly that). And business documents created automatically (a sales order, for instance) may fall under SAP Digital Access licensing for your tenant — clarify that with your SAP account team before you go live. Neither sentence is legal advice; both are the questions your auditor will ask.

## Who is behind this — and how to get help

guniweb-sap-mcp is built and maintained by [GuniWeb](https://guniweb.de) — a consultancy with its own solutions: *processes that work, systems that grow with you*. GuniWeb optimises business processes for mid-sized companies, with more than 20 years of practice, strategic consulting and hands-on implementation, so that a company does not just become more digital but runs better. This server is one of those solutions: it runs in production at customers and is used in teaching and research. The compiled package on npm is **free to use** under the ISC license; the source code is not public.

- **Community** — questions, bug reports and ideas via [Issues](https://github.com/guniweb/guniweb-sap-mcp/issues) and [Discussions](https://github.com/guniweb/guniweb-sap-mcp/discussions), best effort. See [SUPPORT.md](https://github.com/guniweb/guniweb-sap-mcp/blob/main/SUPPORT.md).
- **Production support** — maintenance subscription with prioritised fixes, compatibility with SAP release changes and a direct channel; optionally with a response-time SLA for the write path: **[guniweb.de/sap-mcp](https://guniweb.de/sap-mcp#support)**
- **SAP MCP Checkup** — we review your n8n/SAP setup (auth, governance, tool visibility, performance) before it goes live: **[guniweb.de/sap-mcp](https://guniweb.de/sap-mcp#checkup)**

Contact: [support@guniweb.de](mailto:support@guniweb.de). Security issues: see [SECURITY.md](https://github.com/guniweb/guniweb-sap-mcp/blob/main/SECURITY.md) — and note the zero-telemetry commitment there.

## Technology

Built with:
- [MCP TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk) v1.x
- [axios](https://github.com/axios/axios) -- HTTP client with CSRF + redirect handling
- [jose](https://github.com/panva/jose) -- JWT/JWKS validation for IAS/XSUAA auth
- [fast-xml-parser](https://github.com/NaturalIntelligence/fast-xml-parser) -- IDoc XML + SAML assertion building
- [Zod](https://zod.dev/) v4 -- Schema validation
- [pino](https://github.com/pinojs/pino) -- Structured JSON logging
- [tsup](https://github.com/egoist/tsup) -- ESM bundling
- TypeScript 5.9, Node.js >= 22.18.0

---

SAP, S/4HANA, ECC, NetWeaver, ABAP are trademarks or registered trademarks of SAP SE in Germany and other countries. This project is not affiliated with SAP SE.

## License

ISC
