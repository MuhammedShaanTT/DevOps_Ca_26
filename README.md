# Automated Infrastructure Provisioning, Configuration Management and Monitoring Using Terraform, Puppet and Nagios

**Course:** INT333 - DevOps Advance Configuration Management  
**Project Type:** Puppet + Terraform + Nagios  
**Workload:** URL Shortener Microservice  

---

## Repository Structure

```text
devops/
├── .github/workflows/
│   └── devops-pipeline.yml        # GitHub Actions CI (Pytest, Flake8, Terraform, Puppet Lint)
├── README.md                      # Project guide and manual deployment/destroy commands
├── docs/
│   └── ARCHITECTURE.md            # Architectural blueprint and port mapping
├── app/
│   ├── app.py                     # Python Flask URL Shortener with /health endpoint
│   ├── requirements.txt           # Python dependencies (Flask, Gunicorn)
│   └── urlshortener.service       # Systemd unit file reference
├── terraform/
│   ├── versions.tf                # Terraform & AWS provider requirements
│   ├── variables.tf               # Configurable parameters (region, counts, IPs)
│   ├── main.tf                    # VPC, Subnet, IGW, and Routing
│   ├── security_groups.tf         # Firewall rules (SSH, HTTP 80/8080, Puppet 8140, NRPE 5666)
│   ├── instances.tf               # EC2 definitions (Puppet Master, Nagios, Web Nodes)
│   ├── outputs.tf                 # Public/Private IPs, SSH commands, Dashboard URLs
│   ├── terraform.tfvars.example   # Example user variables template
│   └── scripts/                   # User-data bootstrap scripts
│       ├── puppet-master-bootstrap.sh
│       ├── nagios-bootstrap.sh
│       └── web-node-bootstrap.sh
├── puppet/
│   ├── manifests/
│   │   └── site.pp                # Node matching and role assignment
│   └── modules/
│       ├── role/                  # Role definitions (role::web_server)
│       ├── profile/               # Profiles (profile::base, web, monitoring_agent)
│       ├── urlshortener/          # URL shortener app, systemd service, files
│       └── nrpe/                  # NRPE monitoring agent & check commands
├── nagios/
│   ├── templates/
│   │   └── web_hosts.cfg.tpl      # Auto-registration template for Terraform
│   ├── generated_hosts.cfg        # Auto-generated host definitions
│   ├── services.cfg               # PING, SSH, HTTP /health, and NRPE service checks
│   └── commands.cfg               # Custom HTTP health check command definition
├── scripts/
│   ├── deploy.ps1                 # Optional PowerShell deployment script
│   └── deploy.sh                  # Optional Bash deployment script
└── tests/
    ├── test_app.py                # Python unit tests (pytest)
    └── test_cases.sh              # Live infrastructure & self-healing verification script
```

---

## Manual Deployment Commands (Windows PowerShell)

### Step 1: Load `.env` and Set Key Permissions
Copy `.env.example` to `.env` once and fill in your AWS keys (`.env` is gitignored so your credentials stay local). Then load it in PowerShell from `c:\Users\shaha\devops`:
```powershell
Set-Location "c:\Users\shaha\devops"

Get-Content .\.env | ForEach-Object { if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2].Trim(), "Process") } }

icacls .\CA.pem /inheritance:r
icacls .\CA.pem /grant:r "$($env:USERNAME):(R)"
```
*(Ensure `terraform/terraform.tfvars` exists based on `terraform/terraform.tfvars.example` with your `key_name`.)*

### Step 2: Provision AWS Infrastructure with Terraform
```powershell
Set-Location "c:\Users\shaha\devops\terraform"
terraform init
terraform apply -auto-approve

$PUPPET_IP = (terraform output -raw puppet_master_public_ip).Trim()
$NAGIOS_IP = (terraform output -raw nagios_server_public_ip).Trim()
$WEB_NODES = terraform output -json web_nodes_info | ConvertFrom-Json
Set-Location "c:\Users\shaha\devops"
```

### Step 3: Wait for Bootstrap and Sync Puppet Manifests to Puppet Master
Wait for `cloud-init` on the Puppet Master to finish installing `puppetserver`, then copy manifests and modules:
```powershell
ssh -i .\CA.pem -o StrictHostKeyChecking=no ubuntu@$PUPPET_IP "cloud-init status --wait"

scp -i .\CA.pem -o StrictHostKeyChecking=no -r .\puppet\manifests "ubuntu@${PUPPET_IP}:/tmp/"
scp -i .\CA.pem -o StrictHostKeyChecking=no -r .\puppet\modules "ubuntu@${PUPPET_IP}:/tmp/"

ssh -i .\CA.pem -o StrictHostKeyChecking=no ubuntu@$PUPPET_IP "sudo cp -r /tmp/manifests/* /etc/puppetlabs/code/environments/production/manifests/; sudo cp -r /tmp/modules/* /etc/puppetlabs/code/environments/production/modules/; sudo chown -R root:root /etc/puppetlabs/code/environments/production/"
```

