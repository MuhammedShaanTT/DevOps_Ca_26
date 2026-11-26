#!/bin/bash
# ==============================================================================
# INT333 DevOps Project: Bash Deploy Helper Script
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
WEB_IPS=$(terraform output -json web_nodes_info | python3 -c "import sys, json; print(' '.join(n['public_ip'] for n in json.load(sys.stdin)))")
cd ..

echo "Waiting for SSH and cloud-init bootstrap to complete on Puppet Master..."
for _ in $(seq 1 24); do
    if ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@"$PUPPET_IP" "true" 2>/dev/null; then
        break
    fi
    sleep 5
done
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$PUPPET_IP" "cloud-init status --wait || true"

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
echo "Phase 3: Triggering Puppet Agent on Web Nodes"
echo "=========================================="
for WEB_IP in $WEB_IPS; do
    echo "Waiting for $WEB_IP..."
    ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$WEB_IP" "cloud-init status --wait || true; sudo /opt/puppetlabs/bin/puppet agent -t || true"
done

echo "=========================================="
echo "Phase 4: Syncing Auto-Generated Nagios Configs"
echo "=========================================="
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$NAGIOS_IP" "cloud-init status --wait || true"
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
echo "Check your web nodes on port 80 or port 8080."
echo "=========================================="
