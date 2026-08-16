# Architecture

Technical architecture of the SAP S/4HANA MCP Server (`guniweb-sap-mcp`).

## Component Overview

```mermaid
graph TB
    subgraph Transport["Transport Layer"]
        stdio["stdio"]
        http["Streamable HTTP"]
        sse["SSE"]
        apikey["Auth Guard<br/><i>API key or destination token</i>"]
        dest["DestinationStore<br/><i>destinations.json, hot reload</i>"]
        userctx["UserContext Extraction<br/><i>JWT &rarr; sub, email, name</i>"]
    end

    subgraph MCP["MCP Server"]
        registry["ToolRegistryManager<br/>Core | OData | IDoc | RFC Tiers<br/><i>+ per-token policy ceiling</i>"]
        tools["22 MCP Tools"]
        resources["3 MCP Resources<br/><i>metadata, schema, routing</i>"]
        prompts["3 MCP Prompts"]
        meta["sap_enable_tools<br/><i>Runtime tier activation</i>"]
        registry --> tools
        registry --> meta
    end

    subgraph Data["Data Processing"]
        odata["ODataClient<br/><i>V2/V4 auto-detect</i>"]
        catalog["CatalogClient<br/><i>V2+V4 catalog fetch</i>"]
        categorizer["ServiceCategorizer<br/><i>16 business domains</i>"]
        nlquery["NL-to-OData<br/><i>Filter Builder</i>"]
        metadata["MetadataCache"]
        etag["ETagCache"]
    end

    subgraph HTTP["HTTP Layer"]
        httpclient["SapHttpClient"]
        csrf["CSRF Handler<br/><i>GET on service root</i>"]
        redirect["Redirect Handler<br/><i>Re-inject auth on 307</i>"]
    end

    subgraph Auth["Authentication (8 Types)"]
        basic["basic<br/><i>Base64 header</i>"]
        userbasic["user-basic<br/><i>login from request headers</i>"]
        oauth2["oauth2<br/><i>CC token + cache</i>"]
        apikey2["apikey<br/><i>APIKey header</i>"]
        ias["ias / xsuaa<br/><i>OIDC + JWKS</i>"]
        btp["btp-principal<br/><i>JWT Bearer exchange</i>"]
        saml["saml-bearer<br/><i>SAML 2.0 + RSA sign</i>"]
        tokencache["Per-User Token Cache<br/><i>LRU, SHA-256 key</i>"]
    end

    Transport --> MCP
    tools --> odata
    tools --> catalog
    tools --> nlquery
    catalog --> categorizer
    nlquery --> odata
    odata --> httpclient
    odata --> metadata
    odata --> etag
    catalog --> httpclient
    httpclient --> csrf
    httpclient --> redirect
    httpclient --> Auth
    btp --> tokencache
    saml --> tokencache
    userctx -.->|"user JWT"| btp
    userctx -.->|"user JWT"| saml

    style Transport fill:#4a90d9,color:#fff,stroke:#3a7bc8
    style MCP fill:#2d2d2d,color:#fff,stroke:#555
    style Data fill:#5b8c5a,color:#fff,stroke:#4b7c4a
    style HTTP fill:#8b5e3c,color:#fff,stroke:#7b4e2c
    style Auth fill:#7b3f8d,color:#fff,stroke:#6b2f7d
```

## Integration Paths

### Path 1: Direct S/4HANA

```mermaid
sequenceDiagram
    participant n8n as n8n AI Agent
    participant MCP as guniweb-sap-mcp
    participant SAP as SAP S/4HANA

    n8n->>MCP: MCP tool call
    MCP->>SAP: GET/POST + Basic Auth header
    SAP-->>MCP: OData response
    MCP-->>n8n: JSON result
```

### Path 2: BTP Client Credentials

