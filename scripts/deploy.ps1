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

$ProjectRoot = Split-Path -Parent $PSScriptRoot
if ($KeyPath -eq "c:\Users\shaha\devops\CA.pem") {
    $KeyPath = Join-Path $ProjectRoot "CA.pem"
}

# Auto-load local .env file if present
$EnvFile = Join-Path $ProjectRoot ".env"
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

if (-not (Test-Path $KeyPath)) {
    Write-Host "SSH private key not found at: $KeyPath" -ForegroundColor Red
    exit 1
}

$ScpOpts = @(
    "-i", $KeyPath,
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=NUL",
    "-o", "BatchMode=yes",
    "-o", "LogLevel=ERROR",
    "-o", "ConnectTimeout=5"
)
$SshOpts = @("-T") + $ScpOpts

function Invoke-Checked {
    param(
        [string]$Description,
        [scriptblock]$Command
    )
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $global:LASTEXITCODE = 0
        & $Command
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prevEap
    }
    if ($exitCode -ne 0) {
        throw "$Description failed with exit code $exitCode"
    }
}

function Wait-NodeReady {
    param(
        [string]$NodeName,
        [string]$PublicIp
    )
    if ([string]::IsNullOrWhiteSpace($PublicIp)) {
        throw "$NodeName has no public IP address."
    }

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        Write-Host "Waiting for $NodeName ($PublicIp) SSH access..." -ForegroundColor Yellow
        $sshReady = $false
        for ($i = 0; $i -lt 36; $i++) {
            $global:LASTEXITCODE = 0
            & ssh @SshOpts "ubuntu@$PublicIp" "true" 2>$null
            if ($LASTEXITCODE -eq 0) {
                $sshReady = $true
                break
            }
            Start-Sleep -Seconds 5
        }
        if (-not $sshReady) {
            throw "Timed out waiting for SSH on $NodeName ($PublicIp)."
        }

        Write-Host "Waiting for cloud-init and sudo readiness on $NodeName..." -ForegroundColor Yellow
        & ssh @SshOpts "ubuntu@$PublicIp" "cloud-init status --wait || true"

        $sudoReady = $false
        for ($i = 0; $i -lt 24; $i++) {
            $global:LASTEXITCODE = 0
            & ssh @SshOpts "ubuntu@$PublicIp" "sudo -n true" 2>$null
            if ($LASTEXITCODE -eq 0) {
                $sudoReady = $true
                break
            }
            Start-Sleep -Seconds 3
        }
        if (-not $sudoReady) {
            throw "Timed out waiting for passwordless sudo readiness on $NodeName ($PublicIp)."
        }
    }
    finally {
        $ErrorActionPreference = $prevEap
    }
}

function Read-TerraformOutputs {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $puppetIp = (& terraform output -raw puppet_master_public_ip 2>$null)
        $nagiosIp = (& terraform output -raw nagios_server_public_ip 2>$null)
        $webNodes = (& terraform output -json web_nodes_info | ConvertFrom-Json)
    }
    finally {
        $ErrorActionPreference = $prevEap
    }
    return [PSCustomObject]@{
        PuppetIp = if ($puppetIp) { $puppetIp.Trim() } else { "" }
        NagiosIp = if ($nagiosIp) { $nagiosIp.Trim() } else { "" }
        WebNodes = $webNodes
    }
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " [Step 1/5] Setting AWS Environment & Credentials... " -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

if (-not $env:TF_CLI_CONFIG_FILE) {
    $env:TF_CLI_CONFIG_FILE = Join-Path $ProjectRoot "terraform\terraform.rc"
}
$env:AWS_ACCESS_KEY_ID     = $AccessKey
$env:AWS_SECRET_ACCESS_KEY = $SecretKey
$env:AWS_DEFAULT_REGION    = $Region

Write-Host "Securing PEM key permissions..." -ForegroundColor Yellow
icacls $KeyPath /inheritance:r | Out-Null
icacls $KeyPath /grant:r "$($env:USERNAME):(R)" | Out-Null

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " [Step 2/5] Running Terraform Apply on AWS...          " -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

