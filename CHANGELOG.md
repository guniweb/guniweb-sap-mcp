# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-10-01

`sap_function` liefert bei V2-Function-Imports mit Listenrückgabe jetzt alle Datensätze statt nur den ersten. Das ändert die Form der Antwort, daher eine neue Minor-Version. OData-V4-Dienste bekommen getypte Literale und ihre Metadaten als XML. Veröffentlicht wird erstmals per Trusted Publishing.

### Changed

- **Veröffentlichung auf npm über Trusted Publishing statt eines Tokens (#63).** npm schränkt Tokens, die die Zwei-Faktor-Anmeldung umgehen, fürs direkte Veröffentlichen ein. Genau so eines trug der Release-Workflow. Er meldet sich jetzt per OIDC an: npm tauscht das kurzlebige Identitätstoken des Laufs gegen eine Publish-Berechtigung, ein dauerhaftes Geheimnis gibt es nicht mehr. Der Workflow hebt npm dafür auf mindestens 11.5.1, denn npm 10, wie es Node 22 mitbringt, kann kein OIDC, und die Registry antwortet dann mit einem irreführenden 404. Provenance wird ausdrücklich nicht angefordert, weil npm sie aus einem privaten Quell-Repository nicht erzeugt und der Publish sonst mit 422 abbricht.

- **Die Größengrenzen des Pakets fangen jetzt, wofür sie da sind (#64).** Das Bundle darf entpackt höchstens 260 KB und gepackt höchstens 100 KB groß sein. Beide Grenzen sollten ein versehentlich eingebündeltes Paket bemerken, schlugen aber zunehmend bei gewachsenem eigenem Code an: 0.5.1 lag bei 99,3 KB gepackt, der V4-Fix (#65) riss die 260 KB. Eine Messung per esbuild-Metafile ergab null Eingaben aus `node_modules`. Neu prüft `tests/build/minify-safety.build.ts`, dass jeder Paketimport des Quellcodes im Bundle als externer Import stehen bleibt. Wird ein Paket eingebündelt, verschwindet sein Import, und der Test nennt es beim Namen, gleich wie groß es ist. Gegengeprobt mit eingebündeltem `minimatch`. Die Größengrenzen stehen damit großzügiger bei 400 KB entpackt und 150 KB gepackt, in `tarball-shape.build.ts` (greift schon im PR-Lauf) und gleichlautend in `publish.yml`. Außerdem baut der Build-Test-Helfer jetzt auch neu, wenn sich `tsup.config.ts` oder `package.json` ändern, nicht nur `src/`.

### Fixed

- **V2-Function-Imports mit Listenrückgabe lieferten nur den ersten Datensatz.** `sap_function` gab bei OData V2 aus jeder Antwort nur `results[0]` zurück, auch wenn der Function-Import laut `$metadata` eine Liste liefert (`ReturnType="Collection(...)"`). `GetAllOriginals` aus `API_CV_ATTACHMENT_SRV` meldete bei einem Beleg mit mehreren Anhängen stillschweigend nur einen. Eine Collection kommt jetzt vollständig als `{ "results": [...] }` zurück, Datumswerte und `__metadata` werden je Datensatz behandelt wie bisher. Ohne Metadaten entscheidet die Form der Antwort (`d.results` oder `d` als Array). **Verhaltensänderung:** Wer bisher bei einer Listenrückgabe das Objekt des ersten Datensatzes erwartet hat, bekommt jetzt die Hülle mit allen Datensätzen. Einzelrückgaben (Entity, Complex Type) bleiben unverändert das Objekt selbst. Nicht betroffen sind `create` und der Medien-Upload, die immer genau einen Datensatz zurückbekommen.

- **OData-V4-Dienste bekamen dieselben falschen Literale wie V2 bis 0.5.1, und an SAP gar keine Metadaten (#65).** Drei zusammenhängende Fehler: Der V4-Formatierer setzte jede Zeichenkette in Apostrophe, auch eine GUID, die in V4 **nackt** steht (`TravelUUID=fa49…`), und maskierte enthaltene Apostrophe nicht. Die Parameter von V4-Functions liefen durch dieselbe Regel, ein `Edm.Date` wurde zu `'2026-10-15'`. RAP-Draft-Services (Schlüssel `<UUID>` + `IsActiveEntity`) waren damit per Schlüssel nicht adressierbar. Die Typen dafür hätten im `$metadata` gestanden, aber der Server las V4-Metadaten nur als JSON. SAP liefert sie als XML, und XML-CSDL ist für V4 die Pflichtform. Die Versionserkennung hielt einen Dienst mit `<edmx:Edmx Version="4.0">` sogar für V2 und schickte ihn über den V2-Client.

  Neu sind ein V4-Formatierer (`src/odata/v4/v4-literal.ts`), der die Typen aus dem `$metadata` nimmt (`Edm.Guid`, `Edm.Date`, `Edm.DateTimeOffset`, Zahlen nackt, `Edm.String` mit verdoppeltem Apostroph, `duration'…'`), und ein Parser für V4-Metadaten als XML (`v4-metadata-xml-parser.ts`, samt Capabilities aus Inline- und `Annotations`-Blöcken). Der V4-Client fordert das `$metadata` als XML an und liest JSON-CSDL, wo ein Dienst es trotzdem liefert. Die Versionserkennung liest die Version am Wurzelelement. Ohne Metadaten gilt eine GUID-förmige Zeichenkette in V4 weiter als Zeichenkette, denn ob ein Dienst sie als `Edm.Guid` oder `Edm.String` führt, weiß nur das `$metadata`. Die Typhilfen für V2 und V4 liegen gemeinsam in `src/odata/edm-types.ts`.

  Ein Integrationstest (`tests/integration/v4-draft-literals.integration.ts`) spielt einen RAP-Draft über die MCP-Werkzeuge durch: aktivieren, lesen, bearbeiten, ändern, erneut aktivieren, löschen, dazu eine gebundene Function mit Datum, GUID und Zeichenkette, Löschen per Batch und die Metadaten aus dem XML. Das nachgestellte Gateway liefert sein `$metadata` als XML wie SAP. Gegen den alten Code schlägt jeder Fall fehl. **Nicht gegen ein echtes System geprüft:** Auf S20 und S22 ist kein V4-Dienst veröffentlicht, auch der V4-Katalog nicht.

## [0.5.1] - 2026-09-27

Schreiben in Fiori-Draft-Services (BANF, Bestellung, Lieferant, Material) funktioniert jetzt vollständig, `sap_batch` läuft gegen echte V2-Gateways, und das Protokoll enthält keine Zugangsdaten und personenbezogenen Werte mehr.

### Security

- **Zugangsdaten und personenbezogene Werte traten über das Protokoll aus.** Der Server schreibt auf stderr, und stderr landet im Container-Log — dauerhaft, ohne Löschfrist und in vielen Aufstellungen zentral eingesammelt. Dort standen auf Stufe `info` und bei **jeder** Anfrage: der vollständige SAP-API-Schlüssel (Kopfzeile `APIKey`), das SAP-Session-Cookie, das CSRF-Token, dazu frei konfigurierbare Kopfzeilen wie `Slug` (der Dateiname eines Uploads) und `LinkedSAPObjectKey` (eine Belegnummer). Die bisherige Handkürzung von `Authorization` auf 15 Zeichen half nicht, sondern gab bei `Basic ` noch die ersten Zeichen des Benutzernamens preis. Ebenso im Klartext: der Wert in einem `$filter` (`CustomerName eq 'Mueller'`), das Schlüsselprädikat einer URL (`A_BusinessPartner('4711')`) und ein 200-Zeichen-Auszug des SAP-Fehlerkörpers, der regelmäßig genau den beanstandeten Wert zurückgibt. Bei jedem fehlgeschlagenen End-zu-Ende-Test ging der echte API-Schlüssel zusätzlich in die CI-Ausgabe und zirkulierte damit weiter als jedes Container-Log.

  Neu ist eine gemeinsame Schwärzung für **beide** pino-Instanzen (`src/observability/log-redaction.ts`) — die Instanz im SAP-HTTP-Client erbt nichts vom Logger in `index.ts`, und an ihr hängen fast alle Austrittsstellen. Kopfzeilen laufen gegen eine **Positivliste**: Der Name der Kopfzeile bleibt stehen, weil er Diagnose ist, der Inhalt wird ersetzt. Ein `$filter` wird **auf seine Struktur reduziert statt geschwärzt** — `CustomerName eq '<str>' and Amount gt <num>` —, damit die Fehlersuche weiterhin zeigt, ob das falsche Feld gefiltert wurde oder der Ausdruck syntaktisch entstellt war; Hashen scheidet aus, weil Namen und Belegnummern einen kleinen Wertebereich haben und durchprobierbar sind. Dieselbe Reduktion behandelt die Schlüsselprädikate in URLs, ohne Versionsnummern in Servicepfaden anzutasten. Der Auszug des Fehlerkörpers weicht Typ und Länge; der Fehlertext selbst erreicht den Aufrufer weiterhin geparst über `parseSapError`. Das CSRF-Debug-Protokoll nennt nur noch, **ob** ein Token kam.

  Die Abschlusszeile je Werkzeugaufruf (`correlationId`, `tool`, `outcome`, `durationMs`, `sapCalls`, `resultBytes`) bleibt unverändert — sie ist dokumentiert und trägt nichts Vertrauliches. Laufzeitkosten entstehen praktisch keine: pino ordnet die Schwärzungspfade nach oberstem Schlüssel und schlägt nur für tatsächlich vorhandene Schlüssel nach, sodass die Liste für Logzeilen ohne `headers`, `url` oder `params` kostenlos ist.

### Fixed

- **Fiori-Draft-Services ließen sich anlegen, aber nicht aktivieren, ändern oder löschen.** Die Schlüssel von Draft-Entitäten tragen `DraftUUID` (`Edm.Guid`) und `IsActiveEntity` (`Edm.Boolean`), und SAP prüft jeden Wert in Schlüsselprädikat und Funktionsimport-Parameter streng gegen seinen Edm-Typ. Der Server hatte dafür zwei getrennte Formatierer, und beide rieten nur: `sap_function` setzte bei OData V2 jede Zeichenkette in Apostrophe, auch eine GUID (SAP: `Invalid function import parameter type for 'DraftUUID'. Expected type is 'Edm.Guid'`, und ein schon übergebenes `guid'…'` wurde zu `'guid'…''`), und das Schlüsselprädikat machte aus einem Boolean `'true'` (SAP: `Invalid key predicate type for 'IsActiveEntity'. Expected type is 'Edm.Boolean'`). Damit war jeder Schreibweg gegen BANF, Bestellung, Lieferant oder Material nach dem Anlegen zu Ende. Gemessen am 27.09. gegen S20/324 mit `MM_PUR_PR_PROFNL_MAINTAIN_SRV`, betroffen 0.4.1 und 0.5.0.

  Neu ist ein gemeinsamer Formatierer für beide Stellen (`src/odata/v2/v2-literal.ts`), der die Typen aus dem `$metadata` nimmt: `Edm.Guid` → `guid'…'`, `Edm.Boolean` → `true`, `Edm.DateTime` → `datetime'…'` ohne Zeitzone, `Edm.Decimal` → `5M`, `Edm.String` → `'…'` mit verdoppeltem Apostroph. Der Typ entscheidet, nicht der übergebene Wert: Eine Zahl für einen `Edm.String`-Schlüssel wird trotzdem gequotet, ein schon umhülltes `guid'…'` nicht doppelt. Ohne Metadaten entscheidet der Wert, jetzt auch für Booleans. Die Metadaten liegen nach dem Start ohnehin im Cache, es entsteht kein zusätzlicher Abruf. `sap_function` nimmt bei V2 außerdem die HTTP-Methode aus dem `$metadata`, wenn keine angegeben ist, so wie es die Werkzeugbeschreibung schon immer versprach. Die Beschreibung von `sap_function` erklärt den Draft-Ablauf (`…Activation`, `…Edit` mit `DraftUUID` und `IsActiveEntity`), die API-Referenz zeigt ihn Schritt für Schritt.

- **Jeder V2-Batch scheiterte an SAP mit „malformed syntax".** `sap_batch` lieferte gegen ein echtes Gateway für jede Operation `The Data Services Request could not be understood due to malformed syntax`. Drei Ursachen: Eine Teilanfrage ohne Rumpf (GET, DELETE, POST auf einen Funktionsimport) schloss ihre Kopfzeilen nicht mit einer Leerzeile ab, denn das CRLF vor dem nächsten Trenner gehört nach RFC 2046 zum Trenner. Das Werkzeug reichte `changesetId` bei V2 gar nicht weiter, Schreibaufrufe standen also außerhalb jedes Changesets. Und die Zuordnung der Antworten lief über die Position, die bei einem abgelehnten Changeset (eine einzige Fehlerantwort für mehrere Operationen) alle folgenden verschob. Jetzt schließt jede Teilanfrage ihre Kopfzeilen ab, Schreibaufrufe mit gleicher `changesetId` bilden ein Changeset und einer ohne bekommt ein eigenes, die Antworten kommen in der Reihenfolge der Operationen zurück, und der Fehler eines abgelehnten Changesets steht an jeder seiner Operationen. Teilaktualisierungen gehen in `$batch` als `MERGE`, wie es auch das UI5-ODataModel sendet, und `If-Match` fehlt nie (`__etag` oder `*`).

  Ein neuer Integrationstest (`tests/integration/draft-lifecycle.integration.ts`) spielt den ganzen Lebenszyklus einer BANF über die echten MCP-Werkzeuge durch: anlegen, Position über die Navigation, aktivieren, aktiv lesen, bearbeiten, Menge ändern, erneut aktivieren, löschen, dazu Löschen und Ändern per Changeset. Das nachgestellte Gateway ist an genau den Stellen so streng wie SAP und antwortet mit SAPs Fehlertexten. Gegen den alten Code schlägt jeder dieser Tests fehl.

  **Gegen ein echtes System geprüft:** Der ganze Zyklus lief am 27.09. auf S20/324 mit dem Stand dieses Fixes. Aktivieren, aktiv lesen, bearbeiten, Menge per `sap_update` und per `MERGE` im Batch-Changeset ändern, erneut aktivieren, löschen per `sap_delete` und per Batch-Changeset: alles grün, drei Test-BANF angelegt und wieder gelöscht. Dabei fiel auf, dass die Positionen eines Drafts eine **eigene** `DraftUUID` tragen, nicht die des Kopfs. Wer eine Draft-Position mit der Kopf-UUID ändert, bekommt `Change not possible; object does not exist`. Werkzeugbeschreibung und API-Referenz sagen jetzt, dass der Positionsschlüssel über die Navigation des Draft-Kopfs zu lesen ist.

- **Die Startmeldung zählte die Schreibwerkzeuge falsch auf.** „Schreibwerkzeuge sind aktiv (--allow-write): …" nannte eine fest getippte Liste, die zweimal an der Wirklichkeit vorbeilief: `sap_media_upload` fehlte, und `sap_function` stand weiterhin darin, obwohl es seit 0.5.0 nicht mehr über die Sichtbarkeit läuft, sondern über den Metadaten-Wächter im Handler. Auch `sap_batch` fehlte von Anfang an. Die Meldung wird jetzt aus derselben Quelle abgeleitet, die über die Registrierung entscheidet (`activeWriteTools()` über `TIER_MEMBERSHIP` und `WRITE_TOOLS`), berücksichtigt die aktiven Tiers samt IDoc- und RFC-Bedingung und führt die Namen zusätzlich als Feld `writeTools` im Protokoll. Wer vor einem produktiven Start wissen will, was dieser Server verändern kann, liest damit die Wahrheit statt einer Momentaufnahme von früher.

## [0.5.0] - 2026-09-07

Binärdaten: SAP-Media-Entities lassen sich jetzt über den Server hoch- und herunterladen, und ein lesender Funktionsimport funktioniert auf einem Read-only-Zugang.

### Added

- **Binary payloads: `sap_media_upload` and `sap_media_download`.** SAP media entities — attachments, document images, archive documents — carry their payload in the request body, not in JSON, and the server had no way to send it. Anyone needing an attachment had to go around the MCP path with a plain HTTP node and rebuild four things by hand: the certificate chain (an intermediate alone is not enough for Node and OpenSSL, so a root CA credential), the CSRF handshake with cookie forwarding, the `sap-client` parameter, and their own error classification. All four already exist in the server, so they now cover raw bytes too. `sap_media_upload` sends the file name as the `Slug` header and the bytes as the body; `sap_media_download` fetches the bytes over `$value` and returns them as an MCP `resource` blob rather than a base64 string inside JSON. Headers are given as an object, and **empty values are not sent** — a pair list cannot express "leave this one out", and an empty header makes SAP answer with a message that reads like a missing authorisation and is none. File names are made header-safe (`Prüfbericht.pdf` → `Pruefbericht.pdf`) and the answer says so via `slugAdjustedFrom`.
- **`--max-request-bytes` / `SAP_MCP_MAX_REQUEST_BYTES`, default 16 MB.** The MCP SDK's Express helper registers `express.json()` without a `limit`, which pins the body at Express's 100 kB default — a base64-encoded PDF above roughly 75 kB failed with `413` before SAP was ever contacted, and the helper offers no switch for it. The server now builds its own Express app. A body above the limit is refused as JSON naming the limit, instead of Express's HTML page, which arrives in the n8n node as "Unexpected MCP response body" and sends people looking for the fault in SAP.

### Changed

- **A reading function import now works on a read-only connection.** `sap_function` counted as a write tool wholesale and was therefore invisible whenever the server ran without `--allow-write` or a token carried `policy.readOnly` — including for the reading case. Measured against a customer system on 2026-09-07: a read-only connection got `Tool sap_function disabled` for `GetAllOriginals`, which is the reading path to the attachments of an object and the basis for verifying an upload by reading it back. A function import is not a write operation as such; it can be either. The tool now stays visible and each call is checked against the service metadata: V2 `HttpMethod="GET"` and V4 `$Kind: "Function"` are allowed, a writing import is rejected, and so is a name the metadata does not carry or metadata that cannot be reached. The proof comes from the metadata, never from the call — `httpMethod` and `isFunction` in the arguments have no bearing on the check. What is visible without `--allow-write` still cannot change anything; for `sap_function` that is now demonstrated rather than assumed.
- **"User has no authorization for operation 03 on object …" now names both causes.** SAP KBA 3421507 lists two, and neither is the authorisation: an object key in the wrong format (it goes out ten digits wide with leading zeros) or a `BusinessObjectTypeName` that does not match the object. The error answer names both, plus the third possibility of confusing headers with query parameters — on a writing POST they are headers, on a reading call query parameters, and either way the message looks like a permission problem.

### Fixed

- **Catalog search is now case-insensitive everywhere — as the tool always claimed.** `sap_discover_services` describes its search as case-insensitive across service name, title and description, and that was true only on systems whose Gateway *cannot* filter: there the server fetches the whole catalog and sieves locally. Where the Gateway understands the filter — the fast path added for the 1222-service system — the search was passed through as `substringof('term',TechnicalServiceName)`, which SAP evaluates case-sensitively and only across two of the three fields. Since SAP service names are almost always upper case and people type lower case, the same query found nothing on one system and everything on another. Reproduced against the built-in demo Gateway, where `business partner` returned an empty list. The filter now lowercases both sides (`substringof('business partner',tolower(TechnicalServiceName)) or …`) and includes `Description`. A Gateway that does not understand the expression answers 400 or 501 as before and the server falls back to fetching everything and filtering locally — and now remembers that refusal instead of paying for a doomed round trip on every search.

## [0.4.2] - 2026-08-17

A container image, and the two fields the official MCP Registry asks for.

### Added

- **Container image on GHCR — `ghcr.io/guniweb/guniweb-sap-mcp`.** `docker run --rm -p 8808:8808 -e SAP_MCP_DEMO=true ghcr.io/guniweb/guniweb-sap-mcp:latest` is now a complete first look, and `docker compose up` puts the server next to n8n without an `npm install -g` at every container start. The image is built **from the published npm package**, not from a second build path — what runs in the container is byte for byte the artifact `npm install` would have fetched, so image and package cannot drift apart. HTTP transport on port 8808 is the default inside it, it runs as a non-root user, carries a health check on `/healthz`, and is published for `linux/amd64` and `linux/arm64` with build provenance and an SBOM. RFC/BAPI is deliberately absent: that path needs the SAP NW RFC SDK, which SAP licenses to customers only and which therefore cannot ship in a public image — install it on the host and run the server from npm for RFC. Every published image is started once in CI against the built-in demo before the release finishes.
- **`SAP_MCP_TRANSPORT` and `SAP_MCP_PORT`** — the equivalents of `--transport` and `--port` as environment variables, same precedence as everywhere else (flag wins, unusable values are ignored rather than fatal). Without them, changing a container's port meant overriding the image command; now a line in the compose file is enough. This is what the image relies on, so a container built on a version before this one would start on stdio and publish a port that never answers.
- **`mcpName` in package.json and a `server.json`** — the two pieces the official MCP Registry checks when a server is listed. The registry compares `mcpName` in the version-specific npm metadata against the name in `server.json`; both now say `io.github.guniweb/guniweb-sap-mcp`, and a unit test holds them together so a mismatch fails before a release, not after one.

### Changed

- **`docker-compose.yml` now uses the published image** instead of installing the package into a bare `node:22-slim` at every start, waits for the server's health check before starting n8n, and shows how to mount a `destinations.json` for several SAP systems or personal SAP logins.

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
[0.6.0]: https://github.com/guniweb/guniweb-sap-mcp/releases/tag/v0.6.0
[0.5.1]: https://github.com/guniweb/guniweb-sap-mcp/releases/tag/v0.5.1
[0.5.0]: https://github.com/guniweb/guniweb-sap-mcp/releases/tag/v0.5.0
[0.3.1]: https://github.com/guniweb/guniweb-sap-mcp/releases/tag/v0.3.1
[0.3.0]: https://github.com/guniweb/guniweb-sap-mcp/releases/tag/v0.3.0
[0.2.2]: https://github.com/guniweb/guniweb-sap-mcp/releases/tag/v0.2.2
[0.2.1]: https://github.com/guniweb/guniweb-sap-mcp/releases/tag/v0.2.1
[0.2.0]: https://github.com/guniweb/guniweb-sap-mcp/releases/tag/v0.2.0
