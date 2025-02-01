function Get-DecodedSecret {
    param (
        [string]$namespace,
        [string]$secretName
    )
    
    $secret = kubectl get secret -n $namespace $secretName -o json | ConvertFrom-Json
    
    Write-Host "`nSecret: $secretName"
    Write-Host "========================"
    
    $secret.data.PSObject.Properties | ForEach-Object {
        $decodedValue = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_.Value))
        Write-Host "$($_.Name): $decodedValue"
    }
}

# Get all secrets in keycloak namespace
$secrets = kubectl get secrets -n keycloak -o name | ForEach-Object { $_.Replace("secret/", "") }

# Create output directory if it doesn't exist
$outputDir = "../credentials/secrets"
if (!(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Process each secret
foreach ($secret in $secrets) {
    Get-DecodedSecret -namespace "keycloak" -secretName $secret | 
        Out-File -FilePath "$outputDir/$secret.txt" -Force
}

Write-Host "`nSecrets decoded and saved to: $outputDir"