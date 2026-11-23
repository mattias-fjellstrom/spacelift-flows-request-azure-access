locals {
  slack_configured = var.slack_bot_token != "" && var.slack_signing_secret != ""
}

data "flows_app_version" "slack" {
  name    = "Slack"
  version = var.slack_app_version
}

resource "terraform_data" "slack_channel_id_version" {
  input = sha256(var.slack_channel_id)
}

resource "flows_secret" "slack_channel_id" {
  project_id = var.flows_project_id
  key        = "SLACK_CHANNEL_ID"
  value      = var.slack_channel_id

  lifecycle {
    replace_triggered_by = [terraform_data.slack_channel_id_version]
  }
}

resource "terraform_data" "slack_bot_token_version" {
  count = local.slack_configured ? 1 : 0

  input = sha256(var.slack_bot_token)
}

resource "flows_secret" "slack_bot_token" {
  count = local.slack_configured ? 1 : 0

  project_id = var.flows_project_id
  key        = "SLACK_BOT_TOKEN"
  value      = var.slack_bot_token

  lifecycle {
    replace_triggered_by = [terraform_data.slack_bot_token_version[0]]
  }
}

resource "terraform_data" "slack_signing_secret_version" {
  count = local.slack_configured ? 1 : 0

  input = sha256(var.slack_signing_secret)
}

resource "flows_secret" "slack_signing_secret" {
  count = local.slack_configured ? 1 : 0

  project_id = var.flows_project_id
  key        = "SLACK_SIGNING_SECRET"
  value      = var.slack_signing_secret

  lifecycle {
    replace_triggered_by = [terraform_data.slack_signing_secret_version[0]]
  }
}

resource "flows_app_installation" "slack" {
  project_id = var.flows_project_id
  name       = "Slack"

  app = {
    version_id = data.flows_app_version.slack.id
    custom     = false
  }

  config_fields = local.slack_configured ? {
    slackBotToken      = "secrets.SLACK_BOT_TOKEN"
    slackSigningSecret = "secrets.SLACK_SIGNING_SECRET"
  } : {}

  confirm        = true
  wait_for_ready = local.slack_configured

  depends_on = [
    flows_secret.slack_channel_id,
    flows_secret.slack_bot_token,
    flows_secret.slack_signing_secret,
  ]
}