```mermaid
sequenceDiagram
    participant n8n as n8n AI Agent
    participant MCP as guniweb-sap-mcp
    participant XSUAA as XSUAA / IAS
    participant BTP as BTP Integration Suite
    participant SAP as SAP S/4HANA

    n8n->>MCP: MCP tool call
    MCP->>XSUAA: POST /oauth/token (client_credentials)
    XSUAA-->>MCP: access_token (cached)
    MCP->>BTP: GET/POST + Bearer token
    BTP->>SAP: Forward request
    SAP-->>BTP: OData response
    BTP-->>MCP: Response
    MCP-->>n8n: JSON result
```

### Path 3: BTP Principal Propagation

```mermaid
sequenceDiagram
    participant n8n as n8n + User JWT
    participant MCP as guniweb-sap-mcp
    participant Cache as Per-User Cache
    participant Dest as BTP Destination Service
    participant SAP as SAP S/4HANA

    n8n->>MCP: MCP call + Authorization: Bearer <user-jwt>
    MCP->>MCP: extractUserContext(jwt) -> sub, email
    MCP->>Cache: lookup(SHA-256(jwt))
    alt Cache miss
        MCP->>Dest: GET /destination-configuration/v1/destinations/NAME<br/>X-user-token: <user-jwt>
        Dest-->>MCP: SAP-bound access_token
        MCP->>Cache: store(token, TTL)
    end
    MCP->>SAP: GET/POST + Bearer <sap-token>
    SAP-->>MCP: Response (user-scoped authorization)
    MCP-->>n8n: JSON result
```

### Path 4: SAML Bearer (Direct, no BTP)

```mermaid
sequenceDiagram
    participant n8n as n8n + User JWT
    participant MCP as guniweb-sap-mcp
    participant Cache as Per-User Cache
    participant SAP as SAP S/4HANA OAuth2

    n8n->>MCP: MCP call + Authorization: Bearer <user-jwt>
    MCP->>MCP: extractUserContext(jwt) -> sub, email
    MCP->>Cache: lookup(SHA-256(jwt))
    alt Cache miss
        MCP->>MCP: Build SAML 2.0 Assertion<br/>NameID from JWT claims<br/>NotBefore = now - clockSkew
        MCP->>MCP: Sign XML with RSA-SHA256<br/>(privateKey + certificate)
        MCP->>SAP: POST /sap/bc/sec/oauth2/token<br/>grant_type=saml2-bearer<br/>assertion=<base64-saml>
        SAP-->>MCP: access_token
        MCP->>Cache: store(token, TTL)
    end
    MCP->>SAP: GET/POST + Bearer <sap-token>
    SAP-->>MCP: Response (user-scoped authorization)
    MCP-->>n8n: JSON result
```

## Tool Visibility System

```mermaid
flowchart TB
    Start["Server Start"] --> CLI["parseCliArgs()"]
    CLI --> Tiers{"--tiers flag?"}
    CLI --> ReadOnly{"--read-only?"}
    CLI --> IDoc{"IDoc config<br/>present?"}

    Tiers -->|"core,odata"| Registry["ToolRegistryManager"]
    Tiers -->|"not set"| DefaultTiers["Default: core + odata"] --> Registry
    ReadOnly -->|yes| HideWrite["Hide write tools<br/>Suppress sap_enable_tools"] --> Registry
    CLI --> Policy{"Token policy<br/>(HTTP, per request)?"}
    Policy -->|"readOnly / tiers"| Ceiling["Only restricts:<br/>readOnly OR-ed in,<br/>tiers become a ceiling"] --> Registry
    Policy -->|none| Registry
    ReadOnly -->|no| Registry
    IDoc -->|no| HideIDoc["Auto-disable IDoc tier"] --> Registry
    IDoc -->|yes| Registry

    Registry --> Active["Active Tool List<br/>sent to MCP Client"]
    Active --> LLM["LLM sees only<br/>visible tools"]

    LLM -->|"sap_enable_tools<br/>(tier: 'idoc')"| Enable["enableTier()"]
    Enable --> Notify["listChanged notification"]
    Notify --> Active

    style Start fill:#4a90d9,color:#fff
    style Registry fill:#2d2d2d,color:#fff
    style LLM fill:#5b8c5a,color:#fff
```

