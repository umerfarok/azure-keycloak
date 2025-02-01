# deploy.ps1
function Test-CommandExists {
    param ($command)
    try { return [bool](Get-Command $command -ErrorAction Stop) }
    catch { return $false }
}

function Invoke-CommandWithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [int]$MaxAttempts = 5,
        [int]$DelaySeconds = 15
    )
    
    $attempt = 1
    while ($true) {
        try {
            & $ScriptBlock
            return
        }
        catch {
            if ($attempt -ge $MaxAttempts) {
                Write-Error "Failed after $MaxAttempts attempts: $_"
                exit 1
            }
            Write-Warning "Attempt $attempt failed. Retrying in $DelaySeconds seconds..."
            Start-Sleep -Seconds $DelaySeconds
            $attempt++
        }
    }
}

# Error handling trap
trap {
    Write-Error "DEPLOYMENT FAILED: $_"
    exit 1
}

# Validate tools
$requiredTools = @("terraform", "az", "kubectl", "helm")
foreach ($tool in $requiredTools) {
    if (-not (Test-CommandExists $tool)) {
        throw "$tool is not installed"
    }
}

# Terraform apply
Set-Location terraform
terraform init -reconfigure
Invoke-CommandWithRetry { terraform apply -auto-approve }

# Get outputs
$CLUSTER_NAME = terraform output -raw aks_name
$RG_NAME = terraform output -raw resource_group_name
$ADMIN_DOMAIN = terraform output -raw admin_domain
$API_DOMAIN = terraform output -raw api_domain

# Configure kubectl
az aks get-credentials --resource-group $RG_NAME --name $CLUSTER_NAME --overwrite-existing

# Helm setup
$HELM_CHARTS = @(
    "ingress-nginx=https://kubernetes.github.io/ingress-nginx",
    "jetstack=https://charts.jetstack.io",
    "bitnami=https://charts.bitnami.com/bitnami"
)

foreach ($chart in $HELM_CHARTS) {
    $name, $url = $chart -split '='
    helm repo add $name $url
}
helm repo update

# Install components
@('ingress-nginx', 'cert-manager', 'keycloak') | ForEach-Object {
    kubectl create namespace $_ --dry-run=client -o yaml | kubectl apply -f -
}

Invoke-CommandWithRetry {
    helm upgrade --install nginx-ingress ingress-nginx/ingress-nginx `
        --version 4.10.0 `
        --namespace ingress-nginx `
        --values ../kubernetes/nginx-ingress/values.yaml `
        --wait
}

Invoke-CommandWithRetry {
    helm upgrade --install cert-manager jetstack/cert-manager `
    --namespace cert-manager `
    --version v1.14.4 `
    --set installCRDs=true `
    --wait
}

# Apply Certificate resource
$CERTIFICATE_TEMPLATE = Get-Content ../kubernetes/cert-manager/certificate.yaml -Raw
$CERTIFICATE_TEMPLATE -replace '\${admin_domain}', $ADMIN_DOMAIN `
                      -replace '\${api_domain}', $API_DOMAIN `
                      | kubectl apply -f -

$POSTGRES_PASSWORD = az keyvault secret show --name postgres-password --vault-name (terraform output -raw key_vault_name) --query value -o tsv
$ADMIN_PASSWORD = az keyvault secret show --name keycloak-admin-password --vault-name (terraform output -raw key_vault_name) --query value -o tsv
$POSTGRES_SERVER = terraform output -raw postgres_server_fqdn
$POSTGRES_USER = "psqladmin"  
Write-Host POSTGRES_PASSWORD: $POSTGRES_PASSWORD ADMIN_PASSWORD: $ADMIN_PASSWORD
Write-Host POSTGRES_SERVER: $POSTGRES_SERVER

# Create secrets
@"
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-admin-secret
  namespace: keycloak
type: Opaque
data:
  admin-password: $([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($ADMIN_PASSWORD)))
---
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-db-secret
  namespace: keycloak
type: Opaque
data:
  username: $([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($POSTGRES_USER)))
  db-password: $([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($POSTGRES_PASSWORD)))
  host: $([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($POSTGRES_SERVER)))
"@ | kubectl apply -f -

# Wait for cert-manager
Start-Sleep -Seconds 30

# Install Keycloak
Invoke-CommandWithRetry {
    helm upgrade --install keycloak bitnami/keycloak --version 24.4.8 `
    --namespace keycloak `
    --values ../kubernetes/keycloak/values.yaml `
    --set ingress.hostname=$ADMIN_DOMAIN `
    --set adminIngress.hostname=$API_DOMAIN `
}


# Configure ingress
$INGRESS_TEMPLATE = Get-Content ../kubernetes/keycloak/ingress.yaml -Raw
$INGRESS_TEMPLATE -replace '\${admin_domain}', $ADMIN_DOMAIN `
                  -replace '\${api_domain}', $API_DOMAIN `
                  | kubectl apply -n keycloak -f -


kubectl apply -f ../kubernetes/cert-manager/cluster-issuer.yaml 
# Verify deployment
$maxRetries = 60
$retryCount = 0
do {
    $ingressService = kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller -o json | ConvertFrom-Json
    $INGRESS_IP = $ingressService.status.loadBalancer.ingress[0].ip
    if ($INGRESS_IP) { break }
    Start-Sleep -Seconds 10
    $retryCount++
} while ($retryCount -lt $maxRetries)

if (-not $INGRESS_IP) { throw "Failed to get ingress IP" }

# DNS validation
try {
    $adminLookup = Resolve-DnsName $ADMIN_DOMAIN -ErrorAction Stop
    if ($adminLookup.IPAddress -ne $INGRESS_IP) {
        Write-Warning "DNS mismatch for $ADMIN_DOMAIN (Expected: $INGRESS_IP, Actual: $($adminLookup.IPAddress))"
    }
}
catch {
    Write-Warning "DNS validation failed: $_"
}

Write-Host "Deployment successful! Ingress IP: $INGRESS_IP"
Set-Location ..