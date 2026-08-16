# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.1] - 2026-08-17

Diagnosis fix from the first end-to-end run of the personal SAP login with the n8n node.

### Fixed

- **A wrong SAP password is now reported as an authentication failure**, not as a catalog problem. Measured on an S/4HANA (SAP UCC S22): a rejected Basic-Auth login answers with SAP's HTML page "Anmeldung fehlgeschlagen" — the HTTP status did not survive into the error explainer, so `test-connection` reported stage `auth: ok` and `catalog: failed` with an HTML hint. The explainer now recognises SAP's logon-failure pages (`AUTH_FAILED`, guidance: check user/password, do not retry repeatedly — SAP locks the account) and the diagnosis assigns them to stage `auth` (or `client` when no `SAP_CLIENT` is set). Matters most for the personal login (`user-basic`), where the password comes from each person's n8n credential.

## [0.4.0] - 2026-08-17

One server, many people, no shared account — and a way to try it all without an SAP system.
This release adds the **personal SAP login per request** (`authType: user-basic`) that the new
[n8n community node](https://github.com/guniweb/n8n-nodes-guniweb-sap) uses so that every
person acts in SAP as themselves, an **Admin API** to manage destinations and tokens over HTTP,
and a **`--demo` mode** with a built-in mock S/4HANA. Nothing changes for a running server that
uses none of them.

### Added

- **`--demo` — try the server without an SAP system.** `npx guniweb-sap-mcp --demo` (also `SAP_MCP_DEMO=true`) starts a built-in mock S/4HANA in the same process — an in-memory OData V2 gateway on `127.0.0.1` with three services under their real SAP names and field names (`API_BUSINESS_PARTNER`, `API_SALES_ORDER_SRV`, `API_PRODUCT_SRV`; ~20 business partners with addresses, 15 sales orders with items, 10 products with descriptions) — and points the server at it. No `SAP_*` configuration is needed; a real one (`SAP_BASE_URL`, `--destinations`) is refused alongside `--demo` so it is always clear where the tools talk to. The mock behaves like a Gateway where it matters: catalog discovery (`IWFND/CATALOGSERVICE;v=2`, `substringof` search, the alternative V2/V4 paths answer 404), service documents and `$metadata` (EDMX with associations, `sap:` annotations, function imports), `$filter` (eq/ne/gt/ge/lt/le, and/or/not, substringof/startswith/endswith/tolower/toupper, `datetime'…'`), `$orderby/$top/$skip/$select/$expand/$inlinecount`, single entities and navigation, CSRF (`x-csrf-token: fetch`, 403 `Required` without it), ETags with `If-Match` (412 on a stale one), create with deep insert and SAP-style key assignment, MERGE (also tunnelled through POST), DELETE with cascading items, two function imports, `$batch` with atomic changesets, `sap-client` enforcement and SAP-shaped error payloads. Writes need `--allow-write` as always. Sample data only, in memory, gone at exit; nothing leaves the machine. Works with stdio and HTTP transport; the startup log says `DEMO-MODUS` and the self-test runs against the mock.
- **Admin API — `--admin-token <secret>` / `SAP_MCP_ADMIN_TOKEN`.** The CLI's operations on `destinations.json` are now also available over HTTP under `/admin`, so an n8n workflow, a provisioning script or a person with `curl` can create destinations and issue or revoke tokens without a shell on the host: `GET/PUT/DELETE /admin/destinations[/:name]`, `GET/POST /admin/tokens`, `DELETE /admin/tokens/:ref`. CLI and API share one implementation (`DestinationsAdmin`), so both validate the result exactly like the server before writing and write atomically. Separate keys, separate doors: the admin secret (min. 16 characters) opens *only* `/admin`, the n8n tokens and `--api-key` open *only* `/mcp` — a leaked n8n token cannot mint further access, an admin secret cannot read SAP data. Wrong secrets are counted per client address (`429` after 10 failures per minute); every change is logged with action, target and client address, never with the token or the secret; responses are `Cache-Control: no-store`. Every write reloads the running configuration before answering (`"reloaded": true` — or `false` with the errors when the running server cannot resolve a `${VAR}` written with `?allowMissingEnv=true`; the last valid configuration then stays in force). Without `--admin-token`, `/admin/*` answers `404`. Requires `--destinations` and HTTP/SSE transport; anything else is a startup error.
- **Personal SAP login per request — `authType: "user-basic"`.** A destination may now name system and client only; SAP user and password arrive with each request as `X-SAP-Username`/`X-SAP-Password` (or `X-SAP-Authorization: Basic …`) next to the Bearer token, and become the Basic-Auth configuration of that one request. Everyone acts in SAP as themselves — authorizations, change documents and audit trail on the real user, no shared technical account. The token still authenticates at the MCP server, selects the destination and applies its policy. No fallback: without a login the request is answered `401` with a hint; a login sent to a destination that runs on a technical user is answered `400` rather than silently ignored. Passwords are never logged; the SAP user is bound to the request logger (`sapUser` on every tool line). Catalog and metadata caches are kept per user (in memory only, bounded). HTTP/SSE transport only — stdio has no header for the login and refuses to start with such a default destination. The startup self-test skips these destinations (nothing to log in with) and says so. Built for the [n8n community node](https://github.com/guniweb/n8n-nodes-guniweb-sap), whose credential carries the SAP login.
- **Bootstrap without any SAP configuration.** With `--admin-token` the server starts even when `destinations.json` does not exist yet and no `SAP_*` variable is set: `/mcp` answers `503` (with a hint) until the first destination — and a token for it, or a destination named `default` — has been created through the API. `docker run … -e SAP_MCP_ADMIN_TOKEN=… -e SAP_MCP_DESTINATIONS=/config/destinations.json` is a complete first start.

### Changed

- `destinations remove` (CLI and API) refuses to remove the **last** destination — the server could not load the resulting file; add a replacement first or delete the file.
- Malformed JSON in a request body is answered with a JSON `400` (`{"error": "Invalid JSON body: …"}`) instead of Express' HTML error page — on `/admin` and `/mcp` alike.
- A `destinations.json` that has never existed no longer produces a "file invalid" warning on every re-check; only a file that disappears after it was loaded does.

### Fixed

- `sap_function`, `sap_batch` and `sap_nl_query` now accept the technical service name (`API_SALES_ORDER_SRV`) and absolute URLs like `sap_read`/`sap_query`/`sap_get_metadata` already did (R17). Before, the technical name — exactly what `sap_discover_services` returns — ended in `CONNECTION_ERROR Invalid URL` for these three tools.

## [0.3.1] - 2026-08-16

Documentation and links release, plus two robustness fixes from the first rollout of named
destinations. Nothing changes for a running server unless it hit one of the two fixed cases.

### Changed

- **Documentation, releases and issues now live at [github.com/guniweb/guniweb-sap-mcp](https://github.com/guniweb/guniweb-sap-mcp).** `package.json` (`repository`, `homepage`, `bugs`) and every documentation link in the README point there — previously they pointed at a private repository and returned 404 for anyone reading the README on npm. The source stays private; the compiled package is free to use under ISC.
- README: framing sharpened to *AI-assisted, human-governed workflows* (the workflow author decides the API sequence, the LLM fills parameters), a new **Governance** section (standard SAP interfaces only, governed write path, the two questions to settle before automating document creation), a **Who is behind this** section with support options, and a zero-telemetry statement. Tool count corrected to 22 everywhere; the API reference now documents all 22 tools (discovery, NL query, IDoc, RFC/BAPI and `sap_enable_tools` were missing).
- New `docs/sap-interfaces.md`: which SAP endpoint each of the 22 tools calls, what is bounded (paging, time budgets, concurrency), what leaves your network — written for Basis teams, license managers and auditors. New `SUPPORT.md` (community vs. commercial support, how the project is run) and `SECURITY.md` (reporting channel, supported versions, secure defaults, zero-telemetry commitment). Setup guide: "From Source" replaced by `npx` — the source is not public.

### Fixed

- **A write to `destinations.json` in the first second after startup is no longer missed.** Both the directory watcher (not yet armed) and the stat poll (its baseline is taken asynchronously) could overlook a file that was written right after `watch()` began — for example `destinations add` immediately after `compose up`. A one-off re-check 1.5 s after the watcher starts closes the window.
- **A configured but not-yet-existing `destinations.json` no longer prevents startup** when `SAP_*` is set. Observed during the first rollout: `SAP_MCP_DESTINATIONS` was set in Compose before the file had been created, and the container went into a restart loop. The server now starts with the environment as destination `default`, warns with the path, and loads the file as soon as it appears (directory watch / stat poll). A file that exists but is invalid still aborts startup with the errors listed.

## [0.3.0] - 2026-08-16

One server, several SAP systems, several users. Until now a server knew exactly one SAP
system, configured through `SAP_*` variables, and every n8n workflow talking to it shared
that one connection. This release adds named destinations, token-bound access with
per-token permissions, and a CLI to manage them — while a plain `SAP_*` installation keeps
working unchanged. Every step was deployed and verified against a live S/4HANA (SAP UCC)
before the next one started.

### Added

- **Named destinations — `--destinations <path>` / `SAP_MCP_DESTINATIONS`.** One server, several SAP systems: a `destinations.json` holds named connections (`default`, `s4test`, `sandbox`, …), each with exactly the fields the `SAP_*` variables accept — all seven authentication types per destination. Secrets may be written as `${VARIABLE}` and are resolved from the environment at load time; an unresolvable placeholder makes the file invalid rather than producing an empty password and a misleading `401`. The file is hot-reloaded (directory watch plus a 1 s stat poll as safety net, `SIGHUP` forces it) and takes effect on the next request; an invalid file **never** replaces the running configuration — the error is logged, the last valid one stays. Without the flag nothing changes: `SAP_*` is the single destination `default`; with the file, `SAP_*` is added as `default` unless the file defines one, so an installation migrates without a gap. Startup self-test and the missing-`SAP_CLIENT` warning now run per destination. Currently the destination named `default` (or the only one) answers; token-bound selection per n8n credential is the next step, and the file format already reserves `tokens` for it.

- **Token-bound access — a Bearer token selects the destination.** `destinations.json` may list `tokens: [{ hash, destination, label?, policy?, revoked? }]`. A request whose `Authorization: Bearer` matches a token's SHA-256 hash is served by that token's destination — one n8n credential per system, SAP passwords never leave the server. Lookup is constant-time over all entries (no early exit, so timing reveals neither existence nor position); as soon as one token exists, requests without a valid token get `401`, while `--api-key` keeps working alongside and serves `default`. `revoked: true` takes effect on the next request through the hot reload. After 10 failed attempts within a minute a client address is answered with `429` and `Retry-After` — also for a valid token — as a brake on guessing. Tokens are never logged; rejections are logged with client address and reason. In HTTP mode a file with several destinations and no `default` now starts as long as tokens exist; stdio still needs a `default` (it has no `Authorization` header). The plain token format is `gsm_<destination>_<random>`; a CLI to issue and revoke tokens follows, until then the README shows a one-liner.

- **Per-token policy — `policy: { readOnly?, tiers? }` on a token.** Applied per request and only ever restrictive: `readOnly: true` hides the write tools for that token even when the server runs with `--allow-write` (`readOnly: false` cannot open a read-only server); `tiers` is a ceiling on top of `--tiers` — tiers outside it are invisible for that token, `sap_enable_tools` refuses to switch them on and does not advertise them. `tools/list` reflects the policy, so an agent on a read-only token never sees `sap_create`; a call anyway is answered with the MCP error "Tool sap_create disabled".

- **Admin CLI in the same binary — `guniweb-sap-mcp destinations list|add|remove`, `tokens list|issue|revoke`.** Every command validates the resulting file with the server's own parser before writing (it never leaves a file the server could not load), writes atomically (temp file + rename, new files `0600`), and a running server picks the change up on the next request. `tokens issue` prints the plain token exactly once on stdout — everything else goes to stderr, so `TOKEN=$(guniweb-sap-mcp tokens issue s4prod)` works — and stores only the hash; `tokens revoke <label|hash-prefix>` marks it revoked (entry kept, so the hash stays blocked). `destinations add --from-env` copies the current `SAP_*` environment into a named entry (the migration path), `--set field=value` covers every auth type, `${ENV_VAR}` values are checked against the environment (`--allow-missing-env` to skip). `destinations remove` refuses while tokens point at the entry unless `--force`. Secrets are never printed. Path via `--destinations` or `SAP_MCP_DESTINATIONS`. This replaces the `node -e` one-liner mentioned in the interim docs.

### Changed

- The client (Mandant) now travels with the connection: `createSapMcpServer` falls back to `config.sapClient` when the caller passes none, and the HTTP transport takes it from the resolved destination per request. Catalog and metadata caches are kept **per destination** in HTTP mode (keyed by name and base URL), so two systems never share an entry and one system keeps its cache across requests.

## [0.2.2] - 2026-08-02

Everything in this release comes from the field requirements gathered on a production
S/4HANA system on 2026-07-30 (`docs/roadmap.md`). The trigger was a `sap_list_services`
call that ran into a Cloudflare 524: the server fetched the catalog and then worked
through 1222 services one by one to load their metadata.

That specific fan-out was already gone. What was missing was the lesson from it —
a tool call could still grow without an upper bound, and nothing in the log said which
tool had caused which SAP requests.

> **Note on the version number.** This is a patch-level release carrying a breaking
> change. That is deliberate: the project is pre-1.0, and shipping a safe default sooner
> was judged more valuable than the version-number convention.

### BREAKING

- **The server is read-only by default.** `sap_create`, `sap_update`, `sap_delete`, `sap_function` and `sap_idoc_send` are no longer registered unless `--allow-write` (or `SAP_MCP_ALLOW_WRITE=true`) is set — they are absent from `tools/list`, not merely blocked, because a tool an agent cannot see is one it cannot call by accident. The first contact between an agent and a production ERP should not be able to change anything.

  **Migration:** add `--allow-write` to your start command if your workflows write to SAP. `--read-only` and `SAP_MCP_READ_ONLY` remain accepted and now simply describe the default, so existing commands do not break.

### Added

- **Time budget per tool call (`--tool-timeout`, default 30 s).** A tool call can no longer run without an upper bound. On expiry the client receives a valid MCP response carrying `truncated: true`, a plain-language reason and the hint how to widen the budget — never a hanging connection. Also settable via `SAP_MCP_TOOL_TIMEOUT`; `0` disables it and logs a warning at startup. The default sits below the smallest client limit measured in production (Cloudflare aborts at 100 s, n8n's MCP transport at 300 s).
- **Cancellation reaches SAP (`AbortSignal`).** When the client drops the connection, outbound SAP requests stop: `SapHttpClient.request` aborts before sending, the CSRF fetch stops probing further URL variants, the CSRF-403 retry is skipped, and the V2/V4 pagination returns the pages read so far with `truncated` plus a reason instead of discarding them. Previously discovery kept hammering a production S/4HANA after n8n had already given up.
- **One log line per tool call.** Carries a correlation id, outcome (`ok`/`error`/`timeout`/`aborted`), duration, number of SAP requests triggered and result size. The same id appears on every SAP request, so `grep <id>` shows the whole story of one call.
- **`totalCount`, `hasMore` and `nextSkip` in every list response** — `sap_query`, `sap_list_services` and `sap_discover_services`.

- **`test-connection` is now a stage-by-stage diagnosis.** DNS → TLS (including certificate chain) → authentication → client (Mandant) → catalog, reporting the **first** failing stage with a concrete next step. Stages after the failure are reported as `skipped`, never as passed. On a chain error it performs a second, unverified handshake purely to report the issuing CA — the one detail you need to fix it.
- **Startup self-test.** Logs the same five stages once at startup and warns explicitly when `SAP_CLIENT` is unset, instead of failing later with a misleading 401. It never blocks startup.
- **Known SAP errors are translated.** `/IWFND/MED/170` is reported as a missing service registration (with the explicit note that PFCG is the wrong place to look, despite the 403), a 401 with an HTML logon page asks about `sap-client`, and an incomplete certificate chain points at `SAP_CA_CERT` while ruling out `SAP_TLS_VERIFY=false` as a fix.

- **Caches survive restarts** — `--cache-dir` / `SAP_CACHE_DIR`. The catalog cache (TTL 30 min) and metadata cache (TTL 24 h) are written to disk atomically. Without it every restart refetches the full catalog; since n8n evicts its own MCP client entry on a transport error, restarts are not rare, and two volatile caches in a row turn one hiccup into a full cold start. A corrupt cache file is discarded with a warning, never repaired.
- **Cache keys include the base URL.** Two systems exposing the same service path no longer share an entry — previously a test system could be served the production data model.
- **Metadata report what SAP allows per entity set** — `creatable`, `updatable`, `deletable` from `sap:creatable` (V2) or the `Capabilities` annotations (V4), plus a `capabilities` summary listing the entity sets you can create in. Absent annotations count as allowed, per OData semantics.
- **Catalog search is pushed to the server** as an OData `$filter`, with a fallback to local filtering when the Gateway rejects `substringof` (400/501). A filtered result is deliberately not cached as if it were the full catalog.
- **`SAP_CA_CERT`** — the documented way past a corporate PKI, mirrored into `NODE_EXTRA_CA_CERTS`.
- **Progress notifications** for calls running longer than 5 seconds, when the client supplies a `progressToken`.
- **JWT signature verification for incoming user tokens** — `SAP_JWT_ISSUER`. Tokens are verified against the issuer's JWKS; one that fails is rejected with `401` rather than silently downgraded to the technical user, which would have made the check pointless. A bearer value that is not a JWT at all (a static API key) still means "technical user". The legacy SSE path verifies too. Without an issuer configured, behaviour is unchanged but `UserContext` now carries `verified: false` and the server says so at startup — the trust boundary is in the code, not only in the docs.
- **XXE hardening made explicit** — `processEntities` and `htmlEntities` are switched off in both XML parsers (IDoc webhook and `$metadata`), covered by billion-laughs and external-entity fixtures. External entities are rejected outright; the webhook answers `400` instead of failing.
- **`--concurrency`** (default 5) bounds simultaneous SAP requests. Applied where independent calls actually exist today: the V4 and V2 catalog fetches, which previously ran one after the other.

### Changed

- **`SAP_TLS_VERIFY=false` now warns in every tool result**, not only once at startup. A disabled check that nobody sees after the first day tends to stay for years — on the production system that prompted this work it was set, and nobody noticed.
- **The catalog path probe no longer downloads the catalog.** It sent no `$top`, so on a 1222-service system it fetched everything just to check whether the path answers. Now `$top=1`.
- **No tool answers with `"Unknown error"` any more.** Every failure now carries a classification, HTTP status, SAP error code, plain-language message and the next action. Raw SAP HTML pages are never passed through — only their essence. Error responses use `guidance` uniformly (previously `hint` in one place).
- **`serviceUrl` accepts the technical service name** (`API_SALES_ORDER_SRV`) in addition to the path and absolute URLs. Passing the technical name — exactly what `sap_discover_services` returns as `technicalName` — previously produced `"Unknown error"`.
- **Expected HTTP statuses no longer log as errors.** The catalog probe loop and the V4 catalog attempt declare `404` as normal; over 96 hours of runtime that false alarm was the only `level: 50` entry in the production log.
- **`sap_query.top` now defaults to 50** (hard cap 1000) and `sap_list_services` is paginated. Both were effectively unbounded before: `sap_query` could return ~1000 records via `maxPages`, `sap_list_services` returned every entity set at once. Callers who relied on the old behaviour must page explicitly using `skip` and the `nextSkip` value from the response.
- **`SAP_HTTP_TIMEOUT_MS` default lowered from 120 s to 30 s.** 120 s sat above the smallest client limit and could therefore never take effect. The value is additionally capped by whatever is left of the tool budget.
- **Server version now read from package.json** instead of a hard-coded `'1.1.0'`, which had drifted from the actual version and misled a production field analysis.

## [0.2.1] - 2026-04-28

### Fixed

- **Streamable HTTP transport: cache shared across requests.** `mountStreamableHttp` previously instantiated a fresh `CatalogCache` and `MetadataCache` per `/mcp` request, so the V2 catalog auto-discovery probe (~20 s on slow ECC backends) and the `$metadata` fetch were repeated on every tool call. Multi-tool agent runs (e.g. n8n langchain agent at `http://sap-mcp:8808/mcp`) timed out at 153 s with `Unknown error`. Caches are now created once at server-mount time and threaded into every per-request `createSapMcpServer` call via the new `ServerOptions.caches` hook. stdio mode is unchanged (single-process lifetime).
- **`ODataClient`: removed double `$metadata` fetch.** `initialize()` fetched `$metadata` for version detection but discarded the XML body, then `getMetadata()` re-fetched the same XML to parse it. The version-detection fetch now pre-populates the metadata cache on V2 (the production code path) so the parse step hits the cache instead of doing a second round-trip. V4 retains its CSDL-JSON path unchanged.

## [0.2.0] - 2026-04-27

### Added

- **RFC/BAPI client** -- Stateful connection pool (`src/rfc/`) on top of `node-rfc` 3.x with idle eviction (60s), graceful 5s drain on shutdown, and BAPI session pinning via UUID (Phase 22).
- **5 new MCP tools** in the `rfc` tier (on-demand via `sap_enable_tools`):
  - `sap_rfc_call` -- invoke any RFC-enabled function module with zod-validated parameters
  - `sap_rfc_metadata` -- fetch function-module signature (imports/exports/tables/exceptions) via `RFC_GET_FUNCTION_INTERFACE`
  - `sap_bapi_call` -- invoke a BAPI, parse `BAPIRET2` return tables, pin connection for follow-up commit
  - `sap_bapi_commit` -- invoke `BAPI_TRANSACTION_COMMIT` on the pinned session, optional `wait` parameter (default `true`)
  - `sap_rfc_search_functions` -- find function modules by name pattern via `RFC_FUNCTION_SEARCH`
- **`node-rfc` 3.3.1** as `optionalDependencies` -- graceful degradation with friendly Pino warning if SAP NW RFC SDK 7.50+ is missing on the host.
- **SNC for RFC** -- 4 env vars (`SAP_SNC_QOP`, `SAP_SNC_MYNAME`, `SAP_SNC_PARTNERNAME`, `SAP_SNC_LIB`) propagate to node-rfc connection options (Phase 23).
- **X.509 client certificates for OData** -- `SAP_CLIENT_CERT_PATH` + `SAP_CLIENT_KEY_PATH` (PEM, optional passphrase) propagate to axios `httpsAgent` (Phase 23).
- **`SAP_TLS_VERIFY` env var** -- opt-out of TLS certificate validation for self-signed-cert ECC scenarios; emits a startup warning when enabled (Phase 23).
- **OData catalog auto-discovery** -- probes 3 paths in sequence (S/4HANA default, lower-case ECC, ECC EHP 7 v=1) and caches the first 200 hit; override via `ODATA_V2_CATALOG_PATH` (Phase 23).
- **CLI `--help` / `-h`** -- prints usage text and exits 0 without requiring SAP env vars; runs before Pino init (no stderr noise) (Phase 21).
- **Compatibility matrix** -- README documents support across ECC 6.0+, S/4HANA on-prem, and S/4HANA Cloud for OData V2/V4, IDoc HTTP/XML, and RFC/BAPI (Phase 24).
- **Setup for SAP ECC** -- README section covering NetWeaver Gateway activation (`SICF` + `/IWFND/MAINT_SERVICE`), SAP NW RFC SDK install for Linux + macOS, and ECC-specific environment variables (Phase 24).

### Changed

- **Production bundle is now minified.** `tsup` config sets `minify: true`, `treeshake: true`, `sourcemap: false`, `target: 'node22'`. Packed-gzip tarball shrunk from ~130 KB to ~42 KB (Phase 21).
- **Repository positioning** -- "SAP S/4HANA MCP Server" -> "GuniWeb SAP S/4HANA & ECC MCP Server". README H1, tagline, hero diagram, and `package.json` description updated to highlight ECC support (Phase 24).
- **Top-level shutdown handler** -- `SIGTERM` / `SIGINT` now trigger `rfcPool.closeAll()` for both stdio and HTTP transports (previously only HTTP). Side-effect of RFC integration (Phase 22).

### Removed

- **Source maps from the published tarball.** `dist/index.js.map` is no longer generated; `package.json#files` is now an explicit 3-path whitelist (`dist`, `README.md`, `LICENSE`). The published tarball no longer leaks TypeScript source via `sourcesContent` (Phase 21).

[unreleased]: https://github.com/guniweb/guniweb-sap-mcp/releases
[0.3.1]: https://github.com/guniweb/guniweb-sap-mcp/releases/tag/v0.3.1
[0.3.0]: https://github.com/guniweb/guniweb-sap-mcp/releases/tag/v0.3.0
[0.2.2]: https://github.com/guniweb/guniweb-sap-mcp/releases/tag/v0.2.2
[0.2.1]: https://github.com/guniweb/guniweb-sap-mcp/releases/tag/v0.2.1
[0.2.0]: https://github.com/guniweb/guniweb-sap-mcp/releases/tag/v0.2.0
