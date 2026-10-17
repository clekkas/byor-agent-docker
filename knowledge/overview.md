<!-- scope: docker registry, anonymous, byor, registry connection, aci -->
# byor-agent-docker — what this proves

Generated 2026-10-16.

This is a Microsoft Foundry **hosted agent** deployed with its container image pulled from a
**self-hosted, unauthenticated Docker Registry** (the official open-source `registry:2` image),
with **no Foundry registry connection and no OIDC token exchange configured at all**.

## Why this repo exists

The companion repo `byor-agent` proves the BYOR (bring-your-own-registry) pattern against a
**private, authenticated** JFrog Artifactory registry using Entra/GitHub OIDC federation and a
Foundry registry connection (`oauth_token_exchange` mode). A prior isolated experiment in that
repo (`test-registry-no-auth.py`, run 38665375428) showed anonymous manifest/blob reads against
that specific JFrog trial repository returned HTTP 401, and a hosted-agent deploy with the
registry connection omitted failed with a generic `ProvisioningError` — inconclusive about
whether JFrog specifically, or Foundry's anonymous-pull path in general, was the limiting factor.

A JFrog trial account could not be configured to allow anonymous access (the toggle was
unavailable), so this repo validates the same anonymous-pull mechanism against a **self-hosted,
vendor-neutral Docker Registry v2 implementation** instead — the same reference server software
(`registry:2`) that JFrog, Docker Hub, and most private registries implement the same open Docker
Registry HTTP API V2 specification against. Microsoft's own BYOR documentation explicitly names
"JFrog Artifactory or a self-hosted Docker Distribution registry" as the two supported external
registry patterns, so this keeps the proof inside the documented pattern rather than substituting
an unrelated product.

## Infrastructure note

The registry itself is hosted on **Azure Container Instances (ACI)** purely as disposable test
scaffolding — a single, unauthenticated `registry:2` container with a public endpoint, plus a
`caddy:2` sidecar in the same container group that terminates TLS with a real Let's Encrypt
certificate and reverse-proxies to the registry over localhost — not as an architectural
recommendation. The client does not use Azure Container Apps, so ACI was chosen
deliberately as the simplest "just run one container" option with no implied platform preference.
The TLS proxy exists only because Foundry's hosted-agent image validator rejects any image
reference with an explicit registry port (`host:port/repository`) — see the main `README.md`'s
"Gotcha" section for the exact API error and how this was isolated.

Public endpoint (test-only, not production, no sensitive content):
`https://byor-anon-registry.eastus.azurecontainer.io`

Verified anonymous, no credentials, no `docker login`:
- `GET /v2/`          -> `200 {}`
- `GET /v2/_catalog`  -> `200 {"repositories":[]}`

## Mechanism

`infra/hosted-agent/main.tf`'s `azapi_data_plane_resource` body's `container_configuration` block
contains only `image` — the `registry_connection_id` field is omitted entirely, not set to null or
an empty string. If the hosted agent still reaches `active` and its Responses endpoint answers,
that is direct proof Foundry can pull anonymously from a registry that permits it, using the exact
same registry server implementation pattern documented for BYOR.

## Scope of this proof

This isolates the variable Harsheet's analysis raised: whether a prior failure was due to
authentication being required, or to an unrelated networking/DNS/TLS condition specific to the
JFrog trial tenant. A self-hosted registry with a public, directly-reachable endpoint removes the
private-networking variable entirely, so a result here speaks specifically to the anonymous-pull
authentication question.
