# scripts/cleanup.ps1

function Write-Status {
    param (
        [string]$Message
    )
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Test-CommandExists {
    param ($command)
    try {
        if (Get-Command $command -ErrorAction Stop) {
            return $true
        }
    }
    catch {
        return $false
    }
}

function Handle-Error {
    param(
        [string]$Message
    )
    Write-Host "`nError: $Message" -ForegroundColor Red
    Write-Host "Continuing with cleanup..." -ForegroundColor Yellow
}

# Check required tools
$requiredTools = @("terraform", "az", "kubectl", "helm")
foreach ($tool in $requiredTools) {
    if (-not (Test-CommandExists $tool)) {
        Write-Host "$tool is required but not installed. Please install it first." -ForegroundColor Red
        exit 1
    }
}

# Verify Azure login and subscription
try {
    Write-Status "Verifying Azure login..."
    $subscription = az account show --query id -o tsv
    if ($subscription -ne "37af591d-24c2-4996-8752-aee353fe49bd") {
        Write-Host "Setting correct subscription..."
        az account set --subscription "37af591d-24c2-4996-8752-aee353fe49bd"
    }
}
catch {
    Write-Status "Please login to Azure..."
    az login
    az account set --subscription "37af591d-24c2-4996-8752-aee353fe49bd"
}

Write-Host "Using subscription: $subscription"

# Get resource information from Terraform
try {
    Write-Status "Getting resource information..."
    Push-Location terraform
    $rgName = terraform output -raw resource_group_name 2>$null
    $aksName = terraform output -raw aks_name 2>$null
    $kvName = terraform output -raw key_vault_name 2>$null
    Pop-Location

    # Get AKS credentials if cluster exists
    if ($rgName -and $aksName) {
        Write-Status "Getting AKS credentials..."
        try {
            az aks get-credentials --resource-group $rgName --name $aksName --overwrite-existing
        }
        catch {
            Write-Host "Could not get AKS credentials. Cluster might already be deleted." -ForegroundColor Yellow
        }
    }
}
catch {
    Handle-Error "Could not get terraform outputs. Continuing with cleanup..."
}

# Cleanup Helm releases first
Write-Status "Cleaning up Helm releases..."
$helmReleases = @(
    @{namespace = "keycloak"; name = "keycloak"},
    @{namespace = "cert-manager"; name = "cert-manager"},
    @{namespace = "ingress-nginx"; name = "nginx-ingress"}
)

foreach ($release in $helmReleases) {
    Write-Host "Uninstalling Helm release: $($release.name) from namespace: $($release.namespace)"
    try {
        helm uninstall $release.name -n $release.namespace --timeout 5m0s
    }
    catch {
        Handle-Error "Failed to uninstall Helm release $($release.name)"
    }
}

# Cleanup Kubernetes resources
Write-Status "Cleaning up Kubernetes resources..."
$k8sNamespaces = @("keycloak", "cert-manager", "ingress-nginx")
foreach ($namespace in $k8sNamespaces) {
    Write-Host "Deleting namespace: $namespace"
    try {
        kubectl delete namespace $namespace --ignore-not-found --timeout=5m
    }
    catch {
        Handle-Error "Failed to delete namespace $namespace"
    }
}

# Clean up Key Vault secrets and prepare for deletion
if ($kvName) {
    Write-Status "Cleaning up Key Vault..."
    try {
        # Remove secrets
        Write-Host "Removing secrets from Key Vault..."
        az keyvault secret list --vault-name $kvName --query "[].name" -o tsv | ForEach-Object {
            az keyvault secret delete --vault-name $kvName --name $_
        }
        
        # Disable soft-delete protection if enabled
        Write-Host "Preparing Key Vault for deletion..."
        az keyvault update --name $kvName --resource-group $rgName --enable-soft-delete false
    }
    catch {
        Handle-Error "Failed to clean up Key Vault"
    }
}

# Cleanup Azure Resources using Terraform
Write-Status "Cleaning up Azure resources using Terraform..."
Push-Location terraform
try {
    terraform init -reconfigure
    terraform destroy -auto-approve
}
catch {
    Handle-Error "Terraform destroy failed"
    
    # Attempt manual cleanup
    Write-Status "Attempting manual cleanup..."
    
    try {
        if ($rgName) {
            Write-Host "Deleting resource group: $rgName"
            az group delete --name $rgName --yes --no-wait
        }
    }
    catch {
        Handle-Error "Manual cleanup failed"
    }
}
finally {
    Pop-Location
}

# Clean up local files and directories
Write-Status "Cleaning up local files..."
$filesToDelete = @(
    "terraform/.terraform",
    "terraform/.terraform.lock.hcl",
    "terraform/terraform.tfstate*",
    "terraform/keycloak-ingress.yaml",
    "credentials/keycloak-credentials.txt",
    "credentials/terraform-state-config.txt"
)

foreach ($file in $filesToDelete) {
    if (Test-Path $file) {
        Remove-Item -Path $file -Recurse -Force
        Write-Host "Deleted: $file"
    }
}

# Cleanup temporary kubeconfig entries
Write-Status "Cleaning up kubeconfig..."
try {
    if ($aksName) {
        kubectl config delete-context $aksName 2>$null
        kubectl config delete-cluster $aksName 2>$null
        kubectl config delete-user "clusterUser_${rgName}_${aksName}" 2>$null
    }
}
catch {
    Handle-Error "Failed to clean up kubeconfig"
}

Write-Host "Cleaning up Keycloak resources..."

# Delete Helm release
Write-Host "Deleting Helm release..."
helm delete keycloak -n keycloak --debug

# Delete ingress
Write-Host "Deleting ingress..."
kubectl delete ingress keycloak -n keycloak --ignore-not-found

# Delete certificate
Write-Host "Deleting certificate..."
kubectl delete certificate keycloak-tls -n keycloak --ignore-not-found

# Delete secrets
Write-Host "Deleting secrets..."
kubectl delete secret keycloak-admin-secret -n keycloak --ignore-not-found
kubectl delete secret keycloak-db-secret -n keycloak --ignore-not-found
kubectl delete secret keycloak-tls -n keycloak --ignore-not-found

# Delete any remaining pods
Write-Host "Deleting any remaining pods..."
kubectl delete pods --all -n keycloak --force --grace-period=0

# Wait for resources to be deleted
Write-Host "Waiting for resources to be fully deleted..."
Start-Sleep -Seconds 30

Write-Host "Cleanup completed. You can now run the deployment script again."

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "Cleanup completed!" -ForegroundColor Green
Write-Host "Resources cleaned up:" -ForegroundColor Yellow
Write-Host "- AKS Cluster and related resources" -ForegroundColor Yellow
Write-Host "- Azure Key Vault and secrets" -ForegroundColor Yellow
Write-Host "- PostgreSQL Server" -ForegroundColor Yellow
Write-Host "- Helm releases and Kubernetes resources" -ForegroundColor Yellow
Write-Host "- Local configuration files and credentials" -ForegroundColor Yellow
Write-Host "`nIf there were any errors during the cleanup process," -ForegroundColor Yellow
Write-Host "please check the Azure portal to ensure all resources are removed." -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Green