# Azure Access Requests with Spacelift Flows

This OpenTofu example deploys a Spacelift Flow that handles temporary Azure
access requests. A developer requests access, a platform engineer approves it
in Slack, and the flow assigns and later revokes the Azure role. Requests are
recorded in a Flows data table.

## Prerequisites

- [OpenTofu](https://opentofu.org/) 1.12.6.
- A Spacelift Flows organization, project, and API key with permission to
  manage Flows, app installations, secrets, and data tables in that project.
- A Slack workspace and permission to create and install a Slack app.
- An Azure subscription, plus
  [Azure CLI](https://learn.microsoft.com/cli/azure/) signed in with an
  identity that can create Entra ID applications, grant Microsoft Graph
  `User.Read.All` admin consent, and create subscription role assignments.
- A Slack approval channel and the requesters' identities in the same Entra ID
  tenant.

## Deploy

1. Export the Flows API key and copy the example variables:

   ```sh
   export FLOWS_TOKEN=sfapi_...
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Set `flows_project_id` and `slack_channel_id` in `terraform.tfvars`, keeping
   `rollout_stage = 1`. Then initialize OpenTofu and create the Slack
   installation:

   ```sh
   tofu init
   tofu apply
   ```

3. In Flows, open **Apps > Slack** and complete the guided setup. Copy the
   generated app's bot token and signing secret into `terraform.tfvars`, apply
   again, and invite the app to the approval channel:

   ```sh
   tofu apply
   ```

4. Set `subscription_id` and change `rollout_stage` to `2`. Apply once to
   create the Azure resources:

   ```sh
   tofu apply
   ```

   Open **Apps > Azure OIDC** in Flows, copy the issuer URL, and set it as
   `flows_oidc_issuer_url` in `terraform.tfvars`. Apply again to create the
   federated credential:

   ```sh
   tofu apply
   ```

5. Change `rollout_stage` to `3` and deploy the flow:

   ```sh
   tofu apply
   ```

The default flow uses a form. Set `enable_agent_mcp = true` before the final
apply to deploy the MCP-enabled `flow-with-mcp.yaml` variant instead.

Use `flows_endpoint = "https://useflows.us"` for a project on the US Flows
instance (defaults to `https://useflows.us`).

## Try and remove the example

Open the deployed **Azure Access Requests** flow, submit a request for a
short-lived role, and approve it in Slack. The grant is removed automatically
at expiry.

Before destroying the OpenTofu configuration, remove any active grants in Azure;
assignments created by the running flow are not part of the OpenTofu state:

```sh
tofu destroy
```
