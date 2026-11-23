# Automated Infrastructure Provisioning, Configuration Management and Monitoring Using Terraform, Puppet and Nagios

**Course:** INT333 – DevOps Advance Configuration Management  
**Project Type:** Puppet + Terraform + Nagios  
**Workload:** High-Performance URL Shortener Microservice  

---

## 📁 Repository Structure

```text
int333-devops/
├── README.md                      # Comprehensive project guide and instructions
├── docs/
│   └── ARCHITECTURE.md            # In-depth architectural blueprint and port mapping
├── app/
│   ├── app.py                     # Python Flask URL Shortener with /health endpoint
│   ├── requirements.txt           # Python dependencies (Flask, Gunicorn)
│   └── urlshortener.service       # Systemd unit file for app service
├── terraform/
│   ├── versions.tf                # Terraform & AWS provider requirements
│   ├── variables.tf               # Configurable parameters (region, counts, IPs)
│   ├── main.tf                    # VPC, Subnet, IGW, and Routing
│   ├── security_groups.tf         # Least-privilege firewall rules (SSH, HTTP, Puppet, NRPE)
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
│       ├── urlshortener/          # URL shortener service, systemd unit, files
│       └── nrpe/                  # NRPE monitoring agent & command definitions
├── nagios/
│   ├── templates/
│   │   └── web_hosts.cfg.tpl      # Auto-registration template for Terraform
│   ├── services.cfg               # HTTP, Ping, NRPE check definitions
│   └── commands.cfg               # check_nrpe command definition
├── scripts/
│   └── deploy.sh                  # One-click automated deployment script
└── tests/
    └── test_cases.sh              # Automated test verification suite
```

---

## 🚀 Quick Start Guide

### Step 1: Configure AWS Credentials and Variables
1. Ensure your AWS CLI is configured:
   ```bash
   aws configure
   ```
2. Create your `terraform.tfvars`:
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```
3. Update `key_name` with the exact name of your existing AWS Key Pair (and optionally your `aws_region`).

### Step 2: One-Click Provisioning & Deployment
Run the automated deployment script from the project root:
```bash
chmod +x scripts/deploy.sh tests/test_cases.sh
./scripts/deploy.sh ~/.ssh/your-aws-key.pem
```

Or deploy manually via Terraform:
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

---

## 🌐 Accessing the Services

- **URL Shortener Web Nodes:** `http://<web-node-public-ip>/`
- **Application Health Endpoint:** `http://<web-node-public-ip>/health`
- **Nagios Monitoring Dashboard:** `http://<nagios-public-ip>/nagios4/`
  - Default Username: `nagiosadmin`
  - Default Password: `DevOpsAdmin2026!` (Configurable in `variables.tf`)

---

## 🧪 Validating Synopsis Test Cases (Section 10)

| No. | Test Scenario | Execution Command | Expected Result |
|---|---|---|---|
| 1 | Infrastructure Creation | `terraform apply` | VPC, Subnet, 4 EC2 instances created |
| 2 | Network Isolation | `nmap` or `curl` | Port 5666 accessible only by Nagios; 8140 only by subnet |
| 3 | Puppet Catalog Sync | `sudo /opt/puppetlabs/bin/puppet agent -t` | Catalog applied with 0 errors |
| 4 | URL Shortener Functional Check | `curl http://<web-ip>/health` | Returns `{"status": "UP"}` |
| 5 | **Self-Healing (Service Outage)** | `sudo systemctl stop urlshortener` then run Puppet agent | Nagios flags CRITICAL, Puppet restores service to `active` |
| 6 | **Self-Healing (Config Drift)** | Truncate `/opt/urlshortener/app.py` then run Puppet agent | Puppet reverts file to desired state |
| 7 | NRPE Metrics Check | Nagios UI Services page | CPU load, root disk usage, process checks report OK |
| 8 | Node Down Detection | `terraform state rm aws_instance.web_nodes[1]` or stop EC2 | Nagios reports Host DOWN and fires notification |
| 9 | Scale Web Nodes | Set `web_count = 3` in `terraform.tfvars` and `terraform apply` | New node `web-3` is provisioned, configured, and registered in Nagios |
| 10 | Clean Teardown | `terraform destroy` | All AWS resources terminated, zero ongoing cloud cost |

---

## 🔒 Security Best Practices Implemented
- **Least-Privilege Security Groups**: Port 8140 restricted to VPC subnet; NRPE port 5666 restricted strictly to Nagios server IP (`10.0.1.20/32`).
- **Memory Safety on t3.small**: Puppet Server JVM heap constrained to `-Xms1g -Xmx1g` to prevent OOM errors on modest lab instances.
- **Auto-signing**: Secure auto-signing configured for rapid agent registration without manual certificate management overhead.
