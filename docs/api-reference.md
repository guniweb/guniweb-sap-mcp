# API Reference

Complete reference for all MCP tools, resources, and prompts provided by the SAP S/4HANA MCP Server.

## Tools

The server provides **24 tools**, organised in four tiers plus one meta-tool. The `core` and `odata` tiers are active by default; `idoc` and `rfc` are switched on with `--tiers` at startup or with `sap_enable_tools` at runtime. Write tools (marked with \*) are only registered when the server runs with `--allow-write` (or `SAP_MCP_ALLOW_WRITE=true`) — in the default read-only mode they do not appear in `tools/list` at all.

[`sap_function`](#sap_function) is the one exception (marked with \**): it stays visible in read-only mode, because a function import may read or write. Which one it is comes from the service metadata, checked per call — see [Function imports in read-only mode](#function-imports-in-read-only-mode).

| Tier | Tools | Active by default |
|------|-------|-------------------|
| `core` | [`test-connection`](#test-connection), [`sap_list_services`](#sap_list_services), [`sap_get_metadata`](#sap_get_metadata), [`sap_discover_services`](#sap_discover_services), [`sap_nl_query`](#sap_nl_query) | Yes |
| `odata` | [`sap_read`](#sap_read), [`sap_query`](#sap_query), [`sap_create`](#sap_create)\*, [`sap_update`](#sap_update)\*, [`sap_delete`](#sap_delete)\*, [`sap_function`](#sap_function)\**, [`sap_batch`](#sap_batch)\*, [`sap_media_upload`](#sap_media_upload)\*, [`sap_media_download`](#sap_media_download) | Yes |
| `idoc` | [`sap_idoc_send`](#sap_idoc_send)\*, [`sap_idoc_status`](#sap_idoc_status), [`sap_idoc_discover`](#sap_idoc_discover), [`sap_idoc_list_received`](#sap_idoc_list_received) | No — see [IDoc tools](#idoc-tools) |
| `rfc` | [`sap_rfc_call`](#sap_rfc_call)\*, [`sap_rfc_metadata`](#sap_rfc_metadata), [`sap_bapi_call`](#sap_bapi_call)\*, [`sap_bapi_commit`](#sap_bapi_commit)\*, [`sap_rfc_search_functions`](#sap_rfc_search_functions) | No — see [RFC/BAPI tools](#rfcbapi-tools) |
| meta | [`sap_enable_tools`](#sap_enable_tools) | Yes (not registered in read-only mode) |

Every tool declares MCP annotations. Read tools carry `readOnlyHint: true`; write tools carry `readOnlyHint: false`, and `sap_delete`, `sap_batch` and `sap_bapi_commit` additionally `destructiveHint: true`.

---

### Core tools

The `core` tier is always active. It covers connection diagnosis, service discovery, metadata inspection and the natural-language query helper — everything an agent needs to find its way around a system before touching data.

---

### test-connection

Diagnose the connection to the configured SAP system stage by stage and report the **first** failing stage.

Stages, in order: `dns` → `tls` → `auth` → `client` → `catalog`. Stages after a failure are reported as `skipped` — a stage that was never checked must not look like one that passed. The whole diagnosis completes in under 5 seconds.

**Parameters:** None

**Example Request:**
```json
{
  "name": "test-connection",
  "arguments": {}
}
```

**Example Response (all stages pass):**
```json
{
  "status": "connected",
  "stages": [
    { "stage": "dns", "status": "ok", "detail": "sap.example.com löst auf 10.0.0.1 auf.", "durationMs": 3,
      "info": { "address": "10.0.0.1", "family": 4 } },
    { "stage": "tls", "status": "ok", "detail": "TLS-Verbindung steht, Zertifikatskette ist verifizierbar. Aussteller: Corp Issuing CA 01.", "durationMs": 41,
      "info": { "verified": true, "issuer": "Corp Issuing CA 01", "validTo": "Mar 14 09:00:00 2027 GMT" } },
    { "stage": "auth", "status": "ok", "detail": "Anmeldung am Gateway erfolgreich.", "durationMs": 120 },
    { "stage": "client", "status": "ok", "detail": "Mandant 100 wird an jede Anfrage gehängt und vom Gateway angenommen.", "durationMs": 120 },
    { "stage": "catalog", "status": "ok", "detail": "Servicekatalog erreichbar (HTTP 200).", "durationMs": 120 }
  ],
  "durationMs": 164,
  "timestamp": "2026-08-02T10:00:00.000Z",
  "hint": "Nächster Schritt: sap_discover_services zeigt die verfügbaren OData-Services dieses Systems."
}
```

**Example Response (certificate chain incomplete):**

Note that `failedStage` answers "what is broken", and the `guidance` of that stage answers "what to do". The issuing CA is determined via a second, unverified handshake — without it the message would be a dead end.

```json
{
  "status": "failed",
  "failedStage": "tls",
  "stages": [
    { "stage": "dns", "status": "ok", "detail": "sap.example.com löst auf 10.0.0.1 auf.", "durationMs": 3 },
    { "stage": "tls", "status": "failed",
      "detail": "Die Zertifikatskette ist nicht vollständig verifizierbar. Aussteller des Serverzertifikats: Corp Issuing CA 01.",
      "guidance": "Root-CA über SAP_CA_CERT=<pfad> einbinden (intern NODE_EXTRA_CA_CERTS). …",
      "info": { "issuer": "Corp Issuing CA 01" }, "durationMs": 38 },
    { "stage": "auth", "status": "skipped", "detail": "Nicht geprüft — die TLS-Stufe scheiterte zuvor.", "durationMs": 41 },
    { "stage": "client", "status": "skipped", "detail": "Nicht geprüft — die TLS-Stufe scheiterte zuvor.", "durationMs": 41 },
    { "stage": "catalog", "status": "skipped", "detail": "Nicht geprüft — die TLS-Stufe scheiterte zuvor.", "durationMs": 41 }
  ],
  "durationMs": 44,
  "timestamp": "2026-08-02T10:00:00.000Z"
}
```

> **Why the `client` stage exists separately:** without `sap-client`, the SAP Gateway answers **401 "Anmeldung fehlgeschlagen"** — it looks like a wrong password but is not one. When `SAP_CLIENT` is unset and a 401 comes back, the diagnosis attributes it to the `client` stage, not to `auth`.

---

### sap_list_services

Discover available entity sets in an SAP OData service. This is the first step in the progressive discovery pattern: **list** -> inspect metadata -> execute operations.

| Parameter    | Type   | Required | Description                                                    |
|-------------|--------|----------|----------------------------------------------------------------|
| `serviceUrl` | string | Yes      | Service path (`/sap/opu/odata/sap/API_BUSINESS_PARTNER`), absolute URL, or the plain technical name (`API_BUSINESS_PARTNER`) |
| `top`        | number | No       | Maximum entity sets to return. Default **50**, hard cap **1000** |
| `skip`       | number | No       | Entity sets to skip. Use the `nextSkip` value from the response |

**Example Request:**
```json
{
  "name": "sap_list_services",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER"
  }
}
```

**Example Response:**
```json
{
  "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER",
  "entitySets": [
    "A_BusinessPartner",
    "A_BusinessPartnerAddress",
    "A_BusinessPartnerBank",
    "A_BusinessPartnerContact",
    "A_BusinessPartnerRole",
    "A_BusinessPartnerTaxNumber",
    "A_BuPaAddressUsage",
    "A_Customer",
    "A_Supplier"
  ],
  "count": 9,
  "returned": 9,
  "totalCount": 9,
  "hasMore": false,
  "top": 50,
  "skip": 0
}
```

> **Note:** When `--expose` patterns are configured, only matching entity sets are returned.
>
> **Paging (since 0.2.2):** omitting `top` does **not** mean "all" — it means 50. When `hasMore` is `true`, pass the returned `nextSkip` as `skip` to fetch the next page. `count` keeps its original meaning (the total), `returned` is the size of this page.

---

### sap_get_metadata

Inspect entity types, properties, keys, and navigation properties for an SAP OData service. This is the second step in the progressive discovery pattern: list -> **inspect metadata** -> execute operations.

| Parameter    | Type   | Required | Description                                        |
|-------------|--------|----------|----------------------------------------------------|
| `serviceUrl` | string | Yes      | OData service URL                                  |
| `entityType` | string | No       | Filter to a specific entity type name              |

**Example Request (full service):**
```json
{
  "name": "sap_get_metadata",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER"
  }
}
```

**Example Response (full service):**
```json
{
  "version": "v2",
  "entityTypes": [
    {
      "name": "A_BusinessPartnerType",
      "keys": ["BusinessPartner"],
      "propertyCount": 28,
      "navigationProperties": ["to_BusinessPartnerAddress", "to_BusinessPartnerBank", "to_BusinessPartnerRole"]
    }
  ],
  "entitySets": [
    {
      "name": "A_BusinessPartner",
      "entityTypeName": "A_BusinessPartnerType",
      "creatable": true,
      "updatable": true,
      "deletable": false
    }
  ],
  "capabilities": {
    "creatable": ["A_BusinessPartner"],
    "updatable": 1,
    "deletable": 0
  }
}
```

> **What SAP allows per entity set (since 0.2.2).** Each entity set carries `creatable`, `updatable` and `deletable`, read from `sap:creatable` and friends in the V2 `$metadata`, or from the `Capabilities` annotations in V4. When the annotation is absent the operation counts as allowed — that is the OData default, not a prohibition.
>
> `capabilities.creatable` lists the entity sets you can create in, so "which service can create sales orders?" is answerable without reading raw `$metadata` XML.

**Example Request (single entity type):**
```json
{
  "name": "sap_get_metadata",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER",
    "entityType": "A_BusinessPartnerType"
  }
}
```

**Example Response (single entity type):**
```json
{
  "version": "v2",
  "entityType": {
    "name": "A_BusinessPartnerType",
    "keys": [{ "name": "BusinessPartner" }],
    "properties": [
      { "name": "BusinessPartner", "type": "Edm.String" },
      { "name": "BusinessPartnerFullName", "type": "Edm.String" },
      { "name": "BusinessPartnerCategory", "type": "Edm.String" }
    ],
    "navigationProperties": [
      { "name": "to_BusinessPartnerAddress", "target": "A_BusinessPartnerAddress" }
    ]
  }
}
```

---

### sap_discover_services

Discover all OData services available on the connected SAP system. Fetches the V2 and V4 service catalogs, categorizes every service by business domain, and supports free-text search, category filtering, and pagination. This is the entry point when you do not yet know which service to use — before `sap_list_services` or `sap_get_metadata`. If you already know the service URL, skip straight to `sap_query` or `sap_nl_query`.

| Parameter  | Type   | Required | Description |
|-----------|--------|----------|-------------|
| `search`   | string | No       | Free-text search across service name, title, and description (case-insensitive) |
| `category` | string | No       | Filter by business domain. One of `business-partner`, `sales`, `finance`, `procurement`, `hr`, `logistics`, `production`, `quality`, `plant-maintenance`, `project`, `material`, `warehouse`, `analytics`, `master-data`, `cross-application`, `unknown` |
| `limit`    | number | No       | Maximum services to return. Default **50**, hard cap **1000** |
| `offset`   | number | No       | Services to skip. Use the `nextSkip` value from the response |

**Example Request:**
```json
{
  "name": "sap_discover_services",
  "arguments": {
    "search": "sales order",
    "category": "sales",
    "limit": 10
  }
}
```

**Example Response:**
```json
{
  "services": [
    {
      "technicalName": "API_SALES_ORDER_SRV",
      "title": "Sales Order (A2X)",
      "category": "sales",
      "serviceUrl": "/sap/opu/odata/sap/API_SALES_ORDER_SRV",
      "version": "v2"
    }
  ],
  "returned": 1,
  "totalCount": 1,
  "hasMore": false,
  "top": 10,
  "skip": 0,
  "summary": {
    "total": 1,
    "returned": 1,
    "offset": 0,
    "byCategory": { "sales": 1 }
  },
  "filterApplied": "server"
}
```

> **Paging:** the input parameters are named `limit`/`offset`, but the page information in the response uses the same field names as every other listing tool (`returned`, `totalCount`, `hasMore`, `nextSkip`, `top`, `skip`). `summary.byCategory` counts the services matching your filters **before** pagination, so it tells you what is out there even when you only fetched the first page.
>
> **`filterApplied`** is present only when `search` was given: `server` means the Gateway filtered the catalog via `$filter`, `client` means the full catalog was fetched and filtered locally. **`warnings`** (string array) appears when a catalog endpoint could not be read (for example the V4 catalog on an older system) — the remaining results are still returned.
>
> **Catalog not reachable:** the tool answers with `isError: true` and `{ "error": "...", "guidance": "..." }`. When a BTP Integration Suite endpoint is detected the response also carries `btpWarning`: the Integration Suite proxies individual OData services but does not expose the system catalog — use `sap_list_services` with a known service URL instead.

---

### sap_nl_query

Execute a structured, **read-only** OData query generated from natural language. Instead of a hand-written `$filter` string, the tool takes an array of `field` / `operator` / `value` filters and renders them in the correct OData V2 or V4 syntax for the service (the version is detected from `$metadata`). It never creates, updates, or deletes data. Use it together with the `nl-to-odata-query` prompt; if you already have an exact `$filter` expression, use `sap_query` instead.

| Parameter    | Type              | Required | Description |
|-------------|-------------------|----------|-------------|
| `serviceUrl` | string            | Yes      | OData service URL |
| `entitySet`  | string            | Yes      | Entity set to query |
| `filters`    | array of filter objects | Yes | Structured filters from the NL interpretation (an empty array queries without `$filter`) |
| `select`     | string[]          | No       | Properties to return |
| `orderby`    | string            | No       | Sort expression |
| `top`        | number            | No       | Maximum number of results |
| `skip`       | number            | No       | Number of results to skip |

**Filter Object:**

| Field      | Type                          | Required | Description |
|-----------|-------------------------------|----------|-------------|
| `field`    | string                        | Yes      | Property name from the entity schema |
| `operator` | `"eq"` \| `"ne"` \| `"gt"` \| `"ge"` \| `"lt"` \| `"le"` \| `"contains"` \| `"startswith"` \| `"endswith"` | Yes | Filter operator |
| `value`    | string \| number \| boolean   | Yes      | Filter value |

**How filters are rendered:**

- Multiple filters are joined with `and`.
- String values are single-quoted (embedded quotes are doubled); numbers and booleans are unquoted.
- `contains` becomes `substringof('val',Field)` on V2 and `contains(Field,'val')` on V4; `startswith`/`endswith` become `startswith(Field,'val')` / `endswith(Field,'val')` on both.
- String values that look like an ISO date (`YYYY-MM-DD` or `YYYY-MM-DDTHH:MM[:SS]`) become `datetime'YYYY-MM-DDTHH:MM:SS'` on V2 and stay plain ISO on V4.

**Example Request:**
```json
{
  "name": "sap_nl_query",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER",
    "entitySet": "A_BusinessPartner",
    "filters": [
      { "field": "BusinessPartnerCategory", "operator": "eq", "value": "2" },
      { "field": "BusinessPartnerFullName", "operator": "contains", "value": "SAP" }
    ],
    "select": ["BusinessPartner", "BusinessPartnerFullName"],
    "orderby": "BusinessPartnerFullName asc",
    "top": 10
  }
}
```

**Example Response:**
```json
{
  "version": "v2",
  "generatedFilter": "BusinessPartnerCategory eq '2' and substringof('SAP',BusinessPartnerFullName)",
  "results": [
    { "BusinessPartner": "1000001", "BusinessPartnerFullName": "SAP SE" }
  ],
  "count": 1
}
```

> `generatedFilter` shows the exact `$filter` that was sent (`"(none)"` when `filters` was empty) — useful for debugging the NL interpretation. `count` is the total reported by SAP where available; `nextLink` is present when server-side pagination was capped before all pages were read.
>
> **Note on paging:** unlike `sap_query`, this tool passes `top` and `skip` to SAP as given and applies no default page size of its own. Set `top` explicitly to keep results bounded.
>
> When `--expose` patterns are configured, an entity set outside the patterns is rejected before any SAP call.

---

### OData tools

The `odata` tier is active by default and provides CRUD, function/action calls and batch requests against OData V2 and V4 services. `sap_create`, `sap_update`, `sap_delete`, `sap_function` and `sap_batch` are write tools — without `--allow-write` they are not registered.

---

### sap_read

Read a single entity or entity collection from SAP. Use the `key` parameter for a single entity, omit it for a collection. Supports `$select` and `$expand`.

| Parameter    | Type                         | Required | Description                                                           |
|-------------|------------------------------|----------|-----------------------------------------------------------------------|
| `serviceUrl` | string                       | Yes      | OData service URL                                                     |
| `entitySet`  | string                       | Yes      | Entity set name, e.g., `A_BusinessPartner`                            |
| `key`        | object (string -> any)       | No       | Entity key, e.g., `{ "BusinessPartner": "1000001" }`                  |
| `select`     | string[]                     | No       | Properties to return                                                  |
| `expand`     | string[]                     | No       | Navigation properties to expand                                      |

**Example Request (single entity):**
```json
{
  "name": "sap_read",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER",
    "entitySet": "A_BusinessPartner",
    "key": { "BusinessPartner": "1000001" },
    "select": ["BusinessPartner", "BusinessPartnerFullName", "BusinessPartnerCategory"],
    "expand": ["to_BusinessPartnerAddress"]
  }
}
```

**Example Response (single entity):**
```json
{
  "data": {
    "BusinessPartner": "1000001",
    "BusinessPartnerFullName": "SAP SE",
    "BusinessPartnerCategory": "2",
    "to_BusinessPartnerAddress": [
      {
        "AddressID": "00001",
        "CityName": "Walldorf",
        "Country": "DE"
      }
    ]
  }
}
```

**Example Request (collection):**
```json
{
  "name": "sap_read",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER",
    "entitySet": "A_BusinessPartner",
    "select": ["BusinessPartner", "BusinessPartnerFullName"]
  }
}
```

---

### sap_query

Query SAP entities with filter, sort, and pagination. Returns matching entities with count. Each query option is a separate typed parameter.

| Parameter    | Type     | Required | Description                                                  |
|-------------|----------|----------|--------------------------------------------------------------|
| `serviceUrl` | string   | Yes      | OData service URL                                            |
| `entitySet`  | string   | Yes      | Entity set name                                              |
| `filter`     | string   | No       | OData `$filter` expression, e.g., `"Country eq 'DE'"`       |
| `select`     | string[] | No       | Properties to return                                         |
| `expand`     | string[] | No       | Navigation properties to expand                              |
| `orderby`    | string   | No       | Sort expression, e.g., `"CreationDate desc"`                 |
| `top`        | number   | No       | Maximum number of results. Default **50**, hard cap **1000** |
| `skip`       | number   | No       | Number of results to skip. Use `nextSkip` from the response  |
| `maxPages`   | number   | No       | Maximum pagination pages to follow (default: 10)             |

**Example Request:**
```json
{
  "name": "sap_query",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER",
    "entitySet": "A_BusinessPartner",
    "filter": "BusinessPartnerCategory eq '2' and Country eq 'DE'",
    "select": ["BusinessPartner", "BusinessPartnerFullName", "Country"],
    "orderby": "BusinessPartnerFullName asc",
    "top": 10,
    "expand": ["to_BusinessPartnerAddress"]
  }
}
```

**Example Response:**
```json
{
  "results": [
    {
      "BusinessPartner": "1000001",
      "BusinessPartnerFullName": "SAP SE",
      "Country": "DE",
      "to_BusinessPartnerAddress": [
        { "AddressID": "00001", "CityName": "Walldorf" }
      ]
    }
  ],
  "count": 4200,
  "returned": 10,
  "totalCount": 4200,
  "hasMore": true,
  "nextSkip": 10,
  "top": 10,
  "skip": 0
}
```

> **Paging is mandatory (since 0.2.2).** Omitting `top` applies the default of 50 — an unbounded answer is not expressible, by design. `top` above 1000 is capped. `hasMore` is derived from `totalCount` where SAP reports it; where it does not (many services omit `__count`), a full page counts as a hint that more exists — one `hasMore` too many beats a silently truncated result.
>
> **Partial results:** if the tool time budget expires mid-pagination, the pages read so far are returned with `truncated: true` and a `truncationReason` naming the `skip` value to continue from. See [Time budget](#time-budget-and-cancellation).

---

### sap_create

Create a new entity in SAP. Supports **deep insert**: include nested objects or arrays under navigation property names to create parent and child entities in a single request (e.g., Sales Order with line items).

| Parameter    | Type                   | Required | Description                      |
|-------------|------------------------|----------|----------------------------------|
| `serviceUrl` | string                 | Yes      | OData service URL                |
| `entitySet`  | string                 | Yes      | Entity set name                  |
| `data`       | object (string -> any) | Yes      | Entity data as JSON object       |

**Example Request (simple create):**
```json
{
  "name": "sap_create",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER",
    "entitySet": "A_BusinessPartner",
    "data": {
      "BusinessPartnerCategory": "2",
      "BusinessPartnerFullName": "Test Company GmbH",
      "BusinessPartnerIsBlocked": false
    }
  }
}
```

**Example Response:**
```json
{
  "created": {
    "BusinessPartner": "1000042",
    "BusinessPartnerCategory": "2",
    "BusinessPartnerFullName": "Test Company GmbH",
    "BusinessPartnerIsBlocked": false
  }
}
```

**Example Request (deep insert -- Sales Order with line items):**
```json
{
  "name": "sap_create",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_SALES_ORDER_SRV",
    "entitySet": "A_SalesOrder",
    "data": {
      "SalesOrderType": "OR",
      "SalesOrganization": "1000",
      "DistributionChannel": "10",
      "OrganizationDivision": "00",
      "SoldToParty": "1000001",
      "to_Item": [
        {
          "Material": "MZ-FG-S100",
          "RequestedQuantity": "5",
          "RequestedQuantityUnit": "PC"
        },
        {
          "Material": "MZ-FG-S200",
          "RequestedQuantity": "10",
          "RequestedQuantityUnit": "PC"
        }
      ]
    }
  }
}
```

---

### sap_update

Update an existing SAP entity. Provide the entity key and the fields to update. ETag handling is automatic -- the server manages optimistic concurrency control.

| Parameter    | Type                   | Required | Description                                               |
|-------------|------------------------|----------|-----------------------------------------------------------|
| `serviceUrl` | string                 | Yes      | OData service URL                                         |
| `entitySet`  | string                 | Yes      | Entity set name                                           |
| `key`        | object (string -> any) | Yes      | Entity key, e.g., `{ "BusinessPartner": "1000001" }`     |
| `data`       | object (string -> any) | Yes      | Fields to update as JSON object                           |

**Example Request:**
```json
{
  "name": "sap_update",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER",
    "entitySet": "A_BusinessPartner",
    "key": { "BusinessPartner": "1000001" },
    "data": {
      "BusinessPartnerFullName": "SAP SE (Updated)",
      "SearchTerm1": "SAP"
    }
  }
}
```

**Example Response:**
```json
{
  "updated": true,
  "entitySet": "A_BusinessPartner",
  "key": { "BusinessPartner": "1000001" }
}
```

---

### sap_delete

Delete an entity from SAP. Provide the entity key. ETag handling is automatic.

| Parameter    | Type                   | Required | Description                                               |
|-------------|------------------------|----------|-----------------------------------------------------------|
| `serviceUrl` | string                 | Yes      | OData service URL                                         |
| `entitySet`  | string                 | Yes      | Entity set name                                           |
| `key`        | object (string -> any) | Yes      | Entity key, e.g., `{ "BusinessPartner": "1000001" }`     |

**Example Request:**
```json
{
  "name": "sap_delete",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER",
    "entitySet": "A_BusinessPartner",
    "key": { "BusinessPartner": "1000042" }
  }
}
```

**Example Response:**
```json
{
  "deleted": true,
  "entitySet": "A_BusinessPartner",
  "key": { "BusinessPartner": "1000042" }
}
```

---

### sap_function \**

Invoke an OData V2 Function Import or V4 Action/Function. Supports bound actions (on a specific entity) and unbound actions/functions.

#### Function imports in read-only mode

A function import is not a write operation as such — it can be either. `GetAllOriginals` reads the attachments of an object; `CreateOriginal` creates one. Treating the tool as write-only hid it entirely from read-only connections, and with it the reading path.

So `sap_function` stays visible in read-only mode, and each call is checked against the service metadata instead:

| What the metadata says | Read-only connection |
|---|---|
| V2 `HttpMethod="GET"` | allowed |
| V4 `$Kind: "Function"` | allowed |
| V2 `POST` / V4 `Action` | rejected |
| name not in the metadata | rejected |
| metadata unreachable | rejected |

The proof comes from the metadata, never from the call: `httpMethod` and `isFunction` in the arguments have no bearing on the check — otherwise the guard could be talked out of it. With `--allow-write` no check runs at all.

| Parameter      | Type                   | Required | Description                                                                                     |
|---------------|------------------------|----------|-------------------------------------------------------------------------------------------------|
| `serviceUrl`   | string                 | Yes      | OData service URL                                                                               |
| `functionName` | string                 | Yes      | Function import name (V2) or action/function name (V4). For V4 bound operations, use full namespace, e.g., `com.sap.gateway.srvd.ActionName` |
| `parameters`   | object (string -> any) | No       | Function/action parameters as key-value pairs                                                    |
| `httpMethod`   | `"GET"` or `"POST"`   | No       | HTTP method override. V2: from metadata or defaults to POST. V4: Actions=POST, Functions=GET    |
| `entitySet`    | string                 | No       | Entity set for V4 bound actions/functions                                                        |
| `key`          | object (string -> any) | No       | Entity key for V4 bound actions/functions                                                        |
| `isFunction`   | boolean                | No       | Set `true` for V4 Functions (GET). Default `false` = Action (POST). Ignored for V2.             |

**Example Request (V2 Function Import):**
```json
{
  "name": "sap_function",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_PURCHASEORDER_PROCESS_SRV",
    "functionName": "Release",
    "parameters": {
      "PurchaseOrder": "4500000001"
    }
  }
}
```

**Example Response:**
```json
{
  "PurchaseOrder": "4500000001",
  "PurchaseOrderStatus": "Released"
}
```

**Example Request (V4 Bound Action):**
```json
{
  "name": "sap_function",
  "arguments": {
    "serviceUrl": "/sap/opu/odata4/sap/api_business_partner/srvd_a2x/sap/businesspartner/0001",
    "functionName": "com.sap.gateway.srvd.SetBusinessPartnerBlocked",
    "entitySet": "A_BusinessPartner",
    "key": { "BusinessPartner": "1000001" },
    "parameters": { "IsBlocked": true },
    "isFunction": false
  }
}
```

**Example Request (V4 Unbound Function):**
```json
{
  "name": "sap_function",
  "arguments": {
    "serviceUrl": "/sap/opu/odata4/sap/api_business_partner/srvd_a2x/sap/businesspartner/0001",
    "functionName": "GetNextBusinessPartnerNumber",
    "isFunction": true
  }
}
```

---

### sap_media_upload \*

Upload a file as raw bytes into a SAP media entity — attachments, document images, archive documents. The file name goes out as the `Slug` header, the bytes go into the body, and the answer comes back as JSON.

This runs over the same HTTP client as every other tool, so the certificate chain, the CSRF handshake, the session cookie and the `sap-client` parameter are handled for you. Doing the same thing with a plain HTTP node means rebuilding all four.

| Parameter       | Type                   | Required | Description |
|-----------------|------------------------|----------|-------------|
| `serviceUrl`    | string                 | Yes      | OData service URL |
| `entitySet`     | string                 | Yes      | Entity set name, e.g., `AttachmentContentSet` |
| `contentBase64` | string                 | Yes      | File content, base64-encoded. A `data:` prefix is stripped. |
| `fileName`      | string                 | Yes      | File name; sent as the `Slug` header |
| `contentType`   | string                 | Yes      | Content type of the file, e.g., `application/pdf` |
| `headers`       | object (string -> any) | No       | Additional headers. **Empty values are not sent** — see below. |

**Example Request:**
```json
{
  "name": "sap_media_upload",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_CV_ATTACHMENT_SRV",
    "entitySet": "AttachmentContentSet",
    "contentBase64": "JVBERi0xLjcK...",
    "fileName": "auftragsbestaetigung.pdf",
    "contentType": "application/pdf",
    "headers": {
      "BusinessObjectTypeName": "BUS2032",
      "LinkedSAPObjectKey": "0000012345",
      "DocumentInfoRecordDocType": "PDF"
    }
  }
}
```

**Example Response:**
```json
{
  "uploaded": {
    "status": 201,
    "slug": "auftragsbestaetigung.pdf",
    "bytesSent": 48213,
    "entity": {
      "DocumentInfoRecordDocNumber": "10000042",
      "FileName": "auftragsbestaetigung.pdf",
      "FileSize": "48213",
      "MimeType": "application/pdf"
    }
  }
}
```

**Four things worth knowing:**

1. **Empty headers are omitted, not sent empty.** `"LinkedSAPObjectKey": ""` does not go out as an empty header — the entry is dropped. An empty header makes SAP answer with a message that reads like a missing authorisation and is none.
2. **The object key goes out ten digits wide with leading zeros** (`0000012345`, not `12345`), and `BusinessObjectTypeName` must match the object (`BUS2032` for a sales order). Getting either wrong produces *"User has no authorization for operation 03 on object …"*. SAP KBA 3421507 names both causes; the server repeats both in its error answer.
3. **There is no PATCH.** `API_CV_ATTACHMENT_SRV` reports `updatable: 0` across the whole service. A second upload does not replace anything — it attaches a second document to the same object. Check what is there before repeating an upload.
4. **File names are made header-safe.** HTTP headers are latin1, so `Prüfbericht.pdf` goes out as `Pruefbericht.pdf`. When that happens, the answer carries `slugAdjustedFrom` with the name you passed in.

**Size limit:** the bytes travel base64-encoded inside the JSON-RPC request, because MCP has no binary form for tool *inputs*. The HTTP transport accepts 16 MB of request body by default (roughly a 12 MB file); raise it with `--max-request-bytes` or `SAP_MCP_MAX_REQUEST_BYTES`. Above the limit the server answers `413` as JSON naming the limit.

---

### sap_media_download

Fetch the raw bytes of a media entity over the `$value` path. The bytes come back as an MCP `resource` block with a base64 `blob`, plus a text block with file name, content type and size.

| Parameter          | Type                   | Required | Description |
|--------------------|------------------------|----------|-------------|
| `serviceUrl`       | string                 | Yes      | OData service URL |
| `entitySet`        | string                 | Yes      | Entity set name |
| `key`              | object (string -> any) | Yes      | Entity key |
| `withoutValuePath` | boolean                | No       | Request without the trailing `/$value`. Only needed when the service serves the bytes directly under the entity path. |

**Example Request:**
```json
{
  "name": "sap_media_download",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_CV_ATTACHMENT_SRV",
    "entitySet": "AttachmentContentSet",
    "key": { "DocumentInfoRecordDocNumber": "10000042" }
  }
}
```

**Example Response** (two content blocks):
```json
{
  "content": [
    { "type": "text", "text": "{ \"status\": 200, \"fileName\": \"auftrag.pdf\", \"contentType\": \"application/pdf\", \"bytes\": 48213 }" },
    { "type": "resource", "resource": { "uri": "sap://AttachmentContentSet/auftrag.pdf", "mimeType": "application/pdf", "blob": "JVBERi0xLjcK..." } }
  ]
}
```

This tool reads, so it stays available in the default read-only mode. For the metadata of an attachment (name, size, who created it) `sap_read` on the same entity is enough — no need to move the bytes.

---

### sap_batch

Execute multiple OData operations in a single batch request. Supports V2 (multipart/mixed) and V4 (JSON) batch formats automatically. Operations can be grouped into changesets for transactional behavior. Returns per-operation status — individual failures are always reported, never hidden behind the batch HTTP 200.

| Parameter    | Type   | Required | Description |
|-------------|--------|----------|-------------|
| `serviceUrl` | string | Yes      | OData service URL |
| `operations` | array  | Yes      | Array of operations to execute in batch |

**Operation Object:**

| Field         | Type   | Required | Description |
|--------------|--------|----------|-------------|
| `method`      | `"get"` \| `"post"` \| `"patch"` \| `"delete"` | Yes | HTTP method |
| `entitySet`   | string | Yes      | Entity set name |
| `key`         | object (string -> any) | No | Entity key for read/update/delete |
| `data`        | object (string -> any) | No | Request body for create/update |
| `changesetId` | string | No       | Changeset group ID — operations with the same ID execute as a transaction (all succeed or all fail) |

**Example Request (independent operations):**
```json
{
  "name": "sap_batch",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER",
    "operations": [
      { "method": "get", "entitySet": "A_BusinessPartner", "key": { "BusinessPartner": "1000001" } },
      { "method": "get", "entitySet": "A_BusinessPartner", "key": { "BusinessPartner": "1000002" } }
    ]
  }
}
```

**Example Request (changeset — transactional):**
```json
{
  "name": "sap_batch",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_SALES_ORDER_SRV",
    "operations": [
      { "method": "patch", "entitySet": "A_SalesOrder", "key": { "SalesOrder": "500001" }, "data": { "PurchaseOrderByCustomer": "PO-2026-001" }, "changesetId": "cs1" },
      { "method": "patch", "entitySet": "A_SalesOrder", "key": { "SalesOrder": "500002" }, "data": { "PurchaseOrderByCustomer": "PO-2026-002" }, "changesetId": "cs1" }
    ]
  }
}
```

**Example Response:**
```json
{
  "results": [
    { "status": 200, "entitySet": "A_BusinessPartner", "data": { "BusinessPartner": "1000001", "BusinessPartnerFullName": "SAP AG" } },
    { "status": 200, "entitySet": "A_BusinessPartner", "data": { "BusinessPartner": "1000002", "BusinessPartnerFullName": "Example Corp" } }
  ]
}
```

**Error in batch (per-operation failure):**
```json
{
  "results": [
    { "status": 200, "entitySet": "A_SalesOrder", "data": { "SalesOrder": "500001" } },
    { "status": 400, "entitySet": "A_SalesOrder", "error": "Sales Order 999999 does not exist" }
  ]
}
```

---

### IDoc tools

The four IDoc tools form the `idoc` tier, which is **inactive by default**. Activate it at startup with `--tiers core,odata,idoc` or at runtime with [`sap_enable_tools`](#sap_enable_tools) (`tier: "idoc"`). Either way the tier only becomes available when an IDoc partner configuration is present — at minimum `--sndprn` and `--rcvprn` (`--sndpor`, `--rcvpor`, `--sndprt`, `--rcvprt` are optional). Without it the tools stay hidden and `sap_enable_tools` refuses with an error naming the missing flags.

`sap_idoc_send` is a write tool and additionally requires `--allow-write`. The other three are read-only.

Outbound IDocs go to SAP as XML over HTTP (`POST /sap/bc/idoc_xml`, `Content-Type: text/xml`, `sap-client` appended when configured). Inbound IDocs are received by the webhook endpoint `POST /idoc` (standalone via `--webhook-port` in stdio mode, mounted on the shared HTTP server otherwise) and kept in an in-memory store of the **last 100** IDocs, which `sap_idoc_list_received` reads. The store does not survive a restart.

---

### sap_idoc_send

Send an IDoc to SAP via HTTP/XML. The `EDI_DC40` control record is constructed automatically from the IDoc type and the configured partner profile; per-call overrides are possible. When `metadataServiceUrl` is given, the segments are validated against the IDoc type metadata **before** sending — a validation failure blocks the send.

| Parameter            | Type                       | Required | Description |
|---------------------|----------------------------|----------|-------------|
| `idocType`           | string                     | Yes      | IDoc type name, e.g. `MATMAS05`, `ORDERS05` |
| `segments`           | array of segment objects   | Yes      | IDoc data segments (see below) |
| `metadataServiceUrl` | string                     | No       | OData service URL for IDoc metadata validation. If provided, validates before sending |
| `mesType`            | string                     | No       | Override the auto-derived message type (`MESTYP`) |
| `sndpor`             | string                     | No       | Override sender port |
| `sndprn`             | string                     | No       | Override sender partner number |
| `rcvpor`             | string                     | No       | Override receiver port |
| `rcvprn`             | string                     | No       | Override receiver partner number |

**Segment Object:**

| Field      | Type                       | Required | Description |
|-----------|----------------------------|----------|-------------|
| `name`     | string                     | Yes      | Segment name, e.g. `E1MARAM` |
| `fields`   | object (string -> string)  | Yes      | Segment field values |
| `children` | array of segment objects   | No       | Nested child segments. Nesting is limited to **three levels** (segment → child → grandchild); the schema is deliberately non-recursive because n8n's MCP client cannot resolve `$ref` in JSON Schema |

**Control record defaults:** `TABNAM=EDI_DC40`, `DIRECT=2`, `IDOCTYP` = `idocType`, `MESTYP` = `idocType` with the trailing version digits removed (`MATMAS05` → `MATMAS`) unless `mesType` is given, `SNDPRT`/`RCVPRT` default to `LS`, and `DOCNUM` is generated from a timestamp plus a counter. Partner overrides passed in the call win over the CLI defaults.

**Example Request:**
```json
{
  "name": "sap_idoc_send",
  "arguments": {
    "idocType": "MATMAS05",
    "metadataServiceUrl": "/sap/opu/odata/sap/ZIDOC_METADATA_SRV",
    "segments": [
      {
        "name": "E1MARAM",
        "fields": { "MATNR": "MAT-001", "MTART": "FERT", "MEINS": "PC" },
        "children": [
          { "name": "E1MAKTM", "fields": { "SPRAS": "E", "MAKTX": "Test material" } }
        ]
      }
    ]
  }
}
```

**Example Response (accepted by SAP):**
```json
{
  "success": true,
  "docnum": "1785952000000000",
  "message": "IDoc sent successfully"
}
```

**Example Response (blocked by validation):**
```json
{
  "success": false,
  "docnum": "1785952000000001",
  "message": "Validation failed",
  "violations": [
    {
      "segmentName": "E1MARAM",
      "fieldName": "MATNR",
      "expectedType": "CHAR",
      "expectedLength": 18,
      "actualValue": "THIS-MATERIAL-NUMBER-IS-TOO-LONG",
      "violation": "Field value exceeds max length 18 (actual: 32)"
    }
  ]
}
```

> Validation checks required fields, maximum lengths, `NUMC`/`DATS`/`TIMS` formats, segment `maxOccurrence` and unknown segment names.
>
> `success` reflects SAP's answer: the IDoc counts as accepted when the inbound handler replies with the title `IDoc-XML-inbound ok`; otherwise `message` carries the title of SAP's response (or `IDoc send failed`). A rejected or validation-blocked IDoc is a **normal result with `success: false`**, not an `isError` response — `isError` is reserved for transport and HTTP failures (see [Error responses](#error-responses)). Acceptance means SAP has *received* the IDoc, not that it has been *posted*; use `sap_idoc_status` for that.

---

### sap_idoc_status

Query the processing status of an IDoc in SAP and return the numeric status together with a human-readable description and a category (`success` / `error` / `pending`).

| Parameter          | Type   | Required | Description |
|-------------------|--------|----------|-------------|
| `docnum`           | string | Yes      | IDoc document number |
| `statusServiceUrl` | string | Yes      | OData service URL for the IDoc status query |

The tool reads `{statusServiceUrl}/IdocStatus('{docnum}')` and expects an OData V2 payload whose entity carries `Docnum`, `Status` and optionally `Timestamp` — that is, the status service must expose an `IdocStatus` entity set keyed by document number.

**Example Request:**
```json
{
  "name": "sap_idoc_status",
  "arguments": {
    "docnum": "0000000000123456",
    "statusServiceUrl": "/sap/opu/odata/sap/ZIDOC_STATUS_SRV"
  }
}
```

**Example Response:**
```json
{
  "docnum": "0000000000123456",
  "status": 53,
  "statusText": "Application document posted",
  "category": "success",
  "timestamp": "2026-08-02T10:00:00"
}
```

**Known status codes:**

| Status | Text | Category |
|-------:|------|----------|
| 50 | IDoc added | pending |
| 51 | Application document not posted | error |
| 52 | Application document not fully posted | error |
| 53 | Application document posted | success |
| 56 | IDoc with errors added | error |
| 62 | IDoc passed to application | pending |
| 64 | IDoc ready to be transferred to application | pending |
| 66 | IDoc is waiting for predecessor IDoc (serialization) | pending |
| 68 | Error - no further processing | error |
| 69 | IDoc was edited | pending |
| 73 | IDoc passed to BTP Integration Suite | pending |
| 1 | IDoc generated | pending |
| 3 | IDoc data passed to port OK | success |
| 5 | IDoc translation error | error |
| 12 | Dispatch OK | success |
| 18 | Triggering EDI subsystem OK | success |
| 30 | IDoc ready to be dispatched | pending |

Codes not in this table are returned with `statusText: "Unknown status"` and `category: "pending"`.

---

### sap_idoc_discover

Discover available IDoc types and their segment structures from SAP. Without `idocType` the tool lists all types; with `idocType` it returns the full definition including the segment hierarchy and field metadata — the same metadata `sap_idoc_send` uses for validation.

| Parameter            | Type   | Required | Description |
|---------------------|--------|----------|-------------|
| `metadataServiceUrl` | string | Yes      | OData service URL for IDoc metadata |
| `idocType`           | string | No       | Specific IDoc type to get details for. Omit to list all types |

The tool reads `{metadataServiceUrl}/IdocTypes` (list) or `{metadataServiceUrl}/IdocTypes('{idocType}')?$expand=Segments($expand=Fields)` (details) and expects an OData V2 payload with `IdocType`, `MesType` and, for details, `Segments` (`SegmentName`, `ParentSegment`, `MinOccurrence`, `MaxOccurrence`) with nested `Fields` (`FieldName`, `DataType`, `Length`, `Decimals`, `Required`).

**Example Request (list all types):**
```json
{
  "name": "sap_idoc_discover",
  "arguments": {
    "metadataServiceUrl": "/sap/opu/odata/sap/ZIDOC_METADATA_SRV"
  }
}
```

**Example Response (list all types):**
```json
[
  { "idocType": "MATMAS05", "mesType": "MATMAS" },
  { "idocType": "ORDERS05", "mesType": "ORDERS" }
]
```

**Example Request (single type):**
```json
{
  "name": "sap_idoc_discover",
  "arguments": {
    "metadataServiceUrl": "/sap/opu/odata/sap/ZIDOC_METADATA_SRV",
    "idocType": "MATMAS05"
  }
}
```

**Example Response (single type):**
```json
{
  "idocType": "MATMAS05",
  "mesType": "MATMAS",
  "segments": [
    {
      "name": "E1MARAM",
      "parentSegment": "",
      "minOccurrence": 1,
      "maxOccurrence": 1,
      "fields": [
        { "name": "MATNR", "dataType": "CHAR", "length": 18, "decimals": 0, "required": true },
        { "name": "MTART", "dataType": "CHAR", "length": 4, "decimals": 0, "required": false }
      ]
    },
    {
      "name": "E1MAKTM",
      "parentSegment": "E1MARAM",
      "minOccurrence": 0,
      "maxOccurrence": 999,
      "fields": [
        { "name": "SPRAS", "dataType": "CHAR", "length": 1, "decimals": 0, "required": true },
        { "name": "MAKTX", "dataType": "CHAR", "length": 40, "decimals": 0, "required": false }
      ]
    }
  ]
}
```

> `dataType` is one of `CHAR`, `NUMC`, `DATS`, `TIMS`, `DEC`, `CURR`. Note that the list response is a bare JSON array, not an object.

---

### sap_idoc_list_received

List the IDocs received via the inbound webhook. Returns the contents of the in-memory store — the most recent 100 IDocs, oldest first.

**Parameters:** None

**Example Request:**
```json
{
  "name": "sap_idoc_list_received",
  "arguments": {}
}
```

**Example Response:**
```json
[
  {
    "docnum": "0000000000123456",
    "idocType": "ORDERS05",
    "mesType": "ORDERS",
    "receivedAt": "2026-08-02T10:00:00.000Z"
  }
]
```

> The response is a bare JSON array; an empty store yields `[]`. Only summary fields are listed here — the full parsed payload of a single received IDoc is available through the `idoc://received/{docnum}` resource.

---

### RFC/BAPI tools

The five RFC/BAPI tools form the `rfc` tier, which is **inactive by default**. They talk to SAP through the SAP NetWeaver RFC SDK via the optional `node-rfc` package. Three preconditions must all hold:

1. **`node-rfc` is importable** (SDK installed, `npm install node-rfc`). If it is not, the server logs a warning at startup and the RFC tools are **not registered at all** — they cannot be enabled later in that process.
2. **RFC connection settings** are present in the environment: `SAP_USERNAME` and `SAP_PASSWORD` plus either `SAP_RFC_ASHOST` + `SAP_RFC_SYSNR` (direct application server) or `SAP_RFC_MSHOST` + `SAP_RFC_GROUP` (logon group; `SAP_RFC_MSSERV` optional). `SAP_CLIENT` and `SAP_RFC_LANG` (default `EN`) are passed along; SNC is configured with `SAP_SNC_QOP`, `SAP_SNC_MYNAME`, `SAP_SNC_PARTNERNAME` and `SAP_SNC_LIB` (all-or-none). Without these the tier stays hidden and `sap_enable_tools` refuses with an error.
3. **The tier is active** — via `--tiers core,odata,rfc` at startup or `sap_enable_tools` (`tier: "rfc"`) at runtime.

`sap_rfc_call`, `sap_bapi_call` and `sap_bapi_commit` are write tools and additionally require `--allow-write`; `sap_rfc_metadata` and `sap_rfc_search_functions` are read-only.

**Common behaviour:**

- Function module names are folded to uppercase before the call, as SAP does.
- Parameters and results use ABAP-uppercase keys and node-rfc's default type mapping: `DATS`, `TIMS`, `NUMC` and decimal types (`BCD`, `CURR`, `QUAN`) arrive as strings (`'20260427'`, `'143052'`, `'1234.56'`), integers and floats as numbers, `RAW`/`XSTRING` as Buffers, tables as arrays and structures as objects. No date/decimal conversion is applied on purpose — converting large currencies to JS numbers would silently truncate them.
- **Errors** are reported with `isError: true` and a shape that differs slightly from the OData tools: `{ "code": "...", "message": "...", "details": [...] }`. `code` is the RFC library code (`RFC_COMMUNICATION_FAILURE`, `RFC_LOGON_FAILURE`, `RFC_TIMEOUT`, `RFC_INVALID_HANDLE`, `RFC_CLOSED`, `RFC_AUTHORIZATION_FAILURE`, `RFC_AUTHENTICATION_FAILURE`, `RFC_CRYPTOLIB_FAILURE`, `RFC_IO_FAILURE`), `ABAP_MESSAGE:<class>:<number>` for an ABAP `MESSAGE` statement (with the message as a `details` entry), `ABAP_CLASSIC:<exception>` for a classic exception, `ABAP_CLASS:<cx-class>` for a class-based exception, `RFC_EXTERNAL_RUNTIME` for runtime/native failures, or `UNKNOWN_RFC`. An expired BAPI session answers `{ "code": "SESSION_NOT_FOUND", "message": "...", "sessionId": "..." }`.

---

### sap_rfc_call

Invoke any RFC-enabled function module on a **stateless** connection. Use it for custom `Z_*` modules and read-only helpers such as `RFC_READ_TABLE`. It cannot take part in a BAPI commit transaction — if you intend to call `BAPI_TRANSACTION_COMMIT` afterwards, use `sap_bapi_call` instead. The function module must be flagged Remote-Enabled (SE37).

| Parameter        | Type                   | Required | Description |
|-----------------|------------------------|----------|-------------|
| `functionModule` | string                 | Yes      | Function module name, e.g. `RFC_PING`, `RFC_READ_TABLE`, `Z_CUSTOM_FM` |
| `parameters`     | object (string -> any) | No       | IMPORT/CHANGING/TABLES parameters with ABAP-uppercase keys, e.g. `{ "QUERY_TABLE": "T001", "ROWCOUNT": 10 }` |

**Example Request:**
```json
{
  "name": "sap_rfc_call",
  "arguments": {
    "functionModule": "RFC_READ_TABLE",
    "parameters": {
      "QUERY_TABLE": "T001",
      "DELIMITER": "|",
      "ROWCOUNT": 2,
      "FIELDS": [{ "FIELDNAME": "BUKRS" }, { "FIELDNAME": "BUTXT" }]
    }
  }
}
```

**Example Response:**
```json
{
  "DATA": [
    { "WA": "1000|Company Code 1000" },
    { "WA": "2000|Company Code 2000" }
  ],
  "FIELDS": [
    { "FIELDNAME": "BUKRS", "OFFSET": "000000", "LENGTH": "000004", "TYPE": "C", "FIELDTEXT": "Company Code" },
    { "FIELDNAME": "BUTXT", "OFFSET": "000004", "LENGTH": "000025", "TYPE": "C", "FIELDTEXT": "Name of Company Code or Company" }
  ],
  "OPTIONS": []
}
```

> The response is the raw output of the function module as returned by node-rfc — EXPORT and TABLES parameters with UPPERCASE keys, no reshaping.

---

### sap_rfc_metadata

Retrieve the interface (IMPORT / EXPORT / CHANGING / TABLES / EXCEPTIONS) of an RFC-enabled function module via `RFC_GET_FUNCTION_INTERFACE`. Use it before calling an unfamiliar RFC or BAPI to learn required vs. optional parameters, ABAP types and DDIC references. To find function modules by name pattern, use `sap_rfc_search_functions`.

| Parameter        | Type   | Required | Description |
|-----------------|--------|----------|-------------|
| `functionModule` | string | Yes      | Function module name, e.g. `BAPI_USER_GET_DETAIL` |
| `language`       | string | No       | Single-character language key for parameter texts (default: server configuration) |

**Example Request:**
```json
{
  "name": "sap_rfc_metadata",
  "arguments": {
    "functionModule": "BAPI_USER_GET_DETAIL"
  }
}
```

**Example Response:**
```json
{
  "name": "BAPI_USER_GET_DETAIL",
  "remoteEnabled": true,
  "updateTask": false,
  "parameters": [
    {
      "name": "USERNAME",
      "direction": "IMPORT",
      "type": "C",
      "length": 12,
      "optional": false,
      "text": "User Name",
      "ddicReference": "BAPIBNAME-BAPIBNAME"
    },
    {
      "name": "RETURN",
      "direction": "TABLES",
      "type": "u",
      "length": 548,
      "optional": true,
      "ddicReference": "BAPIRET2"
    }
  ]
}
```

**Parameter Object:**

| Field           | Type    | Description |
|----------------|---------|-------------|
| `name`          | string  | Parameter name |
| `direction`     | `"IMPORT"` \| `"EXPORT"` \| `"CHANGING"` \| `"TABLES"` \| `"EXCEPTION"` | Mapped from `PARAMCLASS` (I/E/C/T/X) |
| `type`          | string  | ABAP type id (`EXID`), e.g. `C`, `N`, `D`, `T`, `P`, `F`, `I`, `X` |
| `length`        | number  | Internal length |
| `decimals`      | number  | Decimals, when given |
| `optional`      | boolean | `true` when the parameter is optional |
| `default`       | string  | Default value, when given |
| `text`          | string  | Parameter short text, when given |
| `ddicReference` | string  | `TABNAME-FIELDNAME` (or just the table name) when the parameter references the dictionary |

---

### sap_bapi_call

Invoke a BAPI on a **stateful** connection. The response carries a `sessionId`; pass it to further `sap_bapi_call` invocations to chain BAPIs on the same connection, and finally to `sap_bapi_commit`. Use this for `BAPI_*_CREATE*` / `BAPI_*_CHANGE*` and whatever else must be followed by `BAPI_TRANSACTION_COMMIT`. For read-only function modules and `RFC_*` helpers, `sap_rfc_call` is cheaper.

| Parameter    | Type                   | Required | Description |
|-------------|------------------------|----------|-------------|
| `bapi`       | string                 | Yes      | BAPI function module name, e.g. `BAPI_USER_GET_DETAIL` |
| `parameters` | object (string -> any) | No       | BAPI input parameters with ABAP-uppercase keys |
| `sessionId`  | string (UUID)          | No       | Continue an existing session from a previous `sap_bapi_call`. Omit on the first call to open a new session |

**Example Request:**
```json
{
  "name": "sap_bapi_call",
  "arguments": {
    "bapi": "BAPI_SALESORDER_CREATEFROMDAT2",
    "parameters": {
      "ORDER_HEADER_IN": { "DOC_TYPE": "OR", "SALES_ORG": "1000", "DISTR_CHAN": "10", "DIVISION": "00" },
      "ORDER_PARTNERS": [{ "PARTN_ROLE": "AG", "PARTN_NUMB": "0001000001" }],
      "ORDER_ITEMS_IN": [{ "ITM_NUMBER": "000010", "MATERIAL": "MZ-FG-S100", "REQ_QTY": "5" }]
    }
  }
}
```

**Example Response:**
```json
{
  "sessionId": "5f1c2a4e-9d3b-4c7a-8e21-0b6f3d9a1c55",
  "return": [
    {
      "type": "S",
      "id": "V1",
      "number": "311",
      "message": "Standard Order 12345 has been saved",
      "messageV1": "Standard Order",
      "messageV2": "12345"
    }
  ],
  "hasErrors": false,
  "errorCount": 0,
  "warningCount": 0,
  "exports": {
    "SALESDOCUMENT": "0000012345"
  },
  "tables": {
    "ORDER_ITEMS_OUT": [
      { "ITM_NUMBER": "000010", "MATERIAL": "MZ-FG-S100", "REQ_QTY": "5.000" }
    ]
  }
}
```

**Response fields:**

| Field          | Description |
|---------------|-------------|
| `sessionId`    | The stateful session — reuse it for follow-up calls and for `sap_bapi_commit` |
| `return`       | The BAPI's `RETURN` (or `E_RETURN`) table parsed into `BAPIRET2` messages with camelCase keys: `type` (`S`/`I`/`W`/`E`/`A`), `id`, `number`, `message`, `messageV1`–`messageV4`, `parameter`, `row`, `field`, `system`, `logNo`, `logMsgNo` |
| `hasErrors`    | `true` when any message has type `E` or `A` |
| `errorCount`, `warningCount` | Counts of `E`/`A` and `W` messages |
| `exports`      | All other scalar and structure output parameters |
| `tables`       | All other table (array) output parameters |

> **`hasErrors: true` is not `isError: true`.** The RFC call itself succeeded; SAP merely reported application errors. Do **not** call `sap_bapi_commit` in that case — either call `sap_bapi_call` again with corrected parameters (reusing `sessionId`) or let the session idle out. A stateful session is released automatically after **60 seconds** without activity, which is an implicit rollback: nothing is written to SAP until `BAPI_TRANSACTION_COMMIT` runs. Every call on the session resets the timer. Using an expired or unknown `sessionId` yields `SESSION_NOT_FOUND` (`isError: true`) — start over with a fresh `sap_bapi_call`.

---

### sap_bapi_commit

Call `BAPI_TRANSACTION_COMMIT` on the **same** stateful connection used by a prior `sap_bapi_call`, then release the session. Only commit when the preceding calls returned `hasErrors: false`; committing a session with errors would persist a faulty state. `sap_rfc_call` cannot participate — it is stateless.

| Parameter   | Type          | Required | Description |
|------------|---------------|----------|-------------|
| `sessionId` | string (UUID) | Yes      | Session id from a prior `sap_bapi_call` |
| `wait`      | boolean       | No       | Default **`true`**: pass `WAIT=X` and wait for the ABAP update task to complete. `false` is fire-and-forget — failures are then only visible in SM58/SM37 |

**Example Request:**
```json
{
  "name": "sap_bapi_commit",
  "arguments": {
    "sessionId": "5f1c2a4e-9d3b-4c7a-8e21-0b6f3d9a1c55"
  }
}
```

**Example Response:**
```json
{
  "sessionId": "5f1c2a4e-9d3b-4c7a-8e21-0b6f3d9a1c55",
  "return": [],
  "committed": true
}
```

> `committed` is `true` when `BAPI_TRANSACTION_COMMIT` returned no `E`/`A` messages; `return` carries whatever messages it did return. The session is released either way — a second commit on the same `sessionId` answers `SESSION_NOT_FOUND`.

---

### sap_rfc_search_functions

Search for function modules by name pattern via `RFC_FUNCTION_SEARCH`. Use it to discover BAPIs and function modules by partial name; to inspect the interface of a known module, use `sap_rfc_metadata`.

| Parameter   | Type   | Required | Description |
|------------|--------|----------|-------------|
| `pattern`   | string | Yes      | Name pattern with SAP wildcards: `*` matches any sequence, `+` matches a single character (not glob syntax). Examples: `BAPI_USER_*`, `Z_*`, `+MATERIAL+` |
| `groupName` | string | No       | Function group filter, e.g. `SU05` |
| `limit`     | number | No       | Maximum hits to return. Default **100**; positive integer. Excess rows are truncated |

**Example Request:**
```json
{
  "name": "sap_rfc_search_functions",
  "arguments": {
    "pattern": "BAPI_USER_*",
    "limit": 3
  }
}
```

**Example Response:**
```json
{
  "functions": [
    { "name": "BAPI_USER_ACTGROUPS_ASSIGN", "groupName": "SU_USER", "shortText": "Change Role Assignments of a User" },
    { "name": "BAPI_USER_CHANGE", "groupName": "SU_USER", "shortText": "Change User" },
    { "name": "BAPI_USER_CREATE1", "groupName": "SU_USER", "shortText": "Create a User" }
  ],
  "total": 42,
  "truncated": true
}
```

> Pattern and group name are folded to uppercase. `total` is the number of rows SAP returned; `truncated: true` appears when that exceeds `limit`. SAP returns the search result unpaginated, so a very broad pattern (`*`) puts load on the backend regardless of `limit`.

---

### Meta tool

One tool manages the tiers themselves.

---

### sap_enable_tools

Activate an additional tool tier for the current session. Lets an agent that starts with `core` + `odata` switch on `idoc` or `rfc` on demand, without a server restart. The tool description lists which tiers are currently active and which can still be activated.

> **Not available in read-only mode:** without `--allow-write` this tool is not registered at all, so tiers can then only be chosen with `--tiers` at startup. Enabling a tier never bypasses read-only mode or a per-token policy: write tools stay hidden, and tiers outside a token's `tiers` ceiling cannot be enabled.

| Parameter | Type   | Required | Description |
|----------|--------|----------|-------------|
| `tier`    | `"core"` \| `"odata"` \| `"idoc"` \| `"rfc"` | Yes | Tier to activate. Use `idoc` for the IDoc tools, `rfc` for the RFC/BAPI tools |

**Example Request:**
```json
{
  "name": "sap_enable_tools",
  "arguments": {
    "tier": "idoc"
  }
}
```

**Example Response:**
```json
{
  "status": "success",
  "tier_enabled": "idoc",
  "enabled_tools": ["sap_idoc_send", "sap_idoc_status", "sap_idoc_discover", "sap_idoc_list_received"],
  "active_tiers": ["core", "odata", "idoc"],
  "note": "Tools enabled. If your client did not refresh the tool list automatically, you may need to reconnect."
}
```

**Example Response (precondition missing):**
```json
{
  "status": "error",
  "message": "Cannot enable IDoc tier: no IDoc partner configuration provided (--sndprn, --rcvprn required)"
}
```

> The server announces `tools.listChanged`, so a compliant client refreshes its tool list after a successful call. Preconditions that produce `status: "error"` (`isError: true`): the IDoc tier without `--sndprn`/`--rcvprn`; the RFC tier without `SAP_RFC_ASHOST` + `SAP_RFC_SYSNR` (or `SAP_RFC_MSHOST` + `SAP_RFC_GROUP`); a tier outside the token policy of the connection. Enabling an already active tier is harmless. `enabled_tools` lists only the tools that actually became visible — RFC tools that were never registered (no `node-rfc`) cannot appear, so `tier: "rfc"` may succeed with an empty list on a host without the SDK.

---

## Cross-cutting behaviour

These rules apply to **every** tool listed above.

### Error responses

No tool answers with `"Unknown error"`. Every failure is reduced to what is actually known and what to do about it:

```json
{
  "code": "SERVICE_NOT_REGISTERED",
  "error": "Service /sap/opu/odata/sap/API_SALES_ORDER_SRV ist im Gateway nicht registriert.",
  "httpStatus": 403,
  "sapCode": "/IWFND/MED/170",
  "guidance": "Aktivierung in Transaktion /IWFND/MAINT_SERVICE nötig. Das ist kein Berechtigungsproblem — PFCG und SU53 führen hier nicht weiter.",
  "correlationId": "a3f19c8b2d04"
}
```

| Field | Meaning |
|---|---|
| `code` | Classification, e.g. `SERVICE_NOT_REGISTERED`, `AUTH_FAILED`, `TLS_CHAIN_INCOMPLETE`, `INVALID_INPUT`, `TOOL_TIMEOUT`, `ABORTED` |
| `error` | Plain-language cause. Never raw HTML — SAP error pages are reduced to their essence |
| `httpStatus` | Present when SAP answered with a status |
| `sapCode` | SAP's own error code when one was found in the response |
| `guidance` | The next sensible action. Absent when there is nothing reliable to suggest |
| `correlationId` | Ties the response to the log lines of the same call (see below) |

Notable translations, each backed by a test with a recorded SAP response:

- **`/IWFND/MED/170`** → the service is not registered in the Gateway. SAP answers `403`, but this is *not* an authorization problem; the guidance says so explicitly, because looking in PFCG costs an hour.
- **`401` with an HTML logon page** → asks whether `sap-client` is set. Without it the Gateway rejects the logon in a way that looks like a wrong password.
- **`UNABLE_TO_GET_ISSUER_CERT_LOCALLY`** → points at `NODE_EXTRA_CA_CERTS` and names the issuing CA. `SAP_TLS_VERIFY=false` is explicitly ruled out as a fix — it disables the check rather than solving it.

`serviceUrl` accepts a path, an absolute URL, or the plain technical name (`API_SALES_ORDER_SRV`). An unusable value is rejected **before** any SAP call, with an example of the expected form.

The RFC/BAPI tools do not go through HTTP and therefore use a slightly different error shape (`code`, `message`, `details`) — see [RFC/BAPI tools](#rfcbapi-tools). The time budget, cancellation and correlation rules below apply to them unchanged.

### Time budget and cancellation

Every tool call runs under a time budget (`--tool-timeout`, default 30 s). When it expires the client receives a valid MCP response — never a hanging connection:

```json
{
  "truncated": true,
  "reason": "Zeitbudget von 30 s überschritten — der Aufruf wurde abgebrochen, damit die Verbindung nicht hängen bleibt.",
  "hint": "Grenzen Sie die Anfrage ein (top/skip, filter, search) oder erhöhen Sie --tool-timeout. …",
  "tool": "sap_query",
  "correlationId": "a3f19c8b2d04",
  "elapsedMs": 30004,
  "sapCalls": 7
}
```

Paginated reads are gentler: they return the pages fetched so far, with `truncated: true` and a `truncationReason` naming the `skip` value to continue from.

If the client drops the connection, outbound SAP requests stop within a second — a production ERP should not keep serving requests whose result nobody will read.

### Progress on long calls

When a call runs longer than 5 seconds and the client supplied a `progressToken`, the server emits `notifications/progress` with elapsed seconds, the budget as `total`, and a message naming the tool and how many SAP requests it has made so far. Without a token nothing is sent — the MCP specification asks for that.

### Correlating a call with the log

Every tool call emits one log line on completion, and every SAP request it triggered carries the same id:

```json
{"correlationId":"a3f19c8b2d04","tool":"sap_discover_services","outcome":"ok","durationMs":842,"sapCalls":1,"resultBytes":18422}
```

`outcome` is `ok`, `error`, `timeout` (budget expired) or `aborted` (client disconnected). A single `grep` on the id shows everything one call did — including how many SAP requests it produced.

---

## Resources

### sap://metadata/{serviceUrl}

Browse parsed metadata for an SAP OData service as a structured JSON resource.

**URI Template:** `sap://metadata/{serviceUrl}`

The `{serviceUrl}` is URL-encoded in the URI, e.g., `sap://metadata/%2Fsap%2Fopu%2Fodata%2Fsap%2FAPI_BUSINESS_PARTNER`.

**Description:** Returns entity types, properties, keys, navigation properties, and entity sets for the given OData service. Metadata is cached per session -- subsequent reads for the same service are instant.

**MIME Type:** `application/json`

**Example Response:**
```json
{
  "version": "v2",
  "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER",
  "entityTypes": [
    {
      "name": "A_BusinessPartnerType",
      "keys": [{ "name": "BusinessPartner" }],
      "properties": [
        { "name": "BusinessPartner", "type": "Edm.String" },
        { "name": "BusinessPartnerFullName", "type": "Edm.String" },
        { "name": "BusinessPartnerCategory", "type": "Edm.String" }
      ],
      "navigationProperties": [
        { "name": "to_BusinessPartnerAddress", "target": "A_BusinessPartnerAddress" }
      ]
    }
  ],
  "entitySets": [
    { "name": "A_BusinessPartner", "entityType": "A_BusinessPartnerType" }
  ]
}
```

---

## Prompts

Prompts are pre-built conversation starters that guide LLMs through common SAP workflows using the progressive discovery pattern.

### explore-sales-orders

Discover and query SAP Sales Order data step by step.

| Argument     | Type   | Required | Description                                          |
|-------------|--------|----------|------------------------------------------------------|
| `serviceUrl` | string | No       | OData service URL (leave empty to discover first)    |

**What it guides you through:**

1. Discover available entity sets (using `sap_list_services`)
2. Inspect the Sales Order data model (using `sap_get_metadata`)
3. Query sales orders with key fields (SalesOrder, SalesOrganization, SoldToParty)
4. Summarize the data model and results

If no `serviceUrl` is provided, it suggests the common Sales Order service URL: `/sap/opu/odata/sap/API_SALES_ORDER_SRV`.

---

### check-material-availability

Look up material master data and check availability in SAP.

| Argument         | Type   | Required | Description                                     |
|-----------------|--------|----------|-------------------------------------------------|
| `materialNumber` | string | No       | SAP Material Number (leave empty to search)     |

**What it guides you through:**

1. Find the material master service (`/sap/opu/odata/sap/API_PRODUCT_SRV`)
2. Discover material-related entity sets
3. Inspect the material entity type metadata
4. Look up or browse materials
5. Display material details (description, type, unit of measure, availability)

---

### manage-business-partners

Create, read, and update Business Partners in SAP.

| Argument     | Type                            | Required | Description                                        |
|-------------|----------------------------------|----------|----------------------------------------------------|
| `serviceUrl` | string                          | No       | OData service URL (leave empty to discover first)  |
| `action`     | `"list"`, `"create"`, `"search"` | No       | What to do with Business Partners                  |

**What it guides you through:**

1. Find the Business Partner service (`/sap/opu/odata/sap/API_BUSINESS_PARTNER`)
2. Discover entity sets
3. Inspect the Business Partner data model
4. Perform the selected action:
   - **list**: Fetch Business Partners with key fields
   - **create**: Understand required fields, create a new Business Partner, verify creation
   - **search**: Query with filters (by name, city, or category)
