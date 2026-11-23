data "azuread_client_config" "current" {
  count = local.azure_enabled ? 1 : 0
}

data "azuread_application_published_app_ids" "well_known" {
  count = local.azure_enabled ? 1 : 0
}

data "azuread_service_principal" "microsoft_graph" {
  count = local.azure_enabled ? 1 : 0

  client_id = one(data.azuread_application_published_app_ids.well_known).result["MicrosoftGraph"]
}

data "azurerm_role_definition" "assignable" {
  for_each = local.azure_enabled ? toset(var.assignable_roles) : toset([])

  name  = each.key
  scope = local.subscription_scope
}

locals {
  subscription_scope = "/subscriptions/${var.subscription_id}"
  azure_enabled      = var.rollout_stage >= 2

  # Federation needs the URL of the Flows app installation, which is only known
  # after the installation has been created by a first apply.
  federation_ready = local.azure_enabled && var.flows_oidc_issuer_url != ""
  oidc_subject     = local.federation_ready ? regex("^https://([^/:]+)", var.flows_oidc_issuer_url)[0] : null

  graph_user_read_all = local.azure_enabled ? one(data.azuread_service_principal.microsoft_graph).app_role_ids["User.Read.All"] : null

  roles = [
    for name in(local.azure_enabled ? var.assignable_roles : []) : {
      id   = basename(data.azurerm_role_definition.assignable[name].id)
      name = name
    }
  ]
  role_ids = join(", ", local.roles[*].id)
}

# The identity that the flow uses. It has no secret: Flows signs a token that
# Entra ID trusts through the federated credential below.
resource "azuread_application" "flows" {
  count = local.azure_enabled ? 1 : 0

  display_name = "spacelift-flows-azure-access-requests"
  owners       = [one(data.azuread_client_config.current).object_id]

  required_resource_access {
    resource_app_id = one(data.azuread_service_principal.microsoft_graph).client_id

    resource_access {
      id   = local.graph_user_read_all
      type = "Role"
    }
  }
}

resource "azuread_service_principal" "flows" {
  count = local.azure_enabled ? 1 : 0

  client_id = one(azuread_application.flows).client_id
  owners    = [one(data.azuread_client_config.current).object_id]
}

resource "azuread_application_federated_identity_credential" "flows" {
  count = local.federation_ready ? 1 : 0

  application_id = one(azuread_application.flows).id
  display_name   = "spacelift-flows"
  description    = "Lets the Azure OIDC app installation in Spacelift Flows sign in as this application."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = var.flows_oidc_issuer_url
  subject        = local.oidc_subject
}

# Admin consent for User.Read.All, which the flow uses to turn the requester's
# email into an Entra ID object ID.
resource "azuread_app_role_assignment" "graph_user_read_all" {
  count = local.azure_enabled ? 1 : 0

  app_role_id         = local.graph_user_read_all
  principal_object_id = one(azuread_service_principal.flows).object_id
  resource_object_id  = one(data.azuread_service_principal.microsoft_graph).object_id
}

# Lets the form list the resource groups of the subscription.
resource "azurerm_role_assignment" "reader" {
  count = local.azure_enabled ? 1 : 0

  scope                = local.subscription_scope
  role_definition_name = "Reader"
  principal_id         = one(azuread_service_principal.flows).object_id
  principal_type       = "ServicePrincipal"
}

# Lets the flow create and delete role assignments, but only for the roles in
# assignable_roles and only for users. Without the condition this identity could
# hand out any role, including Owner.
resource "azurerm_role_assignment" "access_administrator" {
  count = local.azure_enabled ? 1 : 0

  scope                = local.subscription_scope
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = one(azuread_service_principal.flows).object_id
  principal_type       = "ServicePrincipal"
  description          = "Spacelift Flows may assign and remove roles for users."
  condition_version    = "2.0"
  condition            = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.role_ids}}
      AND
      @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'User'}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.role_ids}}
      AND
      @Resource[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'User'}
     )
    )
  EOT
}

# Entra ID needs a moment before a new federated credential and new role
# assignments can be used.
resource "time_sleep" "azure_propagation" {
  count = local.federation_ready ? 1 : 0

  create_duration = "90s"

  depends_on = [
    azuread_application_federated_identity_credential.flows,
    azuread_app_role_assignment.graph_user_read_all,
    azurerm_role_assignment.reader,
    azurerm_role_assignment.access_administrator,
  ]
}
