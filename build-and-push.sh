#!/usr/bin/env bash
# Build the agent image and push it to the self-hosted anonymous Docker Registry.
#
#   export REGISTRY_HOST="byor-anon-registry.eastus.azurecontainer.io"
#   export IMAGE_TAG="0.1"
#   ./build-and-push.sh
#
# No docker login required: the registry allows anonymous push/pull by design (it has no
# authentication configured at all -- see knowledge/overview.md). The registry sits behind a
# Caddy TLS proxy with a real Let's Encrypt certificate, so this is a normal, secure push -- no
# insecure-registries config needed. (REGISTRY_HOST intentionally has no port: Foundry's
# hosted-agent image validator rejects host:port image references -- see README's "Gotcha".)
set -euo pipefail

REGISTRY_HOST="${REGISTRY_HOST:?set REGISTRY_HOST, e.g. byor-anon-registry.eastus.azurecontainer.io}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"
IMAGE="${REGISTRY_HOST}/byor-agent-docker:${IMAGE_TAG}"

echo "==> Building ${IMAGE} (linux/amd64)"
docker build --platform linux/amd64 -t "${IMAGE}" .

echo "==> Smoke testing locally on :8088"
CID=$(docker run -d --rm -p 8088:8088 "${IMAGE}")
trap 'docker stop "${CID}" >/dev/null 2>&1 || true' EXIT
sleep 4
curl -fsS http://localhost:8088/healthz; echo
curl -fsS -X POST http://localhost:8088/responses \
  -H 'Content-Type: application/json' \
  -d '{"input":"Respond with a short deployment confirmation."}' | head -c 600; echo
docker stop "${CID}" >/dev/null
trap - EXIT

echo "==> Pushing to the self-hosted anonymous registry (no login needed)"
docker push "${IMAGE}"

echo
IMAGE_DIGEST="$(docker image inspect --format '{{index .RepoDigests 0}}' "${IMAGE}")"
echo "Image pushed: ${IMAGE}"
echo "Immutable digest: ${IMAGE_DIGEST}"
echo "Use this value as 'image_digest' input to the 'Deploy hosted agent' workflow."