## Named Destinations and Token-Bound Access (0.3.0)

One server, several SAP systems. In HTTP mode every request is resolved to a destination before a per-request MCP server is created (the Streamable HTTP transport is stateless, so the resolution is cheap and naturally hot-reloadable):

```mermaid
flowchart LR
    Req["HTTP request<br/>Authorization: Bearer …"] --> Auth{"TokenAuthenticator"}
    Auth -->|"= --api-key"| Default["default destination"]
    Auth -->|"SHA-256 matches<br/>tokens[] (constant-time)"| Dest["token.destination<br/>+ token.policy"]
    Auth -->|"no match /<br/>revoked"| R401["401 (reason logged,<br/>token never logged)"]
    Auth -->|"> 10 failures / min<br/>per address"| R429["429 + Retry-After"]
    Default --> Server["createSapMcpServer(config,<br/>options ⊕ policy)"]
    Dest --> Server
    Store[("destinations.json<br/>DestinationStore<br/>watch + poll + SIGHUP")] -.->|"get(name) per request"| Auth
    Server --> Caches[("Catalog + metadata caches<br/>per destination")]

    style Store fill:#2d2d2d,color:#fff
    style R401 fill:#8b3a3a,color:#fff
    style R429 fill:#8b3a3a,color:#fff
```

- **`DestinationStore`** (`src/destinations/destination-store.ts`) — loads `destinations.json` (entries share the `SAP_*` zod schema; `${ENV}` placeholders resolved at load), keeps the last valid configuration if a reload fails, watches the directory (atomic replaces change the inode) with a 1 s stat poll as safety net, reloads on `SIGHUP`. Without a file the `SAP_*` environment is the single destination `default`; with a file, `SAP_*` is added as `default` unless the file defines one.
- **`TokenAuthenticator`** (`src/destinations/token-auth.ts`) — compares the presented token's hash against **all** entries without early exit; `--api-key` remains valid alongside. Rate limit per client address.
- **Policy** is applied in the transport (`applyTokenPolicy`) and enforced by the `ToolRegistryManager` (`allowedTiers` ceiling, `readOnly` OR-ed in) — `sap_enable_tools` cannot cross it, and `tools/list` reflects it per request.
- **CLI** (`src/destinations/cli.ts`) — `destinations list|add|remove`, `tokens list|issue|revoke`; validates with the server's parser before writing, writes atomically, prints the plain token exactly once on stdout.

## CSRF Token Flow

```mermaid
flowchart TB
    Request["Mutating Request<br/>POST / PUT / PATCH / DELETE"] --> Extract["Extract service root<br/>/sap/opu/odata/sap/SRV/Entity<br/>&darr;<br/>/sap/opu/odata/sap/SRV/"]

    Extract --> Fetch["GET service root<br/>x-csrf-token: fetch<br/>sap-client: 324"]

    Fetch --> HasToken{"Token in<br/>response?"}
    HasToken -->|yes| Inject["Inject x-csrf-token<br/>+ session cookies"]
    HasToken -->|no| Fallback["Fallback: GET base URL"]
    Fallback --> HasToken2{"Token?"}
    HasToken2 -->|yes| Inject
    HasToken2 -->|no| NoToken["Send without token"]

    Inject --> Send["Send mutating request"]
    NoToken --> Send

    Send --> Result{"Response?"}
    Result -->|"403 CSRF"| Retry["Retry once<br/>with fresh token"]
    Result -->|"2xx"| Success["Return response"]
    Retry --> Send

    style Request fill:#8b5e3c,color:#fff
    style Success fill:#5b8c5a,color:#fff
```

## Service Discovery Flow

