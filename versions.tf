terraform {
  required_version = "1.12.6"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "3.10.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.14.0"
    }

    flows = {
      source  = "spacelift-io/flows"
      version = "0.8.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "0.14.2"
    }
  }
}

# Authentication using the Azure CLI credentials
provider "azuread" {}

# Authentication using the Azure CLI credentials
provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
}

# Authentication comes from the FLOWS_TOKEN environment variable.
provider "flows" {
  endpoint = var.flows_endpoint
}
