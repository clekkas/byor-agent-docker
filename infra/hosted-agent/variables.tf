variable "project_endpoint" {
  type        = string
  description = "Foundry project data-plane endpoint."

  validation {
    condition     = can(regex("^https://[^/?#]+/api/projects/[^/?#]+/?$", var.project_endpoint))
    error_message = "Use an HTTPS Foundry project endpoint without a query or fragment."
  }
}

variable "agent_name" {
  type        = string
  description = "Logical hosted agent to manage."
  default     = "docker-registry-anon-agent"
}

variable "image_uri" {
  type        = string
  description = "Immutable linux/amd64 image digest URI on the self-hosted anonymous registry."

  validation {
    condition     = can(regex("^[^/]+/.+@sha256:[0-9a-f]{64}$", var.image_uri))
    error_message = "Use an immutable registry image URI ending in @sha256:<64 lowercase hex characters>."
  }
}

variable "model_deployment_name" {
  type        = string
  description = "Existing Foundry model deployment used by the container. Empty selects echo mode."
  default     = ""
}

variable "cpu" {
  type        = string
  description = "Hosted-agent CPU allocation."
  default     = "0.5"
}

variable "memory" {
  type        = string
  description = "Hosted-agent memory allocation."
  default     = "1Gi"
}

variable "import_existing_agent" {
  type        = bool
  description = <<-EOT
    Whether to import a PRE-EXISTING logical agent into Terraform state instead of creating a
    new one.

    Set this to false (the default) for a first-time deploy of a never-before-seen agent_name --
    Terraform will create it. Set it to true only once the agent already exists in Foundry (e.g.
    on every subsequent apply after the first, or when adopting an agent that was created outside
    Terraform) -- Terraform will adopt it into state and manage new versions on top of it instead
    of trying to recreate it.

    Getting this backwards produces two different, easy-to-misdiagnose errors:
      - true on a name that doesn't exist yet -> "Cannot import non-existent remote object"
        (Terraform plan fails immediately, no resources touched).
      - false on a name that already exists -> Terraform tries to create a duplicate and the
        Foundry API rejects it (name collision), or -- depending on API behavior -- silently
        creates an unrelated/orphaned second agent under the same name.
  EOT
  default     = false
}

