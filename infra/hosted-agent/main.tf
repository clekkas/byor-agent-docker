locals {
  project_endpoint = trimsuffix(var.project_endpoint, "/")
  project_parent   = trimprefix(local.project_endpoint, "https://")
}

# NOTE -- first-time deploy vs. subsequent deploy of the SAME agent_name:
#   import_existing_agent = false (the default): this agent_name has never been deployed before.
#     Terraform creates it fresh. This is the correct setting for the very first apply.
#   import_existing_agent = true: this agent_name already exists in Foundry (e.g. every apply
#     after the first, or you're adopting an agent that was created some other way). Terraform
#     imports it into state instead of trying to create a duplicate.
# Set it wrong and you get a plan-time error, not a vague runtime failure -- see
# variables.tf's import_existing_agent description for exactly which error each wrong setting
# produces, so it's recognizable if you hit it.
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
