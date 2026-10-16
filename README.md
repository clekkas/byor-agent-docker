# byor-agent-docker — anonymous-pull proof (self-hosted registry)

Proves a Microsoft Foundry **hosted agent** can pull its container image from a **self-hosted,
unauthenticated Docker Registry** (`registry:2`, the official open-source reference
implementation) with **zero Foundry registry connection and zero OIDC token exchange**
configured — relying only on the registry itself allowing anonymous pulls.

This is the closer match to the KP/JFrog scenario than `byor-agent-dockerhub`: both JFrog
Artifactory and `registry:2` implement the same open Docker Registry HTTP API V2 specification,
so a result here speaks directly to whether Foundry's anonymous-pull mechanism works against that
protocol in general, isolated from any JFrog-specific behavior or networking.

See `knowledge/overview.md` for full context, including the prior inconclusive JFrog experiment
this repo follows up on.

## The registry

A single, disposable `registry:2` container running on **Azure Container Instances (ACI)** —
chosen deliberately over Azure Container Apps since Kaiser Permanente does not use Container Apps;
this is test scaffolding, not an architecture recommendation.

```
http://byor-anon-registry.eastus.azurecontainer.io:5000
```

No authentication is configured at all. Verified anonymous:

```bash
curl http://byor-anon-registry.eastus.azurecontainer.io:5000/v2/
# {}
curl http://byor-anon-registry.eastus.azurecontainer.io:5000/v2/_catalog
# {"repositories":[]}
```

## Files

| File | Purpose |
|---|---|
| `app.py` | Same minimal Foundry hosted-agent app as `byor-agent` (Responses protocol + health probes). Registry-agnostic. |
| `Dockerfile` | `linux/amd64`, python:3.12-slim, non-root uid 10001, listens on `$PORT` (8088) |
| `build-and-push.sh` | Build → local smoke test → push to the self-hosted registry |
| `infra/hosted-agent/` | Terraform (AzAPI data-plane) for the logical hosted agent. `container_configuration` has **no `registry_connection_id` key at all** — the proof point. |
| `scripts/test-hosted-agent.py` | Waits for the new version to become active, verifies its image, and invokes its Responses endpoint |
| `.github/workflows/deploy-agent.yml` | `workflow_dispatch`-only: takes an image digest, confirms the registry is reachable anonymously from the runner, deploys via Terraform, smoke-tests |

## Push over plain HTTP (one-time Docker config)

The registry has no TLS certificate (it's a disposable test instance), so Docker needs to be told
to treat this host as "insecure" (meaning: connect over plain HTTP, not "run less securely" in any
other sense — there is nothing sensitive in this registry).

**Docker Desktop:** Settings → Docker Engine → add to the JSON:

```json
{
  "insecure-registries": ["byor-anon-registry.eastus.azurecontainer.io:5000"]
}
```

Apply & Restart, then:

```bash
export REGISTRY_HOST="byor-anon-registry.eastus.azurecontainer.io:5000"
export IMAGE_TAG="0.1"
./build-and-push.sh
```

No `docker login` is needed or possible — the registry has no auth configured.

The script prints the pushed image's immutable digest, e.g.:

```
byor-anon-registry.eastus.azurecontainer.io:5000/byor-agent-docker@sha256:<64 hex chars>
```

## Deploy to Foundry (the actual proof)

In GitHub: **Actions → "Deploy hosted agent (Foundry, anonymous self-hosted registry pull)" → Run
workflow**, paste the digest from the previous step as `image_digest`.

The workflow:
1. Confirms the registry answers anonymously from GitHub's own network (not just this machine).
2. Logs into Azure via OIDC (no stored secret — federated credential on the shared deploy app).
3. Runs `terraform apply` against `infra/hosted-agent/`, whose `main.tf` **omits**
   `registry_connection_id` entirely.
4. Waits for the new agent version to reach `active` and calls its Responses endpoint.

If step 4 succeeds, that is direct, reproducible proof that Foundry pulled the image with no
registry connection configured, against the same protocol JFrog implements — the opposite of the
JFrog trial-account result, where the same experiment (`byor-agent`'s `test-registry-no-auth.py`)
failed without one.

## Foundry project used

This deploys to the shared, disposable `workshop-demo-project` Foundry project (see
`INFRA-NOTES.md` in the `byor-variants` working directory for full resource details) — not a KP
production project.
