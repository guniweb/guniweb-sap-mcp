# Which SAP interfaces this server uses — tool by tool

This page exists so that an SAP Basis team, a license manager or an auditor can answer one question quickly: **what does guniweb-sap-mcp actually call on our SAP system?** The answer is: only SAP's standard, documented integration interfaces — OData through NetWeaver Gateway, IDoc over HTTP/XML, RFC/BAPI through the SAP NW RFC SDK. No UI automation, no undocumented interfaces, no bulk replication. Every SAP request the server makes carries the credentials you configured; authorization is decided by SAP (PFCG), never bypassed.

Nothing on this page is legal advice. It describes what the software does so that you can assess it against your SAP contract, SAP's API usage policy and your Digital Access situation.

## Interfaces at a glance

| Interface | How the server uses it | Standard SAP endpoint |
|---|---|---|
| **OData V2** (NetWeaver Gateway, `IWFND`) | Catalog, `$metadata`, CRUD, function imports, `$batch` | `/sap/opu/odata/IWFND/CATALOGSERVICE;v=2/` and the service paths you address (`/sap/opu/odata/sap/<SERVICE>/…`) |
| **OData V4** (Gateway, S/4HANA 1809+) | Catalog, `$metadata`, CRUD, actions/functions, `$batch` | `/sap/opu/odata4/iwfnd/config/default/iwfnd/catalog/0002/ServiceGroups` and `/sap/opu/odata4/sap/<GROUP>/…` |
| **IDoc over HTTP/XML** (ICF service `IDOC_XML`) | Send IDocs; receive IDocs that SAP posts to your webhook | `POST /sap/bc/idoc_xml?sap-client=<client>` (send); your `/idoc` webhook, configured as an HTTP destination in `SM59` / `WE21` (receive) |
| **RFC / BAPI** (SAP NW RFC SDK, optional) | Call released remote-enabled function modules and BAPIs, `BAPI_TRANSACTION_COMMIT` | RFC protocol via `node-rfc` (only when the SDK is installed and `SAP_RFC_*` is configured) |

