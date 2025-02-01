terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatenextshines"
    container_name      = "tfstate"
    key                = "keycloak.tfstate"
    subscription_id    = "37af591d-24c2-4996-8752-aee353fe49bd"
  }
}
