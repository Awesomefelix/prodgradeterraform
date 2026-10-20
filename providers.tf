terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "tfstateproact0831154133"
    container_name       = "tfstate"
    # "key" is supplied per environment: terraform init -reconfigure -backend-config="config/backend-<env>.hcl"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }

    # Add this block to bypass the lingering DNS zone error
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