### Step 4: Run Puppet Agent on Web Nodes
```powershell
foreach ($node in $WEB_NODES) {
    ssh -i .\CA.pem -o StrictHostKeyChecking=no "ubuntu@$($node.public_ip)" "cloud-init status --wait; sudo /opt/puppetlabs/bin/puppet agent -t"
}
```
*(Note: Puppet exit code `2` indicates changes were applied successfully.)*

### Step 5: Sync Nagios Configuration and Restart Nagios
```powershell
ssh -i .\CA.pem -o StrictHostKeyChecking=no ubuntu@$NAGIOS_IP "cloud-init status --wait"

scp -i .\CA.pem -o StrictHostKeyChecking=no .\nagios\generated_hosts.cfg "ubuntu@${NAGIOS_IP}:/tmp/"
scp -i .\CA.pem -o StrictHostKeyChecking=no .\nagios\services.cfg "ubuntu@${NAGIOS_IP}:/tmp/"
scp -i .\CA.pem -o StrictHostKeyChecking=no .\nagios\commands.cfg "ubuntu@${NAGIOS_IP}:/tmp/"

ssh -i .\CA.pem -o StrictHostKeyChecking=no ubuntu@$NAGIOS_IP "sudo cp /tmp/generated_hosts.cfg /etc/nagios4/conf.d/; sudo cp /tmp/services.cfg /etc/nagios4/conf.d/; sudo cp /tmp/commands.cfg /etc/nagios4/conf.d/; sudo /usr/sbin/nagios4 -v /etc/nagios4/nagios.cfg; sudo systemctl restart nagios4"
```

---

## Manual Destroy Commands (Clean Teardown)

Run inside PowerShell to terminate all EC2 instances, security groups, and VPC resources:
```powershell
Set-Location "c:\Users\shaha\devops"
Get-Content .\.env | ForEach-Object { if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2].Trim(), "Process") } }

Set-Location "c:\Users\shaha\devops\terraform"
terraform destroy -auto-approve
```

---

## Accessing the Services

- **URL Shortener Web Nodes:** `http://<web-node-public-ip>/` (or `http://<web-node-public-ip>:8080/` if port 80 is filtered)
- **Application Health Endpoint:** `http://<web-node-public-ip>/health`
- **Nagios Monitoring Dashboard:** `http://<nagios-public-ip>/nagios4/`
  - Username: `nagiosadmin`
  - Password: `DevOpsAdmin2026!` (Configurable in `terraform/variables.tf`)

---

## Verification & Test Cases

| No. | Test Scenario | Execution Command | Expected Result |
|---|---|---|---|
| 1 | Unit Tests (Local/CI) | `python -m pytest tests/test_app.py -v` | All 5 tests pass |
| 2 | Infrastructure Creation | `terraform apply` | VPC, Subnet, 4 EC2 instances created |
| 3 | Network Isolation | `nmap` or Security Group review | Port 5666 open only to `10.0.1.20/32`; 8140 open only to `10.0.1.0/24` |
| 4 | Puppet Catalog Sync | `sudo /opt/puppetlabs/bin/puppet agent -t` | Catalog applied with 0 errors |
| 5 | URL Shortener Health Check | `curl http://<web-ip>/health` | Returns `{"status": "UP", ...}` |
| 6 | Self-Healing (Service Outage) | `sudo systemctl stop urlshortener` then run Puppet agent | Nagios flags CRITICAL, Puppet restores service to `active` |
| 7 | Self-Healing (Config Drift) | Overwrite `/opt/urlshortener/app.py` then run Puppet agent | Puppet restores file to desired state |
| 8 | NRPE Metrics Check | Nagios UI Services page | CPU load, disk usage, Gunicorn & Nginx process checks report OK |
| 9 | Scale Web Nodes | Set `web_count = 3` in `terraform.tfvars` and `terraform apply` | `web-3` provisioned, configured, and registered in Nagios |
| 10 | Clean Teardown | `terraform destroy` | All AWS resources terminated |