Set-Location (Join-Path $ProjectRoot "terraform")
try {
    if (-not (Test-Path ".terraform")) {
        Invoke-Checked "terraform init" { terraform init }
    }
    Invoke-Checked "terraform apply" { terraform apply -auto-approve }

    $tfOut = Read-TerraformOutputs
    $needsRefresh = [string]::IsNullOrWhiteSpace($tfOut.PuppetIp) -or
                    [string]::IsNullOrWhiteSpace($tfOut.NagiosIp) -or
                    ($tfOut.WebNodes | Where-Object { [string]::IsNullOrWhiteSpace($_.public_ip) }).Count -gt 0

    if ($needsRefresh) {
        Write-Host "Refreshing Terraform state to capture newly started instance IPs..." -ForegroundColor Yellow
        Invoke-Checked "terraform refresh" { terraform apply -refresh-only -auto-approve }
        $tfOut = Read-TerraformOutputs
    }
}
finally {
    Set-Location $ProjectRoot
}

$PUPPET_IP      = $tfOut.PuppetIp
$NAGIOS_IP      = $tfOut.NagiosIp
$WEB_NODES_JSON = $tfOut.WebNodes

if ([string]::IsNullOrWhiteSpace($PUPPET_IP) -or [string]::IsNullOrWhiteSpace($NAGIOS_IP)) {
    throw "Missing Puppet or Nagios public IP after Terraform apply."
}

