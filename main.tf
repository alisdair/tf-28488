terraform {
  # For all Terraform configuration settings, see: https://www.terraform.io/docs/configuration/terraform.html
  required_version = "~> 0.15.0"

  # Lock providers to reduce incompatibility between runs
  required_providers {
    azurerm = {
      # see: https://www.terraform.io/docs/providers/azurerm/
      source  = "hashicorp/azurerm"
      version = "~> 2.56"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true
  features {}
}

variable "location" {
  type    = string
  default = "canadacentral"
}

variable "tmp_settings" {
  description = "Addition settings used to merge with app_settings"
  type        = map(string)
  default     = { "Sensitive_Crash_Test" = "Shhh! This is a secret." }
  sensitive   = true # This will cause azurerm_key_vault_access_policy to crash Terraform.
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = "issue-28488-resources"
  location = var.location
}

resource "azurerm_key_vault" "kv" {
  name                = "vault-26959"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku_name            = "standard"
  tenant_id           = data.azurerm_client_config.current.tenant_id

  access_policy {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    object_id          = data.azurerm_client_config.current.object_id
    secret_permissions = ["delete", "get", "set"]
  }
}

resource "azurerm_app_service_plan" "plan_crash" {
  name                = "example-appserviceplan-crash"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "linux"
  reserved            = true

  sku {
    tier = "PremiumV2"
    size = "P1v2"
  }
}

resource "azurerm_app_service" "app_crash" {
  name                = "example-app-crash"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_app_service_plan.plan_crash.id

  app_settings = var.tmp_settings

  identity {
    type = "SystemAssigned"
  }
}

# This will crash Terraform because the app service has app_settings marked as sensitive.
resource "azurerm_key_vault_access_policy" "main" {
  key_vault_id       = azurerm_key_vault.kv.id
  tenant_id          = azurerm_app_service.app_crash.identity[0].tenant_id
  object_id          = azurerm_app_service.app_crash.identity[0].principal_id
  secret_permissions = ["get"]
}
