terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # State lives in an Azure Storage blob. resource_group_name / storage_account_name /
  # container_name / key come from env/<env>/<env>.backend.tfvars via `-backend-config`
  # (see the Makefile's init target). Blob storage provides native lease-based locking,
  # so there's no DynamoDB-style lock table to provision — unlike the AWS template.
  backend "azurerm" {}
}

provider "azurerm" {
  # Required by azurerm v4 — no implicit subscription from the CLI default.
  subscription_id = var.subscription_id

  features {}
}