Which OData services exist and which of them are *released* SAP APIs is decided on your side: SAP-delivered services listed on the [SAP Business Accelerator Hub](https://api.sap.com/) are SAP's published APIs; custom (`Z*`) services are your own. The server does not distinguish — it calls what your Gateway exposes and your user is authorised for.

## Tool by tool

| Tool | Tier | SAP interface | What is called | Reads / writes |
|---|---|---|---|---|
| `test-connection` | core | OData V2 | `GET …/CATALOGSERVICE;v=2/` (one request; plus DNS/TLS handshake) | read |
| `sap_list_services` | core | OData V2 | `GET <service>/` service document (entity sets) | read |
| `sap_discover_services` | core | OData V2 + V4 catalog | `GET …/CATALOGSERVICE;v=2/ServiceCollection` (`$top`/`$skip`, server-side `$filter` where supported) and the V4 `ServiceGroups` catalog; result cached (30 min) | read |
| `sap_get_metadata` | core | OData V2/V4 | `GET <service>/$metadata` (cached 24 h) | read |
| `sap_nl_query` | core | OData V2/V4 | Structured filter → one `GET <service>/<EntitySet>?$filter=…` with `$top`/`$skip` passed through as given (set `top`; unlike `sap_query` it applies no default page size) | read |
| `sap_read` | odata | OData V2/V4 | `GET <service>/<EntitySet>(<key>)` | read |
| `sap_query` | odata | OData V2/V4 | `GET <service>/<EntitySet>?$filter/$select/$expand/$orderby/$top/$skip` — default page 50, hard cap 1000 per call | read |
| `sap_create` | odata | OData V2/V4 | `POST <service>/<EntitySet>` (with CSRF token fetch `GET` + `X-CSRF-Token: Fetch` first) | **write** |
| `sap_update` | odata | OData V2/V4 | `MERGE`/`PATCH <service>/<EntitySet>(<key>)` (+ CSRF) | **write** |
| `sap_delete` | odata | OData V2/V4 | `DELETE <service>/<EntitySet>(<key>)` (+ CSRF) | **write** |
| `sap_function` | odata | OData V2/V4 | V2 function import (`GET`/`POST`), V4 action/function (`POST`/`GET`) (+ CSRF for writes) | **write** |
| `sap_batch` | odata | OData V2/V4 | `POST <service>/$batch` (multipart; changesets = one LUW) | **write** |
| `sap_idoc_send` | idoc | IDoc HTTP/XML | `POST /sap/bc/idoc_xml?sap-client=…` with the IDoc XML (`EDI_DC40` control record + segments) | **write** |
| `sap_idoc_status` | idoc | OData V2 | `GET <statusServiceUrl>/IdocStatus(...)` — an OData service **on your side** exposing IDoc status (there is no SAP standard service for this; typically a small custom Gateway service over `EDIDC`) | read |
| `sap_idoc_discover` | idoc | OData V2 | `GET <metadataServiceUrl>/IdocTypes(...)` — likewise a custom OData service exposing IDoc type/segment structure | read |
| `sap_idoc_list_received` | idoc | server-internal | Lists IDocs SAP posted to the `/idoc` webhook — no SAP call | read |
| `sap_rfc_search_functions` | rfc | RFC | `RFC_FUNCTION_SEARCH` (function-module search) | read |
| `sap_rfc_metadata` | rfc | RFC | `RFC_GET_FUNCTION_INTERFACE` (interface description of a function module) | read |
| `sap_rfc_call` | rfc | RFC | Calls the remote-enabled function module you name | **write** (may change data — treated as write) |
| `sap_bapi_call` | rfc | RFC / BAPI | Calls the BAPI you name; no implicit commit | **write** |
| `sap_bapi_commit` | rfc | RFC / BAPI | `BAPI_TRANSACTION_COMMIT` on the same stateful connection as the preceding `sap_bapi_call`; an uncommitted session rolls back when it idles out | **write** |
| `sap_enable_tools` | meta | none | Activates a tool tier for the session — no SAP call | — |

Tiers `idoc` and `rfc` are inactive by default (`--tiers` or `sap_enable_tools`); the RFC tools exist only when the SAP NW RFC SDK and the optional `node-rfc` package are present. Write tools are not registered at all until `--allow-write` is set; a per-token `readOnly` policy hides them again for that token.

## Behaviour that matters for API-usage and load

- **No bulk replication.** Every list is bounded: `sap_query` pages at 50 rows by default with a hard cap of 1000 per call, catalog and service listings are paginated, and each tool call has a time budget (default 30 s) after which it returns what it has, marked `truncated`. There is no "export the table" tool.
- **Respecting the Gateway.** Concurrency towards SAP is bounded (`--concurrency`, default 5); catalog and `$metadata` are cached (30 min / 24 h, optionally on disk) so discovery does not repeat per tool call; a client that disconnects aborts the outbound SAP requests. Expected `404`s (no V4 catalog on older systems) are handled, not retried in a loop.
- **Human-governed sequences.** The server offers tools; it does not plan API sequences. In the intended n8n setup the workflow author decides which tools are visible (server flags, per-token policy) and designs the workflow as a deterministic sequence; the LLM extracts, maps and fills parameters. If your SAP contract or SAP's API usage policy has terms on autonomous or generative use of APIs, this is the design to point to — and the governance features (read-only default, explicit write enablement, per-token ceilings, per-call log lines with correlation ids) are how you evidence it.
- **Digital Access.** Documents created through this server by automated means (sales orders, deliveries, invoices, …) are created like any other API-created document. Whether they count towards SAP Digital Access for your tenant is a question of your license, not of this software — settle it with your SAP account team before you go live with automated document creation.
- **What leaves your network.** Only the requests above, to the SAP/BTP endpoints you configure (and OIDC/JWKS lookups when `SAP_JWT_ISSUER` is set). The server sends no telemetry.
- **Demo mode talks to no SAP system.** `--demo` starts an in-memory mock gateway on `127.0.0.1` inside the server process and points the server at it; every request above then goes to that mock. Nothing is sent to any SAP endpoint, and the sample data is invented.
- **Admin API calls no SAP endpoint.** `/admin/*` (optional, `--admin-token`) only reads and writes the server's own `destinations.json` — creating a destination or issuing a token does not contact SAP. Connectivity is verified by the startup self-test and `test-connection`, on your side.

## Authorization

The server authenticates as the technical user (or, with principal propagation, as the end user) you configure per destination. What that user may do is decided by SAP roles (`PFCG`); a `403` from SAP is reported as such, with the SAP message and the next step (`SU53` for authorization traces, `/IWFND/MAINT_SERVICE` when a service is simply not activated). The recommended setup is a dedicated technical user per destination with exactly the OData services / RFC function groups the workflows need — the same principle as for any other integration. Where people should act as themselves, a destination with `authType: user-basic` takes the SAP user and password from each request (the n8n credential of the person) — SAP then applies that person's roles, and every change document names them; the server never substitutes a technical user when the login is missing.
