# Security Policy

## Reporting a vulnerability

Please report security issues **privately** to [support@guniweb.de](mailto:support@guniweb.de) with `SECURITY` in the subject line — not through a public GitHub issue. Include the server version, the transport mode and, if possible, a reproduction or the relevant log lines (tokens and SAP credentials are never written to the log, so log excerpts are safe to share).

What you can expect from us:

- an acknowledgement within **two business days**;
- an assessment and, for confirmed issues, a fix or mitigation as a priority release — you will hear from us about the timeline;
- credit in the changelog if you want it.

We ask for coordinated disclosure: please give us the chance to ship a fix before details become public.

## Supported versions

| Version | Supported |
|---|---|
| latest `0.x` on npm | yes — fixes ship as the next patch/minor release |
| older `0.x` | no — please upgrade; the changelog lists every behaviour change with its migration |

Customers with a production support subscription receive fixes for the version they run.

## Zero telemetry — a commitment, not a setting

guniweb-sap-mcp sends **nothing** anywhere except to the SAP and BTP endpoints you configure (and, when you use `SAP_JWT_ISSUER`, to that issuer's OIDC/JWKS endpoints to verify incoming tokens). There are no usage statistics, no update checks, no crash reports, no "phone home". Your SAP data, your metadata and your usage stay in your network. `npm install` naturally talks to the npm registry; the running server does not.

## Secure defaults you get without configuring anything

- **Read-only by default.** `sap_create`, `sap_update`, `sap_delete`, `sap_function`, `sap_batch`, `sap_idoc_send` and the RFC/BAPI write tools are not registered until `--allow-write` is set — a tool an agent cannot see is a tool it cannot call by accident.
- **Tokens and secrets never reach the log.** Bearer tokens, SAP passwords, client secrets and PEM material are not logged; outbound `Authorization` headers appear masked. Rejected requests are logged with client address and reason only.
- **Token-bound access.** With named destinations, one Bearer token per n8n credential selects the SAP system; only the SHA-256 hash of a token is stored, comparison is constant-time over all entries, revocation takes effect on the next request, and after 10 failed attempts per minute a client address gets `429`.
- **Per-token policies can only restrict** (`readOnly`, tool-tier ceiling) — never widen what the server allows.
- **Incoming user tokens are verified** against the issuer's JWKS when `SAP_JWT_ISSUER` is set; a token failing verification is rejected with `401` rather than silently downgraded to the technical user.
- **XML parsing is hardened** against external entities and entity expansion (IDoc webhook and `$metadata`); the IDoc webhook enforces a body-size limit and its own shared secret.
- **TLS verification is on**; `SAP_TLS_VERIFY=false` is warned about in **every** tool result, not only at startup. Corporate CAs go in via `SAP_CA_CERT`.
- **The published npm package contains no source and no source maps** — five files, checked by a hard gate in the release pipeline.

## What we ask of operators

- Run the HTTP transport behind authentication (`--api-key` or destination tokens) — the server warns at startup if it is open.
- Put `destinations.json` (or `.env`) on a volume with restrictive permissions and keep it out of version control; the CLI writes it `0600`.
- Keep the server behind your reverse proxy / network boundary; it is designed to sit next to n8n, not on the public internet.

## Scope

This policy covers the `guniweb-sap-mcp` npm package. Issues in SAP products, n8n or third-party dependencies should be reported to their respective vendors; if a dependency issue affects this server, we still want to know.
