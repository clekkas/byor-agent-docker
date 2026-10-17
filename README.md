# byor-agent-docker — anonymous pull proof (self-hosted registry) 🔐

**Proves a Microsoft Foundry hosted agent can pull its container image from a self-hosted, unauthenticated Docker Registry (`registry:2`) with zero Foundry registry connection and zero OIDC token exchange configured** — the closer analog to the production JFrog scenario, since both implement the same open Docker Registry HTTP API V2 specification.

[![Deploy](https://github.com/clekkas/byor-agent-docker/actions/workflows/deploy-agent.yml/badge.svg)](https://github.com/clekkas/byor-agent-docker/actions/workflows/deploy-agent.yml)

> Sibling repo for the simpler half of the proof: [`byor-agent-dockerhub`](https://github.com/clekkas/byor-agent-dockerhub) validates the same mechanism against public Docker Hub. This repo follows up on an inconclusive JFrog trial-account experiment in `byor-agent`.

## 🎯 What This Proves

- A Microsoft Foundry **hosted agent** running an image pulled from a disposable, self-hosted `registry:2` instance with **no authentication configured at all**
- **No `registry_connection_id`** in the Terraform-managed agent definition — not null, not empty, the key is absent
- Protocol-level proof, not vendor-specific: `registry:2` is the same open-source Docker Registry V2 API that JFrog Artifactory implements, so this result isolates Foundry's pull mechanism from any JFrog product quirks or trial-account limits
- A real, previously-undocumented Foundry platform behavior: **the hosted-agent image validator rejects any `host:port` image reference** — see [🧩 The Gotcha](#-the-gotcha-foundry-rejects-hostport-image-references) below

## 🏗️ Architecture

```
                 Azure Container Instances · container group: byor-anon-registry
                ┌──────────────────────────────────────────────────────────────┐
                │  ┌─────────────────────┐        ┌──────────────────────────┐ │
  Public ──────▶│  │  caddy:2 (sidecar)  │───────▶│  registry:2 (reference)  │ │
  internet      │  │  443 (HTTPS), 80    │        │  5000 (localhost only)   │ │
  (no port)     │  │  real Let's Encrypt │        │  no auth configured      │ │
                │  │  cert for ACI FQDN  │        │  same API as JFrog       │ │
                │  └─────────────────────┘        └──────────────────────────┘ │
                └──────────────────────────────────────────────────────────────┘
                        https://byor-anon-registry.eastus.azurecontainer.io
```

The Caddy sidecar isn't for security — the registry has no auth either way — it exists purely so the registry is reachable on the **standard HTTPS port with no port number in the image reference**, which Foundry's validator requires (see the gotcha below).

## 🚀 Quick Start

### Prerequisites

- A GitHub repository with Actions enabled (this one, forked or as-is)
- An Entra app with GitHub OIDC federation, scoped RBAC on the target Foundry project (already wired for `workshop-demo-project` — see `INFRA-NOTES.md`)
- A private self-hosted GitHub Actions runner reachable to the Terraform state storage account (label `byor-private`) — required because this subscription's state storage is private-network-only by policy
- The self-hosted registry + Caddy TLS proxy already running on ACI (see [Architecture](#-architecture)) — this is shared, disposable infrastructure, not provisioned by this repo's own pipeline

### Deploy

```bash
# Push to main (any tracked path) — GitHub Actions does the rest
git push origin main
```

```bash
# ...or trigger manually, optionally skipping the build with an existing digest
gh workflow run deploy-agent.yml -f image_digest=""
```

> 💡 **Tip**: Watch it live with `gh run watch $(gh run list --limit 1 --json databaseId -q '.[0].databaseId')`.

### Verify the registry is genuinely anonymous

```bash
curl https://byor-anon-registry.eastus.azurecontainer.io/v2/
# {}
curl https://byor-anon-registry.eastus.azurecontainer.io/v2/_catalog
# {"repositories":[]}
```

A bare `200 {}` with no `WWW-Authenticate` challenge is the whole proof surface for anonymous pull.

## 🔑 The Key Difference (vs. OIDC/JFrog)

The entire proof point is one Terraform key, present in `byor-agent` (JFrog) and absent here:

```hcl
# infra/hosted-agent/main.tf
container_configuration = {
  image = var.image_uri
  # registry_connection_id intentionally omitted.
}
```

No connection resource, no Entra audience/issuer config, no token-exchange endpoint. If the agent still reaches `active` and answers its Responses endpoint, Foundry pulled the image with zero credentials presented to the registry.

## 🧩 The Gotcha: Foundry Rejects `host:port` Image References

The registry's native listener is `registry:2`'s default port `5000`. The first version of this proof used `byor-anon-registry.eastus.azurecontainer.io:5000/...` directly as the image reference, and `terraform apply` failed:

```
RESPONSE 400: 400 Bad Request
ERROR CODE: invalid_payload
"message": "Must be a valid container image in the format '<registry>/<repository>[:<tag>|@<digest>]'."
"param": "definition.container_configuration.image"
```

Direct testing against the Foundry agents API (same image string, with vs. without the `:5000` port, everything else identical) confirmed the **port itself** is what's rejected — not the hostname, not digest-vs-tag, not registry name length. Foundry's hosted-agent image validator only accepts a bare registry host (implicit port 443), never `host:port` syntax — even though `host:port/repo` is valid per the Docker/OCI reference grammar.

**Fix:** a Caddy TLS reverse proxy in front of the registry, auto-provisioning a real Let's Encrypt certificate for the public ACI FQDN, so the image reference never needs an explicit port.

## 🔁 Pipeline

| Stage | Runner | What happens |
|---|---|---|
| **build** | `ubuntu-latest` (GitHub-hosted) | Docker Buildx builds `linux/amd64`, pushes to the self-hosted registry over real TLS (no `insecure-registries` config needed), smoke-tests the pushed image locally |
| **deploy** | `[self-hosted, linux, byor-private]` | Pings the registry anonymously from the runner (diagnostic), Azure OIDC login, `terraform init/plan/apply` against `infra/hosted-agent/`, waits for the new agent version to go `active`, calls its Responses endpoint |

## 📁 Repository Layout

```
byor-agent-docker/
├── app.py                          # Minimal Foundry hosted-agent app (Responses protocol + health probes)
├── Dockerfile                      # linux/amd64, python:3.12-slim, non-root uid 10001
├── build-and-push.sh               # Build → local smoke test → push to the self-hosted registry
├── requirements.txt
├── infra/
│   └── hosted-agent/
│       ├── main.tf                 # The proof point: no registry_connection_id key
│       ├── variables.tf            # import_existing_agent nuance documented here
│       ├── outputs.tf
│       ├── versions.tf
│       └── backend.hcl.example
├── scripts/
│   └── test-hosted-agent.py        # Waits for ACTIVE, verifies image, calls /responses
├── knowledge/
│   └── overview.md                 # Full "why this repo exists" context
└── .github/
    └── workflows/
        └── deploy-agent.yml        # build → deploy, push-triggered + workflow_dispatch
```

## 🛠️ Commands Reference

| Command | Description |
|---|---|
| `git push origin main` | Triggers the full build → push → deploy pipeline automatically |
| `gh workflow run deploy-agent.yml` | Manually trigger a build-and-deploy run |
| `gh workflow run deploy-agent.yml -f image_digest=<digest>` | Skip the build, deploy an already-published digest |
| `./build-and-push.sh` | Local/manual build → smoke test → push (no login needed — the registry has no auth) |
| `curl https://byor-anon-registry.eastus.azurecontainer.io/v2/` | Confirm the registry is still answering anonymously |

### Push over HTTPS (optional, local/manual)

```bash
export REGISTRY_HOST="byor-anon-registry.eastus.azurecontainer.io"
export IMAGE_TAG="0.1"
./build-and-push.sh
```

The registry sits behind a real Let's Encrypt certificate, so Docker's normal, secure registry client works unmodified. No `docker login` is needed or possible — the registry has no auth configured. The script prints the pushed image's immutable digest:

```
byor-anon-registry.eastus.azurecontainer.io/byor-agent-docker@sha256:<64 hex chars>
```

## 📚 Documentation

- [`knowledge/overview.md`](knowledge/overview.md) — why this repo exists, how it relates to `byor-agent` (JFrog/OIDC) and `byor-agent-dockerhub` (public Docker Hub)
- `INFRA-NOTES.md` (in the working directory, not this repo) — Foundry project, Entra app, RBAC, runner, and registry resource details shared across all three repos

## ⚠️ Important Notes

- The registry (`byor-anon-registry.eastus.azurecontainer.io`) and its Caddy TLS proxy are **disposable test scaffolding on Azure Container Instances**, chosen deliberately over Azure Container Apps since Kaiser Permanente does not use that service — not an architecture recommendation.
- This deploys to the shared, disposable `workshop-demo-project` Foundry project — **not** a production project.
- Any registry endpoint exposed on a non-standard port needs a standard-port (443) front end before Foundry will accept the image reference — see [🧩 The Gotcha](#-the-gotcha-foundry-rejects-hostport-image-references).
- Anonymous pull is a proof-of-concept pattern. For production JFrog workloads, OIDC token exchange via a registry connection (see `byor-agent`) remains the correct, auditable approach.

## 🤝 Contributing

This is a proof-of-concept repo built for a specific workshop engagement. Issues and suggestions are welcome, but expect the scope to stay narrow and disposable by design.

## 📄 License

Internal proof-of-concept — no license file; not intended for redistribution outside this engagement.
