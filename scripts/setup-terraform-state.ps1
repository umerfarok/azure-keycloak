# setup-terraform-state.ps1

# First, clear any existing Azure CLI token issues
Remove-Item "$env:USERPROFILE\.azure\*" -Force -Recurse -ErrorAction SilentlyContinue
az logout

# Force a new login
Write-Host "Please login to Azure..."
az login

# Function to check if command was successful
function Test-AzCommand {
    param (
        [string]$Command,
        [string]$ErrorMessage
    )
    
    try {
        $result = Invoke-Expression $Command
        if ($LASTEXITCODE -ne 0) { throw $ErrorMessage }
        return $result
    }
    catch {
        Write-Host "Error: $ErrorMessage"
        Write-Host "Command failed: $Command"
        Write-Host "Error details: $_"
        exit 1
    }
}

# Get subscription ID
$SUBSCRIPTION_ID = "37af591d-24c2-4996-8752-aee353fe49bd"

# Set subscription explicitly
Write-Host "Setting subscription..."
Test-AzCommand "az account set --subscription $SUBSCRIPTION_ID" "Failed to set subscription"

# Verify subscription
$currentSub = Test-AzCommand "az account show --query id -o tsv" "Failed to get current subscription"
Write-Host "Using subscription: $currentSub"

# Set variables
$RESOURCE_GROUP_NAME = "terraform-state-rg"
$STORAGE_ACCOUNT_NAME = "tfstatenextshines"
$CONTAINER_NAME = "tfstate"
$LOCATION = "eastus"

# Create resource group
Write-Host "`nCreating resource group..."
Test-AzCommand "az group create --name $RESOURCE_GROUP_NAME --location $LOCATION --subscription $SUBSCRIPTION_ID" "Failed to create resource group"

# Create storage account
Write-Host "`nCreating storage account..."
Test-AzCommand "az storage account create --resource-group $RESOURCE_GROUP_NAME --name $STORAGE_ACCOUNT_NAME --sku Standard_LRS --encryption-services blob --allow-blob-public-access false --subscription $SUBSCRIPTION_ID" "Failed to create storage account"

# Get storage account key
Write-Host "`nGetting storage account key..."
$ACCOUNT_KEY = Test-AzCommand "az storage account keys list --resource-group $RESOURCE_GROUP_NAME --account-name $STORAGE_ACCOUNT_NAME --query '[0].value' -o tsv --subscription $SUBSCRIPTION_ID" "Failed to get storage account key"

# Create container
Write-Host "`nCreating storage container..."
Test-AzCommand "az storage container create --name $CONTAINER_NAME --account-name $STORAGE_ACCOUNT_NAME --account-key $ACCOUNT_KEY" "Failed to create container"

# Save configurations
$config = @"
Resource Group: $RESOURCE_GROUP_NAME
Storage Account: $STORAGE_ACCOUNT_NAME
Container: $CONTAINER_NAME
Subscription ID: $SUBSCRIPTION_ID
"@
$config | Out-File -FilePath "credentials/terraform-state-config.txt"

# Create backend.tf
$backend_tf = @"
terraform {
  backend "azurerm" {
    resource_group_name  = "$RESOURCE_GROUP_NAME"
    storage_account_name = "$STORAGE_ACCOUNT_NAME"
    container_name      = "$CONTAINER_NAME"
    key                = "keycloak.tfstate"
    subscription_id    = "$SUBSCRIPTION_ID"
  }
}
"@
$backend_tf | Out-File -FilePath "terraform/backend.tf"

Write-Host "`n================================================================"
Write-Host "Terraform state storage has been configured:"
Write-Host "Resource Group: $RESOURCE_GROUP_NAME"
Write-Host "Storage Account: $STORAGE_ACCOUNT_NAME"
Write-Host "Container: $CONTAINER_NAME"
Write-Host "Configuration has been saved to: credentials/terraform-state-config.txt"
Write-Host "Backend.tf has been created in the terraform folder"
Write-Host "================================================================"

# Export environment variable for Terraform
$env:ARM_ACCESS_KEY = $ACCOUNT_KEY