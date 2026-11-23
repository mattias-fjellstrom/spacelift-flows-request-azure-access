data "flows_app_version" "azure_oidc" {
  count = local.azure_enabled ? 1 : 0

  name    = "Azure OIDC"
  version = "0.2.0"
}

resource "flows_app_installation" "azure" {
  count = local.azure_enabled ? 1 : 0

  project_id = var.flows_project_id
  name       = "Azure OIDC"

  app = {
    version_id = one(data.flows_app_version.azure_oidc).id
    custom     = false
  }

  config_fields = {
    clientId = jsonencode(one(azuread_application.flows).client_id)
    tenantId = jsonencode(one(data.azuread_client_config.current).tenant_id)
    services = jsonencode({
      management = "https://management.azure.com"
      graph      = "https://graph.microsoft.com"
    })
    azureSetupComplete = jsonencode(local.federation_ready)
  }

  confirm        = true
  wait_for_ready = local.federation_ready

  depends_on = [time_sleep.azure_propagation]
}

locals {
  flow_definition = var.enable_agent_mcp ? "flow-with-mcp.yaml" : "flow.yaml"

  azure_settings = local.azure_enabled ? {
    AZURE_SUBSCRIPTION_ID = var.subscription_id
    AZURE_ROLES           = jsonencode(local.roles)
    AZURE_IDENTITIES = jsonencode({
      for login, identity in var.requester_identities : lower(trimspace(login)) => trimspace(identity)
    })
  } : {}

  flow_tables = var.rollout_stage >= 3 ? yamldecode(file("${path.module}/tables.yaml")).dataTables : {}

  flow_columns = merge({}, [
    for table_key, table in local.flow_tables : {
      for column in table.schema.columns : "${table_key}/${column.name}" => {
        table = table_key
        name  = column.name
        type  = column.type
      }
    }
  ]...)

  flow_tables_section = length(local.flow_tables) == 0 ? "" : yamlencode({
    dataTables = {
      for key, table in local.flow_tables : key => merge(table, { id = flows_data_table.this[key].id })
    }
  })
}

resource "terraform_data" "azure_setting_version" {
  for_each = toset(nonsensitive(keys(local.azure_settings)))

  input = sha256(local.azure_settings[each.key])
}

resource "flows_secret" "azure_setting" {
  for_each = toset(nonsensitive(keys(local.azure_settings)))

  project_id = var.flows_project_id
  key        = each.key
  value      = local.azure_settings[each.key]

  lifecycle {
    replace_triggered_by = [terraform_data.azure_setting_version[each.key]]
  }
}

resource "terraform_data" "flow_prerequisites" {
  count = var.rollout_stage >= 3 ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.slack_configured
      error_message = "Complete the Slack setup and then set rollout_stage = 3."
    }

    precondition {
      condition     = local.federation_ready
      error_message = "Complete the Azure installation setup, set flows_oidc_issuer_url, and then set rollout_stage = 3."
    }
  }
}

resource "flows_data_table" "this" {
  for_each = local.flow_tables

  project_id = var.flows_project_id
  name       = each.value.name

  lifecycle {
    precondition {
      condition     = each.key == each.value.name
      error_message = "The key of data table \"${each.key}\" in tables.yaml must be the same as its name (\"${each.value.name}\")."
    }
  }
}

resource "flows_data_table_column" "this" {
  for_each = local.flow_columns

  data_table_id = flows_data_table.this[each.value.table].id
  name          = each.value.name
  type          = each.value.type
}

resource "flows_flow" "this" {
  count = var.rollout_stage >= 3 ? 1 : 0

  project_id = var.flows_project_id
  name       = "Azure Access Requests"
  definition = "${local.flow_tables_section}${file("${path.module}/${local.flow_definition}")}"
  # definition  = "${file("${path.module}/tables.yaml")}${file("${path.module}/flow.yaml")}"
  enabled     = true
  event_limit = null

  app_installation_mapping = {
    azure = one(flows_app_installation.azure).id
    slack = flows_app_installation.slack.id
  }

  depends_on = [
    terraform_data.flow_prerequisites,
    flows_data_table_column.this,
    flows_secret.azure_setting,
  ]
}

resource "flows_data_table_attachment" "this" {
  for_each = local.flow_tables

  data_table_id = flows_data_table.this[each.key].id
  flow_id       = one(flows_flow.this).id
}