```mermaid
flowchart LR
    Call["sap_discover_services<br/>(category, search)"] --> Catalog["CatalogClient"]

    Catalog --> V4["Fetch V4 Catalog<br/>/sap/opu/odata4/iwfnd/config/"]
    Catalog --> V2["Fetch V2 Catalog<br/>/IWFND/CATALOGSERVICE;v=2/"]

    V4 --> Merge["Merge + Deduplicate<br/><i>V4 priority</i>"]
    V2 --> Merge

    Merge --> Normalize["Normalize URLs<br/><i>absolute &rarr; relative paths</i>"]
    Normalize --> Categorize["Categorize Services"]

    Categorize --> Rules["13 Keyword Rules<br/>BUSINESS_?PARTNER &rarr; business-partner<br/>SALES_ORDER &rarr; sales<br/>..."]
    Categorize --> Modules["8 Module Rules<br/>ZMM_ &rarr; procurement<br/>ZSD_ &rarr; sales<br/>..."]

    Rules --> Filter["Filter by<br/>category + search"]
    Modules --> Filter
    Filter --> Paginate["Paginate"] --> Response["Return to LLM"]

    style Call fill:#4a90d9,color:#fff
    style Response fill:#5b8c5a,color:#fff
```

## Metadata Response Optimization

```mermaid
flowchart TB
    Call["sap_get_metadata(serviceUrl)"] --> Type{"entityType<br/>provided?"}

    Type -->|yes| Find["Find entity type<br/><i>case-insensitive</i>"]
    Find --> Found{"Found?"}
    Found -->|yes| Full["Return full<br/>property details"]
    Found -->|no| Suggest["Error + closest<br/>matching names"]

    Type -->|no| Search{"search<br/>provided?"}
    Search -->|yes| FilterTypes["Filter types/sets<br/>by name pattern"]
    Search -->|no| Count{"Entity type<br/>count?"}

    Count -->|"&gt; 50"| Compact["Compact mode:<br/>Entity set names only<br/>+ hint to use search"]
    Count -->|"&le; 50"| FullList["Full type list<br/>with keys + nav props"]

    FilterTypes --> FullList

    style Call fill:#4a90d9,color:#fff
    style Compact fill:#e8a317,color:#fff
    style Full fill:#5b8c5a,color:#fff
```

## Project Structure

