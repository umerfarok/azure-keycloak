output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "resource_group_id" {
  value = azurerm_resource_group.rg.id
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "aks_cluster_id" {
  value = azurerm_kubernetes_cluster.aks.id
}

output "kubernetes_cluster_host" {
  value     = azurerm_kubernetes_cluster.aks.kube_config[0].host
  sensitive = true
}

output "kubernetes_cluster_client_certificate" {
  value     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  sensitive = true
}

output "kubernetes_cluster_client_key" {
  value     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  sensitive = true
}

output "kubernetes_cluster_ca_certificate" {
  value     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  sensitive = true
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}

output "key_vault_id" {
  value = azurerm_key_vault.kv.id
}

output "postgres_server_name" {
  value = azurerm_postgresql_flexible_server.postgres.name
}

output "postgres_server_fqdn" {
  value = azurerm_postgresql_flexible_server.postgres.fqdn
}

output "postgres_connection_string" {
  value     = "postgresql://psqladmin:${random_password.postgres_password.result}@${azurerm_postgresql_flexible_server.postgres.fqdn}:5432/keycloak"
  sensitive = true
}

output "admin_domain" {
  value = "admin.nextshines.com"  # Replace with your actual domain
}

output "api_domain" {
  value = "api.nextshines.com"  # Replace with your actual domain
}



