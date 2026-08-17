# syntax=docker/dockerfile:1
#
# =============================================================================
# guniweb-sap-mcp — Container-Abbild
# =============================================================================
#
# Das Abbild wird NICHT aus dieser Quelle gebaut, sondern aus dem
# veröffentlichten npm-Paket. Zwei Gründe:
#
#   1. Es kann nichts auseinanderlaufen. Was im Container liegt, ist Byte für
#      Byte das Artefakt, das auf npm liegt — kein zweiter Build-Pfad, der
#      irgendwann anders ausfällt als der erste.
#   2. Der Bauplan bleibt vorzeigbar. Diese Datei kann im öffentlichen
#      Schaufenster-Repo liegen und dort auch laufen, ohne dass die private
#      Quelle dafür nötig wäre — jeder kann das Abbild nachbauen.
#
# Bauen:
#   docker build --build-arg PACKAGE_VERSION=0.4.2 -t guniweb-sap-mcp:0.4.2 .
#
# Betreiben (HTTP-Transport ist im Abbild voreingestellt):
#   docker run --rm -p 8808:8808 --env-file .env guniweb-sap-mcp:0.4.2
#
# Ohne SAP-System ausprobieren:
#   docker run --rm -p 8808:8808 -e SAP_MCP_DEMO=true guniweb-sap-mcp:0.4.2
#
# Mindestversion 0.4.2: Der Transport kommt hier aus SAP_MCP_TRANSPORT, und ältere
# Fassungen lesen diese Variable nicht — sie starten auf stdio und veröffentlichen
# einen Port, an dem nie jemand antwortet.
#
# Nicht enthalten: RFC/BAPI. Dieser Pfad braucht das SAP NW RFC SDK, das SAP
# nur an Kunden lizenziert und das deshalb in keinem öffentlichen Abbild liegen
# darf. Die optionale Abhängigkeit `node-rfc` wird bewusst weggelassen; alle
# übrigen Werkzeuge (OData V2/V4, IDoc über HTTP/XML) laufen vollständig.
# =============================================================================

# Alpine, weil ohne native Abhängigkeiten nichts an musl scheitern kann und das
# Abbild klein bleibt. Über --build-arg auf node:22-slim umstellbar, falls eine
# Umgebung glibc verlangt.
ARG NODE_IMAGE=node:22-alpine

# -----------------------------------------------------------------------------
# Stufe 1 — Abhängigkeiten aus der npm-Registry holen
# -----------------------------------------------------------------------------
# --platform=$BUILDPLATFORM: Diese Stufe läuft immer auf der Architektur des
# Bauwirts, auch wenn für arm64 gebaut wird. Das darf sie, weil nach
# --omit=optional nur JavaScript installiert wird — nichts davon ist
# architekturabhängig. Der Mehrarchitektur-Build braucht dadurch keine
# Emulation. Käme je ein RUN-Befehl in die Laufzeitstufe, gälte das nicht mehr.
FROM --platform=$BUILDPLATFORM ${NODE_IMAGE} AS deps

# Ohne Version kein Build: ein implizites "latest" würde bedeuten, dass zwei
# Bauläufe desselben Stands verschiedene Abbilder ergeben können.
ARG PACKAGE_VERSION
RUN test -n "${PACKAGE_VERSION}" || { \
      echo "FEHLER: --build-arg PACKAGE_VERSION=<version> fehlt (z. B. 0.4.1)." >&2; \
      exit 1; \
    }

WORKDIR /opt/sap-mcp

# Eigene package.json statt `npm init`: der Verzeichnisname darf nicht mit dem
# Paketnamen kollidieren, sonst verweigert npm die Installation ("refusing to
# install package with itself as dependency").
RUN printf '{\n  "name": "guniweb-sap-mcp-container",\n  "private": true,\n  "type": "module"\n}\n' > package.json

# --omit=optional lässt node-rfc weg (siehe Kopf), --ignore-scripts verhindert,
# dass irgendein Paket beim Installieren Code im Build ausführt.
RUN npm install \
      --omit=optional \
      --omit=dev \
      --ignore-scripts \
      --no-audit \
      --no-fund \
      "guniweb-sap-mcp@${PACKAGE_VERSION}" \
    && npm cache clean --force \
    && rm -f package-lock.json

# -----------------------------------------------------------------------------
# Stufe 2 — Laufzeit
# -----------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS runtime

ARG PACKAGE_VERSION

LABEL org.opencontainers.image.title="guniweb-sap-mcp" \
      org.opencontainers.image.description="SAP S/4HANA & ECC MCP server — OData V2/V4, IDoc, RFC/BAPI for n8n" \
      org.opencontainers.image.version="${PACKAGE_VERSION}" \
      org.opencontainers.image.source="https://github.com/guniweb/guniweb-sap-mcp" \
      org.opencontainers.image.documentation="https://github.com/guniweb/guniweb-sap-mcp#readme" \
      org.opencontainers.image.url="https://guniweb.de/sap-mcp" \
      org.opencontainers.image.vendor="GuniWeb" \
      org.opencontainers.image.licenses="ISC"

# Ein Container ohne Kommandozeile soll trotzdem das Richtige tun: HTTP-Transport
# auf 8808. Beides ist per Umgebungsvariable und per Flag übersteuerbar — wer
# stdio will, hängt `--transport stdio` an.
ENV NODE_ENV=production \
    SAP_MCP_TRANSPORT=http \
    SAP_MCP_PORT=8808 \
    PATH=/opt/sap-mcp/node_modules/.bin:$PATH

COPY --from=deps --chown=root:root /opt/sap-mcp/node_modules /opt/sap-mcp/node_modules

# Der Server schreibt nichts in sein eigenes Verzeichnis; Caches (--cache-dir)
# und die destinations.json kommen aus gemounteten Volumes.
WORKDIR /home/node
USER node

EXPOSE 8808

# Im stdio-Betrieb gibt es keinen Endpunkt zum Prüfen — dort meldet die Prüfung
# schlicht "gesund", statt den Container fälschlich als krank zu markieren.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "const t=process.env.SAP_MCP_TRANSPORT||'http';if(t==='stdio')process.exit(0);const p=process.env.SAP_MCP_PORT||'8808';fetch('http://127.0.0.1:'+p+'/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["guniweb-sap-mcp"]
