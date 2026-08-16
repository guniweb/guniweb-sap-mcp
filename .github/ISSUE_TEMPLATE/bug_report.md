---
name: Bug report
about: Something does not work as documented
title: ''
labels: bug
assignees: ''
---

**Server version** (from the `initialize` response or `guniweb-sap-mcp --help`):

**Transport** (stdio / http / sse) and **client** (n8n version, other MCP host):

**SAP system** (S/4HANA on-prem / cloud, ECC + EHP; OData V2/V4, IDoc, RFC):

**What happened** — the tool call, its arguments (no credentials!) and the response:

**What you expected**:

**Log excerpt** — the line with the correlation id of the failing call and the SAP request lines carrying the same id (tokens and passwords are never logged, so this is safe to paste):

**`test-connection` result** (if the problem is connectivity):