Write-Host "`nTerraform Finished! Provisioned Nodes:" -ForegroundColor Green
Write-Host " - Puppet Master IP : $PUPPET_IP" -ForegroundColor White
Write-Host " - Nagios Server IP : $NAGIOS_IP" -ForegroundColor White
foreach ($node in $WEB_NODES_JSON) {
    Write-Host " - $($node.node_name) IP       : $($node.public_ip)" -ForegroundColor White
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " [Step 3/5] Syncing Puppet Manifests & Modules...      " -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

Wait-NodeReady -NodeName "puppet-master" -PublicIp $PUPPET_IP

Invoke-Checked "Clean remote /tmp Puppet staging" {
    & ssh @SshOpts "ubuntu@$PUPPET_IP" "rm -rf /tmp/manifests /tmp/modules"
}
Invoke-Checked "SCP Puppet manifests" {
    & scp @ScpOpts -r "puppet/manifests" "ubuntu@${PUPPET_IP}:/tmp/"
}
Invoke-Checked "SCP Puppet modules" {
    & scp @ScpOpts -r "puppet/modules" "ubuntu@${PUPPET_IP}:/tmp/"
}

$masterDeployCmd = @'
set -e
sudo -n mkdir -p /etc/puppetlabs/code/environments/production/manifests /etc/puppetlabs/code/environments/production/modules
sudo -n rm -rf /etc/puppetlabs/code/environments/production/modules/*
sudo -n cp -rf /tmp/manifests/* /etc/puppetlabs/code/environments/production/manifests/
sudo -n cp -rf /tmp/modules/* /etc/puppetlabs/code/environments/production/modules/
sudo -n chown -R puppet:puppet /etc/puppetlabs/code/environments/production/
sudo -n grep -qE '^127\.0\.0\.1[[:space:]]+puppet([[:space:]]|$)' /etc/hosts || echo '127.0.0.1 puppet' | sudo -n tee -a /etc/hosts >/dev/null
sudo -n grep -qE '^10\.0\.1\.10[[:space:]]+puppet([[:space:]]|$)' /etc/hosts || echo '10.0.1.10 puppet' | sudo -n tee -a /etc/hosts >/dev/null
for i in $(seq 1 40); do
    if ss -tln | grep -q ':8140 '; then break; fi
    sleep 3
done
ss -tln | grep -q ':8140 '
echo "Puppet code deployed and Puppet Server listening on port 8140."
'@

Invoke-Checked "Deploy Puppet code & verify port 8140" {
    $masterDeployCmd | & ssh @SshOpts "ubuntu@$PUPPET_IP" "tr -d '\r' | bash -s"
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " [Step 4/5] Triggering Puppet Agent on Web Nodes...    " -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

foreach ($node in $WEB_NODES_JSON) {
    Write-Host "Configuring $($node.node_name) ($($node.public_ip))..." -ForegroundColor Yellow
    Wait-NodeReady -NodeName $node.node_name -PublicIp $node.public_ip

    $agentCmd = @"
set -e
sudo -n hostnamectl set-hostname $($node.node_name)
sudo -n grep -qE '^10\.0\.1\.10[[:space:]]+puppet([[:space:]]|$)' /etc/hosts || echo '10.0.1.10 puppet' | sudo -n tee -a /etc/hosts >/dev/null
sudo -n /opt/puppetlabs/bin/puppet config set certname $($node.node_name) --section main
sudo -n /opt/puppetlabs/bin/puppet config set server puppet --section main
rc=0
sudo -n /opt/puppetlabs/bin/puppet agent -t --waitforlock 60 --detailed-exitcodes || rc=`$?
if [ "`$rc" -ne 0 ] && [ "`$rc" -ne 2 ]; then
    exit "`$rc"
fi
curl -sf http://127.0.0.1/health
echo ""
"@

    Invoke-Checked "Puppet agent sync on $($node.node_name)" {
        $agentCmd | & ssh @SshOpts "ubuntu@$($node.public_ip)" "tr -d '\r' | bash -s"
    }
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " [Step 5/5] Syncing Nagios Monitoring Configurations..." -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

Wait-NodeReady -NodeName "nagios-server" -PublicIp $NAGIOS_IP

Invoke-Checked "SCP generated_hosts.cfg" {
    & scp @ScpOpts "nagios/generated_hosts.cfg" "ubuntu@${NAGIOS_IP}:/tmp/"
}
Invoke-Checked "SCP services.cfg" {
    & scp @ScpOpts "nagios/services.cfg" "ubuntu@${NAGIOS_IP}:/tmp/"
}
Invoke-Checked "SCP commands.cfg" {
    & scp @ScpOpts "nagios/commands.cfg" "ubuntu@${NAGIOS_IP}:/tmp/"
}

$nagiosSyncCmd = @'
set -e
sudo -n cp /tmp/generated_hosts.cfg /etc/nagios4/conf.d/
sudo -n cp /tmp/services.cfg /etc/nagios4/conf.d/
sudo -n cp /tmp/commands.cfg /etc/nagios4/conf.d/
sudo -n /usr/sbin/nagios4 -v /etc/nagios4/nagios.cfg
sudo -n systemctl restart nagios4 apache2
sudo -n systemctl is-active --quiet nagios4
sudo -n systemctl is-active --quiet apache2
echo "Nagios monitoring verified and active."
'@

Invoke-Checked "Configure and verify Nagios" {
    $nagiosSyncCmd | & ssh @SshOpts "ubuntu@$NAGIOS_IP" "tr -d '\r' | bash -s"
}

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host " DEPLOYMENT SUCCESSFUL! YOUR WEBSITE IS LIVE!          " -ForegroundColor Green
Write-Host "=======================================================`n" -ForegroundColor Green

foreach ($node in $WEB_NODES_JSON) {
    Write-Host " Web App URL : $($node.app_url) (Alt: $($node.alt_url))" -ForegroundColor Cyan
    Write-Host " Health Check: $($node.health_url)" -ForegroundColor Gray
}
Write-Host "`n Nagios Dashboard : http://$NAGIOS_IP/nagios4/ (User: nagiosadmin / Pass: DevOpsAdmin2026!)" -ForegroundColor Yellow

if ($WEB_NODES_JSON.Count -gt 0 -and $env:TERM_PROGRAM -ne "antigravity" -and -not $env:NO_BROWSER) {
    Start-Process $WEB_NODES_JSON[0].app_url
}
