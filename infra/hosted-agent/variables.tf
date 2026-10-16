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
  description = "Adopt the existing logical agent into Terraform state on the first apply."
  default     = true
}
