# Gasket development environment

Tools for development of the Gasket Gateway

## Prerequisites

DNS entries in either your local DNS server or your `/etc/hosts` file

This repo and the main Gasket repo are setup for `<tool>.gasket-dev.local` you should add the following records:

```
portal.gasket-dev.local 127.0.0.1
traefik.gasket-dev.local 127.0.0.1
authentik.gasket-dev.local 127.0.0.1
opensearch.gasket-dev.local 127.0.0.1
opensearch-dashboard.gasket-dev.local 127.0.0.1
prometheus.gasket-dev.local 127.0.0.1
grafana.gasket-dev.local 127.0.0.1
open-webui.gasket-dev.local 127.0.0.1
ollama-external.gasket-dev.local 127.0.0.1
ollama-internal.gasket-dev.local 127.0.0.1
code.gasket-dev.local 127.0.0.1
```

## Traefik

Serves as an ingress proxy that handles the tls termination and hostname routing

Exposes ports 80 and 443 for the proxy, with 80 redirecting to 443 https

Traefik UI available at traefik.gasket-dev.local via the Traefik instance routing to it's UI instance

Traefik metrics available at traefik-metrics.gasket-dev.local via the Traefik instance routing to it's metrics instance

## Authentik

Gasket requires OIDC for user auth to the portal UI, Authentik provides this with various test users for different scenarios.
It also serves as the OIDC provider for the rest of the development environment tools.

Authentik available at authentik.gasket-dev.local:443 via the Traefik instance routing to authentik.gasket-dev.local:9443 (unverified https)

## OpenSearch

Gasket requires an OpenSearch cluster for storing metadata and full content event records.

OpenSearch available at opensearch.gasket-dev.local:443 via the Traefik instance routing to opensearch.gasket-dev.local:9200 (http)

OpenSearch dashboard available at opensearch-dashboard.gasket-dev.local:443 via the Traefik instance routing to opensearch-dashboard.gasket-dev.local:5601 (http)

## Prometheus

Gasket requires a Prometheus server to scrape metrics out of Gasket for monitoring and managing usage quotas

OpenSearch available at opensearch.gasket-dev.local:443 via the Traefik instance routing to opensearch.gasket-dev.local:9090 (http)

## Grafana

Used to work with the Gasket Grafana dashboards

Grafana available at grafana.gasket-dev.local:443 via the Traefik instance routing to grafana.gasket-dev.local:3000 (http)

## Open WebUI

This is used to validate Open WebUI use cases against the Gasket API

Open WebUI available at open-webui.gasket-dev.local:443 via the Traefik instance routing to open-webui.gasket-dev.local:3001 (http)

## Ollama

This stubs OpenAI compliant backends, two instances (internal and external) are provided to simulate multiple endpoints.

Ollama External available at ollama-external.gasket-dev.local:443 via the Traefik instance routing to ollama-external.gasket-dev.local:12434 (http)

Ollama Internal available at ollama-internal.gasket-dev.local:443 via the Traefik instance routing to ollama-internal.gasket-dev.local:11434 (http)

## Code Server

This provides a basic environment to validate the VScode Continue plugin use cases

Code Server available at code.gasket-dev.local:443 via the Traefik instance routing to code.gasket-dev.local:8443 (unverified https)

## Gasket Portal

The Gasket portal available at portal.gasket-dev.local:443 via the Traefik instance routing and load balancing to:
    - portal.gasket-dev.local:5000 (http)
    - portal.gasket-dev.local:5001 (http)
    - portal.gasket-dev.local:5002 (http)

The portal should be running from a seperate project instance and so assumes it will be available at port 5000,5001,5002 using http, it should use the Gasket healtcheck endpoint to validate available backends for load balancing connections
