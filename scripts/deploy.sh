#!/bin/bash
# ==============================================================================
# INT333 DevOps Project: Bash Deploy Helper Script
# Provisions AWS Infra (Terraform), deploys Puppet catalogs, syncs Nagios.
# ==============================================================================
set -e

KEY_FILE="${1:-./CA.pem}"
if [ ! -f "$KEY_FILE" ]; then
    echo "Usage: ./scripts/deploy.sh <path-to-aws-private-key.pem>"
    exit 1
fi

if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    . ./.env
    set +a
fi

SSH_OPTS="-i $KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=5"

wait_node_ready() {
    local name="$1"
    local ip="$2"
    echo "Waiting for $name ($ip) SSH, cloud-init, and sudo readiness..."
    for _ in $(seq 1 36); do
        if ssh $SSH_OPTS ubuntu@"$ip" "true" 2>/dev/null; then
            break
        fi
        sleep 5
    done
    ssh $SSH_OPTS ubuntu@"$ip" "cloud-init status --wait || true"
    for _ in $(seq 1 24); do
        if ssh $SSH_OPTS ubuntu@"$ip" "sudo -n true" 2>/dev/null; then
            return 0
        fi
        sleep 3
    done
    echo "ERROR: $name ($ip) did not finish cloud-init/sudo initialization."
    exit 1
}

echo "=========================================="
echo "Phase 1: Terraform Infrastructure Provisioning"
echo "=========================================="
cd terraform
if [ ! -d .terraform ]; then
    terraform init
fi
terraform apply -auto-approve

PUPPET_IP=$(terraform output -raw puppet_master_public_ip)
NAGIOS_IP=$(terraform output -raw nagios_server_public_ip)
if [ -z "$PUPPET_IP" ] || [ -z "$NAGIOS_IP" ]; then
    terraform apply -refresh-only -auto-approve
    PUPPET_IP=$(terraform output -raw puppet_master_public_ip)
    NAGIOS_IP=$(terraform output -raw nagios_server_public_ip)
fi
WEB_NODES=$(terraform output -json web_nodes_info | python3 -c "import sys, json; print('\n'.join(f\"{n['node_name']}:{n['public_ip']}\" for n in json.load(sys.stdin)))")
cd ..

wait_node_ready "puppet-master" "$PUPPET_IP"

echo "=========================================="
echo "Phase 2: Syncing Puppet Manifests & Modules"
echo "=========================================="
ssh $SSH_OPTS ubuntu@"$PUPPET_IP" "rm -rf /tmp/manifests /tmp/modules"
scp $SSH_OPTS -r puppet/manifests ubuntu@"$PUPPET_IP":/tmp/
scp $SSH_OPTS -r puppet/modules ubuntu@"$PUPPET_IP":/tmp/
ssh $SSH_OPTS ubuntu@"$PUPPET_IP" << 'EOF'
set -e
sudo -n mkdir -p /etc/puppetlabs/code/environments/production/manifests /etc/puppetlabs/code/environments/production/modules
sudo -n rm -rf /etc/puppetlabs/code/environments/production/modules/*
sudo -n cp -rf /tmp/manifests/* /etc/puppetlabs/code/environments/production/manifests/
sudo -n cp -rf /tmp/modules/* /etc/puppetlabs/code/environments/production/modules/
sudo -n chown -R puppet:puppet /etc/puppetlabs/code/environments/production/
for i in $(seq 1 40); do
    if ss -tln | grep -q ':8140 '; then break; fi
    sleep 3
done
ss -tln | grep -q ':8140 '
echo "Puppet Server ready on port 8140."
EOF

echo "=========================================="
echo "Phase 3: Triggering Puppet Agent on Web Nodes"
echo "=========================================="
for entry in $WEB_NODES; do
    NODE_NAME="${entry%%:*}"
    WEB_IP="${entry#*:}"
    wait_node_ready "$NODE_NAME" "$WEB_IP"
    ssh $SSH_OPTS ubuntu@"$WEB_IP" "sudo -n grep -qE '\\spuppet(\\s|$)' /etc/hosts || echo '10.0.1.10 puppet' | sudo -n tee -a /etc/hosts >/dev/null; sudo -n /opt/puppetlabs/bin/puppet agent -t --waitforlock 60 --detailed-exitcodes || rc=\$?; rc=\${rc:-0}; if [ \"\$rc\" -ne 0 ] && [ \"\$rc\" -ne 2 ]; then exit \"\$rc\"; fi; curl -sf http://127.0.0.1/health"
done

echo "=========================================="
echo "Phase 4: Syncing Auto-Generated Nagios Configs"
echo "=========================================="
wait_node_ready "nagios-server" "$NAGIOS_IP"
scp $SSH_OPTS nagios/generated_hosts.cfg ubuntu@"$NAGIOS_IP":/tmp/
scp $SSH_OPTS nagios/services.cfg ubuntu@"$NAGIOS_IP":/tmp/
scp $SSH_OPTS nagios/commands.cfg ubuntu@"$NAGIOS_IP":/tmp/

ssh $SSH_OPTS ubuntu@"$NAGIOS_IP" << 'EOF'
set -e
sudo -n cp /tmp/generated_hosts.cfg /etc/nagios4/conf.d/
sudo -n cp /tmp/services.cfg /etc/nagios4/conf.d/
sudo -n cp /tmp/commands.cfg /etc/nagios4/conf.d/
sudo -n /usr/sbin/nagios4 -v /etc/nagios4/nagios.cfg
sudo -n systemctl restart nagios4 apache2
echo "Nagios monitoring configuration active."
EOF

echo "=========================================="
echo "DEPLOYMENT COMPLETE!"
echo "Nagios Dashboard: http://$NAGIOS_IP/nagios4/"
echo "=========================================="
