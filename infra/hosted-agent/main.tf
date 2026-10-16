locals {
  project_endpoint = trimsuffix(var.project_endpoint, "/")
  project_parent   = trimprefix(local.project_endpoint, "https://")
}

import {
  for_each = var.import_existing_agent ? toset([var.agent_name]) : toset([])
  to       = azapi_data_plane_resource.hosted_agent
  id       = "${local.project_parent}/agents/${each.value}|Microsoft.Foundry/agents@v1"
}

# PROOF POINT: container_configuration deliberately has NO registry_connection_id key at all
# (not null, not empty string -- the key is absent). This is the entire point of this repo: prove
# Foundry's hosted-agent runtime can pull the image with zero Foundry registry connection and zero
# OIDC token exchange configured, relying only on the registry itself permitting anonymous pulls --
# here, a self-hosted registry:2 instance (the same Docker Registry v2 API JFrog implements).
resource "azapi_data_plane_resource" "hosted_agent" {
  type      = "Microsoft.Foundry/agents@v1"
  name      = var.agent_name
  parent_id = local.project_parent

  body = {
    name = var.agent_name
    definition = {
      kind   = "hosted"
      cpu    = var.cpu
      memory = var.memory
      container_configuration = {
        image = var.image_uri
        # registry_connection_id intentionally omitted.
      }
      environment_variables = {
        AZURE_AI_MODEL_DEPLOYMENT_NAME = var.model_deployment_name
      }
      protocol_versions = [
        {
          protocol = "responses"
          version  = "2.0.0"
        }
      ]
    }
  }

  response_export_values = ["versions.latest.version"]

  lifecycle {
    prevent_destroy = true

    precondition {
      condition = contains(
        ["0.5:1Gi", "1:2Gi", "2:4Gi"],
        "${var.cpu}:${var.memory}",
      )
      error_message = "Choose a supported CPU and memory pair."
    }
  }
}
