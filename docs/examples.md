# Examples

Practical examples for common SAP workflows using the MCP Server. Each example follows the progressive discovery pattern: **discover services** -> **inspect metadata** -> **execute operations**.

## Reading Business Partners

### Step 1: Discover Available Entity Sets

```json
{
  "name": "sap_list_services",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER"
  }
}
```

Response shows entity sets like `A_BusinessPartner`, `A_BusinessPartnerAddress`, `A_BusinessPartnerBank`, etc., plus `totalCount` and `hasMore` — the list is paged at 50 entries by default.

`serviceUrl` also accepts the plain technical name (`API_BUSINESS_PARTNER`) or an absolute URL. That matters because `sap_discover_services` returns the technical name as `technicalName`, and passing it straight through should just work.

### Step 2: Inspect the Data Model

```json
{
  "name": "sap_get_metadata",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER",
    "entityType": "A_BusinessPartnerType"
  }
}
```

This reveals the key fields (`BusinessPartner`), properties (name, category, country), and navigation properties (addresses, bank accounts, roles).

### Step 3: Query Business Partners

```json
{
  "name": "sap_query",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER",
    "entitySet": "A_BusinessPartner",
    "filter": "BusinessPartnerCategory eq '2'",
    "select": ["BusinessPartner", "BusinessPartnerFullName", "BusinessPartnerCategory", "SearchTerm1"],
    "orderby": "BusinessPartnerFullName asc",
    "top": 5
  }
}
```

The response carries the paging state alongside the data:

```json
{
  "results": [ /* 5 business partners */ ],
  "count": 4200,
  "returned": 5,
  "totalCount": 4200,
  "hasMore": true,
  "nextSkip": 5,
  "top": 5,
  "skip": 0
}
```

### Step 3b: Page Through the Rest

Omitting `top` does **not** return everything — it applies the default of 50. To walk a large result set, feed `nextSkip` back as `skip` until `hasMore` is `false`:

```json
{
  "name": "sap_query",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER",
    "entitySet": "A_BusinessPartner",
    "filter": "BusinessPartnerCategory eq '2'",
    "orderby": "BusinessPartnerFullName asc",
    "top": 5,
    "skip": 5
  }
}
```

> Always pair paging with a stable `orderby`. Without one, SAP does not guarantee a consistent order across pages, and records can be seen twice or skipped.
>
> If a response comes back with `truncated: true`, the tool time budget expired mid-pagination. The `truncationReason` names the `skip` value to continue from — the data already read is valid.

### Step 4: Read a Single Business Partner with Details

```json
{
  "name": "sap_read",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER",
    "entitySet": "A_BusinessPartner",
    "key": { "BusinessPartner": "1000001" },
    "select": ["BusinessPartner", "BusinessPartnerFullName", "BusinessPartnerCategory"],
    "expand": ["to_BusinessPartnerAddress", "to_BusinessPartnerRole"]
  }
}
```

---

## Creating a Sales Order with Line Items (Deep Insert)

Deep insert creates a parent entity and its child entities in a single request. This is useful for Sales Orders with line items, where both must be created together.

### Step 1: Discover the Sales Order Service

```json
{
  "name": "sap_list_services",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_SALES_ORDER_SRV"
  }
}
```

### Step 2: Inspect Sales Order Metadata

```json
{
  "name": "sap_get_metadata",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_SALES_ORDER_SRV",
    "entityType": "A_SalesOrderType"
  }
}
```

Look for navigation properties like `to_Item` that link to `A_SalesOrderItem`.

