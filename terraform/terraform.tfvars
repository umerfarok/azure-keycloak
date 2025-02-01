# terraform/terraform.tfvars
resource_group_name    = "keycloak-rg"
location              = "eastus2"
environment           = "dev"
keycloak_admin_domain = "admin.nextshines.com"
keycloak_api_domain   = "api.nextshines.com"
postgres_sku_name     = "B_Standard_B1ms"
admin_domain = "admin.nextshines.com"
api_domain = "api.nextshines.com"