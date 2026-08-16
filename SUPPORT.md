# Support

guniweb-sap-mcp is built and maintained by [GuniWeb](https://guniweb.de) — a consultancy with its own solutions (*processes that work, systems that grow with you*), optimising business processes for mid-sized companies with more than 20 years of practice, strategic consulting and hands-on implementation. The compiled package on npm is **free to use** under the ISC license. The source code is not public; what is public is everything you need to run it: the package, this documentation, the changelog, releases and this issue tracker.

## Community support (free, best effort)

- **Bugs and feature requests** → [GitHub Issues](https://github.com/guniweb/guniweb-sap-mcp/issues). Please include the server version (`initialize` response or `guniweb-sap-mcp --help`), the transport mode, the SAP release (S/4HANA / ECC + EHP) and, for a failing tool call, the correlation id from the log line — it ties the call to the SAP requests it triggered.
- **Questions and ideas** → [GitHub Discussions](https://github.com/guniweb/guniweb-sap-mcp/discussions).
- **Before you file:** `test-connection` walks DNS → TLS → authentication → client (Mandant) → catalog and names the first failing stage with a concrete next step; the same five stages are logged once at startup. Most "it does not connect" reports are answered there.

Community support is best effort: we read everything, we fix what breaks the product for many, and we do not commit to response times.

## Production support (paid)

If the server runs in a business process you depend on, a maintenance subscription gives you what best effort cannot:

- **Production** — prioritised fixes, compatibility commitment across SAP release changes and API deprecations, a direct channel to the maintainers.
- **Production + SLA** — additionally a guaranteed response time on incidents affecting the write path. We recommend this tier as the precondition for productive write operations at customers.
- **Projects** — implementation, extensions, connecting the server to your specific processes (from a first workflow to complete solutions), on a time-and-materials or fixed-price basis.

Details and pricing: **[guniweb.de/sap-mcp](https://guniweb.de/sap-mcp#support)** · Contact: [support@guniweb.de](mailto:support@guniweb.de)

## SAP MCP Checkup

Before an n8n/SAP setup goes live we offer a structured review — authentication path, governance (read-only defaults, token policies, tool visibility), performance (cache, time budgets, catalog discovery on large systems) and the questions around SAP's API policy and Digital Access licensing that an auditor will ask. **[guniweb.de/sap-mcp](https://guniweb.de/sap-mcp#checkup)**

## Security issues

Do **not** open a public issue for a vulnerability — see [SECURITY.md](SECURITY.md).

## How the project is run

- Releases are published to npm from tagged versions; every release passes lint, type check, unit, integration and end-to-end tests against a live SAP system before it is published.
- The [changelog](CHANGELOG.md) is written for operators: every entry says what changed for you and, where relevant, what a migration looks like.
- The server sends **no telemetry** — no usage statistics, no update checks, no crash reports. If you want us to know something, tell us.
