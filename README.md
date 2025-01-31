# README.md
# Azure Keycloak Deployment

## Prerequisites
- Windows 10/11
- Azure CLI
- Terraform
- kubectl
- Helm
- Git Bash or WSL
- Azure Subscription with Contributor access

## Installation Steps (Windows)

```powershell
# Install tools using chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

choco install azure-cli -y
choco install terraform -y
choco install kubernetes-cli -y
choco install kubernetes-helm -y
choco install git -y
```

## Deployment Steps

1. Clone the repository
2. Create `terraform.tfvars`:
```hcl
resource_group_name    = "your-rg-name"
location              = "eastus"
environment           = "dev"
keycloak_admin_domain = "admin.your-domain.com"
keycloak_api_domain   = "api.your-domain.com"
```

3. Initialize Terraform state:
```bash
./scripts/setup-terraform-state.sh
```

4. Deploy:
```bash
./scripts/deploy.sh
```

## Post-Deployment
1. Get the ingress IP from the deployment output
2. Configure your DNS records for both domains to point to this IP
3. Access Keycloak admin console at https://admin.your-domain.com
4. Credentials are stored in keycloak-credentials.txt

# In deploy.sh, modify the Keycloak installation:
helm upgrade --install keycloak bitnami/keycloak \
    --namespace keycloak \
    --values ../kubernetes/keycloak/values.yaml \
    --set adminDomain="${KEYCLOAK_ADMIN_DOMAIN}" \
    --set apiDomain="${KEYCLOAK_API_DOMAIN}" \
    --wait# azure-keycloak