```
src/
├── index.ts                    # Entry point, CLI, transport init
├── auth/                       # 8 authentication types (incl. user-basic: personal login per request)
│   ├── types.ts                # SapDestination discriminated union
│   ├── destination-factory.ts  # Creates destination from config
│   ├── oauth2-client.ts        # OAuth2 CC token manager
│   ├── ias-xsuaa-token-manager.ts  # IAS/XSUAA with OIDC discovery
│   ├── btp-principal-token-manager.ts  # BTP JWT Bearer exchange
│   ├── saml-bearer-token-manager.ts    # SAML 2.0 assertion + signing
│   ├── user-context.ts         # UserContext extraction from HTTP headers
│   ├── token-manager.ts        # TokenManager interface
│   └── oidc-discovery.ts       # OIDC/.well-known discovery
├── config/                     # Configuration & CLI
│   ├── types.ts                # Zod schema (all 8 auth types) — also the destination entry schema
│   ├── index.ts                # loadConfig() from env vars
│   ├── cli.ts                  # CLI args + --tiers, --allow-write, --tool-timeout, --destinations
│   └── startup-selftest.ts     # Five-stage self-test + SAP_CLIENT warning, per destination
├── destinations/               # Named destinations, tokens, policy, admin CLI (0.3.0)
│   ├── schema.ts               # destinations.json format, ${ENV} placeholders, token entries
│   ├── destination-store.ts    # Load, hot-reload (watch + poll + SIGHUP), fail-safe
│   ├── token-auth.ts           # Constant-time token lookup, api-key coexistence, rate limit
│   └── cli.ts                  # destinations list|add|remove, tokens list|issue|revoke
├── catalog/                    # Service discovery
│   ├── catalog-client.ts       # V2+V4 catalog fetch + URL normalization
│   ├── catalog-cache.ts        # In-memory catalog cache
│   ├── service-categorizer.ts  # 16 business domain categories
│   └── catalog-errors.ts       # BTP detection + actionable errors
├── nl-query/                   # NL-to-OData conversion
│   ├── filter-builder.ts       # Structured filters -> OData $filter
│   └── types.ts                # StructuredFilter type
├── http/                       # SAP HTTP communication
│   ├── sap-http-client.ts      # CSRF + redirect + per-user auth + abort/budget
│   ├── error-parser.ts         # OData error -> SapError
│   ├── sap-error-explainer.ts  # Failure -> cause + next action (R7/R17)
│   ├── connection-diagnostics.ts # DNS/TLS/auth/client/catalog staging (R9)
│   └── concurrency.ts          # Bounded parallel SAP calls (R5)
├── observability/              # What a tool call did, and how long it may take
│   ├── tool-context.ts         # AsyncLocalStorage: signal, deadline, correlation id
│   └── tool-instrumentation.ts # Time budget + one log line per tool call (R4/R14)
├── odata/                      # OData V2 + V4
│   ├── odata-client.ts         # Unified facade with version detection
│   ├── metadata-cache.ts       # TTL + base-URL key + optional persistence (R12)
│   ├── metadata-store.ts       # Atomic JSON persistence for the caches (R12)
│   ├── v2/                     # V2: GET/POST/MERGE/DELETE
│   ├── v4/                     # V4: GET/POST/PATCH/DELETE
│   └── batch/                  # $batch (multipart + JSON)
├── idoc/                       # IDoc HTTP/XML
│   ├── idoc-client.ts          # Send via POST to /sap/bc/idoc_xml
│   ├── webhook-server.ts       # Receive via HTTP webhook
│   └── ...                     # XML build/parse, validation, metadata
├── rfc/                        # RFC/BAPI via optional node-rfc (SAP NW RFC SDK)
│   ├── rfc-availability.ts     # Import-only detection; tools disabled when absent
│   ├── rfc-config.ts           # SAP_RFC_* (direct or load-balanced, SNC)
│   └── rfc-pool.ts             # Connection pool
├── routing/                    # Domain routing resources for LLM tool selection
├── mcp/                        # MCP protocol layer
│   ├── server.ts               # Server factory + tool registration proxy
│   ├── tools/                  # 22 MCP tools
│   ├── tool-registry.ts        # 4-tier visibility manager + token-policy ceiling
│   ├── resources/              # MCP resources (metadata, schema, routing)
│   └── prompts/                # Pre-built conversation starters
└── transport/                  # HTTP/SSE server
    └── http-server.ts          # Streamable HTTP + SSE, api-key/token auth, per-destination caches
```

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| No SAP Cloud SDK runtime | Removed for non-permissive transitive licenses. Custom HTTP + auth layer. |
| Unified OData facade | Single interface hides V2/V4 differences. Lazy version detection. |
| CSRF via GET (not HEAD) | Many SAP Gateways don't return tokens on HEAD requests. |
| Service-specific CSRF URL | Tokens are often service-scoped, not system-wide. |
| `z.string()` for write data | LLMs can't populate `z.record()` (generic `{type: object}`). JSON string works reliably. |
| Catalog URL normalization | SAP catalog returns absolute URLs that break when concatenated with baseUrl. |
| Compact metadata mode | Services with 300+ entity types overflow LLM context windows. |
| IDoc via HTTP/XML | No C++ native RFC bindings. Cross-platform, Docker-friendly. |
| Per-user LRU cache | SHA-256 keying prevents cross-user token leakage in principal propagation. |
| One token = auth + destination | The n8n MCP Client sends exactly one `Authorization` header; a token that both authenticates and selects the system keeps SAP secrets on the server. Header pass-through and credentials-as-tool-arguments were rejected. |
| Policy only restricts | A per-token policy can never widen what the server allows (`--allow-write`, `--tiers`) — the operator's baseline stays the upper bound. |
| Hot reload never replaces a valid config with an invalid one | A typo in `destinations.json` must not take a running server down; the error is logged, the last valid configuration stays. |

## Testing

- **1267 tests** -- unit, integration, E2E
- Unit tests run without SAP access (mocked HTTP)
- Integration/E2E require SAP API Business Hub Sandbox
- CI: unit on every push, integration on master