### Step 3: Create Sales Order with Line Items

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
      "PurchaseOrderByCustomer": "PO-2026-001",
      "to_Item": [
        {
          "Material": "MZ-FG-S100",
          "RequestedQuantity": "5",
          "RequestedQuantityUnit": "PC",
          "NetAmount": "500.00",
          "TransactionCurrency": "EUR"
        },
        {
          "Material": "MZ-FG-S200",
          "RequestedQuantity": "10",
          "RequestedQuantityUnit": "PC",
          "NetAmount": "1200.00",
          "TransactionCurrency": "EUR"
        }
      ]
    }
  }
}
```

The deep insert creates the Sales Order header and both line items in a single atomic request. SAP assigns the `SalesOrder` number and `SalesOrderItem` numbers automatically.

---

## Calling Function Imports

### V2: Release a Purchase Order

Function imports in V2 are operations that go beyond standard CRUD. They typically trigger SAP business logic.

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

V2 function imports default to HTTP POST for safety. Use `httpMethod: "GET"` if the function import is read-only.

### V4: Bound Action on a Business Partner

Bound actions operate on a specific entity instance:

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

### V4: Unbound Function

Unbound functions are standalone operations not tied to a specific entity:

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

Note: `isFunction: true` means this is a V4 Function (uses GET). The default `false` means it is a V4 Action (uses POST).

---

## Using MCP Prompts

MCP Prompts are pre-built conversation starters that guide an LLM through a specific workflow. They are particularly useful for getting started with SAP data exploration.

### Explore Sales Orders

Invoke the `explore-sales-orders` prompt to walk through discovering and querying Sales Order data:

```json
{
  "prompt": "explore-sales-orders",
  "arguments": {}
}
```

The prompt guides the LLM through:
1. Discovering the Sales Order service
2. Listing available entity sets
3. Inspecting the Sales Order metadata
4. Querying sample sales orders with key fields
5. Summarizing the data model

You can also provide a service URL if you already know it:

```json
{
  "prompt": "explore-sales-orders",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_SALES_ORDER_SRV"
  }
}
```

### Manage Business Partners

The `manage-business-partners` prompt supports three actions:

**List Business Partners:**
```json
{
  "prompt": "manage-business-partners",
  "arguments": {
    "action": "list"
  }
}
```

**Search for Business Partners:**
```json
{
  "prompt": "manage-business-partners",
  "arguments": {
    "action": "search"
  }
}
```

**Create a Business Partner:**
```json
{
  "prompt": "manage-business-partners",
  "arguments": {
    "action": "create"
  }
}
```

---

## Batch Operations

### Multiple Reads in One Request

Read several business partners in a single batch call instead of multiple individual requests:

```json
{
  "name": "sap_batch",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER",
    "operations": [
      { "method": "get", "entitySet": "A_BusinessPartner", "key": { "BusinessPartner": "1000001" } },
      { "method": "get", "entitySet": "A_BusinessPartner", "key": { "BusinessPartner": "1000002" } },
      { "method": "get", "entitySet": "A_BusinessPartner", "key": { "BusinessPartner": "1000003" } }
    ]
  }
}
```

### Transactional Updates with Changesets

Update multiple sales orders atomically — if any update fails, all are rolled back:

```json
{
  "name": "sap_batch",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_SALES_ORDER_SRV",
    "operations": [
      {
        "method": "patch",
        "entitySet": "A_SalesOrder",
        "key": { "SalesOrder": "500001" },
        "data": { "OverallSDProcessStatus": "C" },
        "changesetId": "close-orders"
      },
      {
        "method": "patch",
        "entitySet": "A_SalesOrder",
        "key": { "SalesOrder": "500002" },
        "data": { "OverallSDProcessStatus": "C" },
        "changesetId": "close-orders"
      }
    ]
  }
}
```

### Mixed Operations (Read + Write)

Combine reads and writes in one batch. GET operations outside changesets, writes inside:

```json
{
  "name": "sap_batch",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_SALES_ORDER_SRV",
    "operations": [
      { "method": "get", "entitySet": "A_SalesOrder", "key": { "SalesOrder": "500001" } },
      {
        "method": "post",
        "entitySet": "A_SalesOrderItem",
        "data": { "SalesOrder": "500001", "Material": "MAT-001", "RequestedQuantity": 10 },
        "changesetId": "add-items"
      }
    ]
  }
}
```

Each operation returns its own status — a failing write does not hide a successful read:

```json
{
  "results": [
    { "status": 200, "entitySet": "A_SalesOrder", "data": { "SalesOrder": "500001", "SoldToParty": "1000001" } },
    { "status": 201, "entitySet": "A_SalesOrderItem", "data": { "SalesOrder": "500001", "SalesOrderItem": "10", "Material": "MAT-001" } }
  ]
}
```

---

## Selective Entity Set Exposure

The `--expose` CLI option restricts which entity sets are visible to the LLM, which is useful for security and reducing noise.

### Example: Expose Only Business Partner and Sales Order Entities

```bash
sap-mcp-server --expose 'A_BusinessPartner*,A_SalesOrder*'
```

### What the LLM Sees

With this configuration, calling `sap_list_services`:

```json
{
  "name": "sap_list_services",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER"
  }
}
```

Returns only matching entity sets:

```json
{
  "serviceUrl": "/sap/opu/odata/sap/API_BUSINESS_PARTNER",
  "entitySets": [
    "A_BusinessPartner",
    "A_BusinessPartnerAddress",
    "A_BusinessPartnerBank",
    "A_BusinessPartnerContact"
  ],
  "count": 4
}
```

Entity sets like `A_Customer`, `A_Supplier` are hidden since they do not match the patterns.

### What Happens When Accessing Non-Exposed Entity Sets

Attempting to use a CRUD operation on a non-exposed entity set returns an error:

```json
{
  "error": "Entity set 'A_Customer' is not exposed. Configure --expose to include it."
}
```

### Pattern Matching Reference

| Pattern              | Matches                                  | Does Not Match           |
|---------------------|------------------------------------------|--------------------------|
| `A_BusinessPartner`  | `A_BusinessPartner` only                 | `A_BusinessPartnerAddress` |
| `A_BusinessPartner*` | `A_BusinessPartner`, `A_BusinessPartnerAddress`, `A_BusinessPartnerBank` | `A_Customer` |
| `*Order*`            | `A_SalesOrder`, `A_SalesOrderItem`, `A_PurchaseOrderItem` | `A_BusinessPartner` |
| `A_Sales*,A_Business*` | All Sales and Business entity sets     | `A_Customer`, `A_Supplier` |

---

## Attaching a PDF to a Sales Order

A document attached to a SAP object goes through `API_CV_ATTACHMENT_SRV`. The file travels as raw bytes; everything that identifies the object travels as headers.

### Step 1: Upload the File

```json
{
  "name": "sap_media_upload",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_CV_ATTACHMENT_SRV",
    "entitySet": "AttachmentContentSet",
    "contentBase64": "JVBERi0xLjcKJeLjz9MK...",
    "fileName": "auftragsbestaetigung-4711.pdf",
    "contentType": "application/pdf",
    "headers": {
      "BusinessObjectTypeName": "BUS2032",
      "LinkedSAPObjectKey": "0000004711",
      "DocumentInfoRecordDocType": "PDF"
    }
  }
}
```

Two details decide whether this works:

- `LinkedSAPObjectKey` is **ten digits with leading zeros**. Sales order 4711 is `0000004711`.
- `BusinessObjectTypeName` must match the object. A sales order is `BUS2032`.

Get either wrong and SAP answers *"User has no authorization for operation 03 on object …"* — which is not about authorisations. The server's error answer names both causes.

**Response:**

```json
{
  "uploaded": {
    "status": 201,
    "slug": "auftragsbestaetigung-4711.pdf",
    "bytesSent": 48213,
    "entity": {
      "DocumentInfoRecordDocNumber": "10000042",
      "FileName": "auftragsbestaetigung-4711.pdf",
      "FileSize": "48213",
      "MimeType": "application/pdf"
    }
  }
}
```

### Step 2: Read It Back Instead of Trusting the Status Code

`201` says SAP accepted the request. Whether the attachment hangs on the right object is a different question — ask it:

```json
{
  "name": "sap_function",
  "arguments": {
    "serviceUrl": "/sap/opu/odata/sap/API_CV_ATTACHMENT_SRV",
    "functionName": "GetAllOriginals",
    "parameters": {
      "BusinessObjectTypeName": "BUS2032",
      "LinkedSAPObjectKey": "0000004711"
    }
  }
}
```

This is a reading function import, so it works on a read-only connection too — see [Function imports in read-only mode](api-reference.md#function-imports-in-read-only-mode).

Note the asymmetry: on the **writing** call above, `BusinessObjectTypeName` and `LinkedSAPObjectKey` are *headers*; on this **reading** call they are *parameters*. Mixing the two up produces a message that looks like a missing authorisation in both directions.

### Step 3: Fetch the Bytes Again

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

The bytes come back as an MCP `resource` blob. In the n8n node they arrive as a binary field on the item.

### Before Repeating an Upload: Look First

`API_CV_ATTACHMENT_SRV` reports `updatable: 0` across the whole service — **there is no PATCH**. Uploading the same file again does not replace the first one; it attaches a second document to the same object. A workflow that retries needs Step 2 before Step 1, not after.
