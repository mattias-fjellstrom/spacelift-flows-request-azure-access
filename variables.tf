#---------------------------------------------------------------------------------------------------
# BEHAVIOR
#---------------------------------------------------------------------------------------------------
variable "rollout_stage" {
  description = "Deployment stage: 1 creates Slack, 2 adds Azure, and 3 creates the flow. Increase it between applies in the same configuration."
  type        = number
  default     = 3

  validation {
    condition     = var.rollout_stage == floor(var.rollout_stage) && var.rollout_stage >= 1 && var.rollout_stage <= 3
    error_message = "rollout_stage must be 1, 2, or 3."
  }
}

variable "enable_agent_mcp" {
  description = "Deploy the MCP-enabled flow definition instead of the form-only definition."
  type        = bool
  default     = false
}

#---------------------------------------------------------------------------------------------------
# FLOWS
#---------------------------------------------------------------------------------------------------
variable "flows_endpoint" {
  description = "Flows instance to manage: https://useflows.eu or https://useflows.us."
  type        = string
  default     = "https://useflows.eu"
}

variable "flows_project_id" {
  description = "ID of the Flows project to deploy to."
  type        = string
}

#---------------------------------------------------------------------------------------------------
# SLACK CONFIG
#---------------------------------------------------------------------------------------------------
variable "slack_app_version" {
  type    = string
  default = "0.7.0"
}

variable "slack_channel_id" {
  description = "ID of the Slack channel that receives approval requests and notifications. Use the ID, not the channel name."
  type        = string

  validation {
    condition     = var.slack_channel_id != "C0123456789" && can(regex("^[CG][A-Z0-9]{8,}$", var.slack_channel_id))
    error_message = "slack_channel_id must be the real Slack channel ID (starting with C for public channels or G for private channels), not the example placeholder or a channel name."
  }
}

variable "slack_bot_token" {
  description = "Bot token (xoxb-...) of the Slack app. Leave null until the first apply has created the installation and its setup instructions."
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_signing_secret" {
  description = "Signing secret of the Slack app. Leave null until the first apply has created the installation and its setup instructions."
  type        = string
  default     = ""
  sensitive   = true
}

#---------------------------------------------------------------------------------------------------
# AZURE CONFIG
#---------------------------------------------------------------------------------------------------
variable "azure_oidc_app_version" {
  type    = string
  default = "0.2.0"
}

variable "subscription_id" {
  description = "ID of the Azure subscription that people can request temporary access to. Required from rollout stage 2."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.rollout_stage < 2 || var.subscription_id != null
    error_message = "subscription_id is required when rollout_stage is 2 or 3."
  }
}

variable "assignable_roles" {
  description = "Names of the Azure built-in roles that can be requested. The flow's identity is not allowed to assign any other role."
  type        = list(string)
  default     = ["Reader", "Storage Blob Data Reader", "Contributor"]

  validation {
    condition     = length(var.assignable_roles) > 0
    error_message = "At least one role must be assignable."
  }
}

variable "requester_identities" {
  description = "Entra ID identity by the email address that Flows reports for a signed-in user, for people whose two identities differ. The identity is an object ID, a user principal name or an email address."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for login, identity in var.requester_identities : trimspace(login) != "" && trimspace(identity) != ""])
    error_message = "Neither the Flows email address nor the Entra ID identity may be empty."
  }
}

variable "flows_oidc_issuer_url" {
  description = "URL of the Azure OIDC app installation in Flows, used as the issuer of the federated credential. It only exists after the first apply; leave null until then, see the README."
  type        = string
  default     = ""
}
