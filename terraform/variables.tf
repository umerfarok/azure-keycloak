# terrform/variables.tf 
variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
}

variable "location" {
  type        = string
  description = "Azure region for resources"
  default     = "eastus2"
}

variable "keycloak_admin_domain" {
  type        = string
  description = "Domain for Keycloak admin console"
}

variable "keycloak_api_domain" {
  type        = string
  description = "Domain for Keycloak API"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, prod, etc.)"
}

variable "postgres_sku_name" {
  type        = string
  description = "SKU name for PostgreSQL"
  default     = "B_Standard_B1ms"
}

variable "admin_domain" {
  type        = string
  description = "Domain for Keycloak admin interface"
}

variable "api_domain" {
  type        = string
  description = "Domain for Keycloak API"
}