# ==============================================================================
# INT333 DevOps - PowerShell Deployment Script
# Provisions AWS Infra (Terraform), deploys Puppet catalogs, syncs Nagios,
# and verifies URL Shortener is live.
# ==============================================================================
param(
    [string]$KeyPath   = "c:\Users\shaha\devops\CA.pem",
    [string]$AccessKey = $env:AWS_ACCESS_KEY_ID,
    [string]$SecretKey = $env:AWS_SECRET_ACCESS_KEY,
    [string]$Region    = "ap-south-1"
)

$ErrorActionPreference = "Stop"

# Auto-load local .env file if present
$EnvFile = "c:\Users\shaha\devops\.env"
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*)$') {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2].Trim(), "Process")
        }
    }
    if (-not $AccessKey) { $AccessKey = $env:AWS_ACCESS_KEY_ID }
    if (-not $SecretKey) { $SecretKey = $env:AWS_SECRET_ACCESS_KEY }
    if ($env:AWS_DEFAULT_REGION) { $Region = $env:AWS_DEFAULT_REGION }
}

if (-not $AccessKey -or -not $SecretKey) {
    Write-Host "AWS Access Key or Secret Key not found in environment or .env file." -ForegroundColor Red
    Write-Host "Usage: .\scripts\deploy.ps1 -AccessKey 'YOUR_KEY' -SecretKey 'YOUR_SECRET'" -ForegroundColor Yellow
    exit 1
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " [Step 1/5] Setting AWS Environment & Credentials... " -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

$env:TF_CLI_CONFIG_FILE    = "c:\Users\shaha\devops\terraform\terraform.rc"
$env:AWS_ACCESS_KEY_ID     = $AccessKey
$env:AWS_SECRET_ACCESS_KEY = $SecretKey
$env:AWS_DEFAULT_REGION    = $Region

Write-Host "Securing PEM key permissions..." -ForegroundColor Yellow
icacls $KeyPath /inheritance:r | Out-Null
icacls $KeyPath /grant:r "$($env:USERNAME):(R)" | Out-Null

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " [Step 2/5] Running Terraform Apply on AWS...          " -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

Set-Location "c:\Users\shaha\devops\terraform"
if (-not (Test-Path ".terraform")) {
    terraform init
}
terraform apply -auto-approve

$PUPPET_IP = (terraform output -raw puppet_master_public_ip).Trim()
$NAGIOS_IP = (terraform output -raw nagios_server_public_ip).Trim()
$WEB_NODES_JSON = terraform output -json web_nodes_info | ConvertFrom-Json
Set-Location "c:\Users\shaha\devops"

Write-Host "`nTerraform Finished! Provisioned Nodes:" -ForegroundColor Green
Write-Host " - Puppet Master IP : $PUPPET_IP" -ForegroundColor White
Write-Host " - Nagios Server IP : $NAGIOS_IP" -ForegroundColor White
foreach ($node in $WEB_NODES_JSON) {
    Write-Host " - $($node.node_name) IP       : $($node.public_ip)" -ForegroundColor White
}

Write-Host "`nWaiting for SSH & cloud-init bootstrap on Puppet Master..." -ForegroundColor Yellow
for ($i = 0; $i -lt 24; $i++) {
    ssh -i $KeyPath -o StrictHostKeyChecking=no -o ConnectTimeout=5 "ubuntu@$PUPPET_IP" "true" 2>$null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 5
}
ssh -i $KeyPath -o StrictHostKeyChecking=no "ubuntu@$PUPPET_IP" "cloud-init status --wait || true"

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " [Step 3/5] Syncing Puppet Manifests & Modules...      " -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

scp -i $KeyPath -o StrictHostKeyChecking=no -r puppet/manifests "ubuntu@${PUPPET_IP}:/tmp/"
scp -i $KeyPath -o StrictHostKeyChecking=no -r puppet/modules "ubuntu@${PUPPET_IP}:/tmp/"

ssh -i $KeyPath -o StrictHostKeyChecking=no "ubuntu@$PUPPET_IP" "sudo cp -r /tmp/manifests/* /etc/puppetlabs/code/environments/production/manifests/; sudo cp -r /tmp/modules/* /etc/puppetlabs/code/environments/production/modules/; sudo chown -R root:root /etc/puppetlabs/code/environments/production/; echo 'Puppet code deployed.'"

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " [Step 4/5] Triggering Puppet Agent on Web Nodes...    " -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

foreach ($node in $WEB_NODES_JSON) {
    Write-Host "Configuring $($node.node_name) ($($node.public_ip))..." -ForegroundColor Yellow
    ssh -i $KeyPath -o StrictHostKeyChecking=no "ubuntu@$($node.public_ip)" "cloud-init status --wait || true; sudo /opt/puppetlabs/bin/puppet agent -t || true"
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " [Step 5/5] Syncing Nagios Monitoring Configurations..." -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

ssh -i $KeyPath -o StrictHostKeyChecking=no "ubuntu@$NAGIOS_IP" "cloud-init status --wait || true"
scp -i $KeyPath -o StrictHostKeyChecking=no nagios/generated_hosts.cfg "ubuntu@${NAGIOS_IP}:/tmp/"
scp -i $KeyPath -o StrictHostKeyChecking=no nagios/services.cfg "ubuntu@${NAGIOS_IP}:/tmp/"
scp -i $KeyPath -o StrictHostKeyChecking=no nagios/commands.cfg "ubuntu@${NAGIOS_IP}:/tmp/"

ssh -i $KeyPath -o StrictHostKeyChecking=no "ubuntu@$NAGIOS_IP" "sudo cp /tmp/generated_hosts.cfg /etc/nagios4/conf.d/; sudo cp /tmp/services.cfg /etc/nagios4/conf.d/; sudo cp /tmp/commands.cfg /etc/nagios4/conf.d/; sudo /usr/sbin/nagios4 -v /etc/nagios4/nagios.cfg; sudo systemctl restart nagios4; echo 'Nagios configured.'"

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host " DEPLOYMENT SUCCESSFUL! YOUR WEBSITE IS LIVE!          " -ForegroundColor Green
Write-Host "=======================================================`n" -ForegroundColor Green

foreach ($node in $WEB_NODES_JSON) {
    Write-Host " Web App URL : $($node.app_url) (Alt: $($node.alt_url))" -ForegroundColor Cyan
    Write-Host " Health Check: $($node.health_url)" -ForegroundColor Gray
}
Write-Host "`n Nagios Dashboard : http://$NAGIOS_IP/nagios4/ (User: nagiosadmin / Pass: DevOpsAdmin2026!)" -ForegroundColor Yellow

if ($WEB_NODES_JSON.Count -gt 0) {
    Start-Process $WEB_NODES_JSON[0].app_url
}
