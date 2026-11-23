#!/bin/bash
# ==============================================================================
# INT333 DevOps Project: One-Click Deploy Script
# Provisions AWS Infra (Terraform), deploys Puppet catalogs, syncs Nagios.
# ==============================================================================
set -e

KEY_FILE="$1"
if [ -z "$KEY_FILE" ]; then
    echo "Usage: ./scripts/deploy.sh <path-to-aws-private-key.pem>"
    exit 1
fi

echo "=========================================="
echo "Phase 1: Terraform Infrastructure Provisioning"
echo "=========================================="
cd terraform
terraform init
terraform apply -auto-approve

PUPPET_IP=$(terraform output -raw puppet_master_public_ip)
NAGIOS_IP=$(terraform output -raw nagios_server_public_ip)
cd ..

echo "Waiting for EC2 instances and cloud-init bootstrap (60s)..."
sleep 60

echo "=========================================="
echo "Phase 2: Syncing Puppet Manifests & Modules"
echo "=========================================="
scp -i "$KEY_FILE" -o StrictHostKeyChecking=no -r puppet/manifests ubuntu@"$PUPPET_IP":/tmp/
scp -i "$KEY_FILE" -o StrictHostKeyChecking=no -r puppet/modules ubuntu@"$PUPPET_IP":/tmp/
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$PUPPET_IP" << 'EOF'
sudo cp -r /tmp/manifests/* /etc/puppetlabs/code/environments/production/manifests/
sudo cp -r /tmp/modules/* /etc/puppetlabs/code/environments/production/modules/
sudo chown -R root:root /etc/puppetlabs/code/environments/production/
echo "Puppet code synced successfully."
EOF

echo "=========================================="
echo "Phase 3: Syncing Auto-Generated Nagios Configs"
echo "=========================================="
scp -i "$KEY_FILE" -o StrictHostKeyChecking=no nagios/generated_hosts.cfg ubuntu@"$NAGIOS_IP":/tmp/
scp -i "$KEY_FILE" -o StrictHostKeyChecking=no nagios/services.cfg ubuntu@"$NAGIOS_IP":/tmp/
scp -i "$KEY_FILE" -o StrictHostKeyChecking=no nagios/commands.cfg ubuntu@"$NAGIOS_IP":/tmp/

ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$NAGIOS_IP" << 'EOF'
sudo cp /tmp/generated_hosts.cfg /etc/nagios4/conf.d/
sudo cp /tmp/services.cfg /etc/nagios4/conf.d/
sudo cp /tmp/commands.cfg /etc/nagios4/conf.d/
sudo /usr/sbin/nagios4 -v /etc/nagios4/nagios.cfg
sudo systemctl restart nagios4
echo "Nagios monitoring configuration active."
EOF

echo "=========================================="
echo "DEPLOYMENT COMPLETE!"
echo "Nagios Dashboard: http://$NAGIOS_IP/nagios4/"
echo "Check your web nodes directly on port 80!"
echo "=========================================="
