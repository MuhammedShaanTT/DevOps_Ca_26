#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
MASTER_IP="${master_ip}"
NODE_NAME="${node_name}"

# Set hostname
hostnamectl set-hostname "$NODE_NAME"
echo "$MASTER_IP puppet" >> /etc/hosts

# Update package index and install curl/wget
apt-get update -y
apt-get install -y wget curl git python3-flask python3-gunicorn

# Add Puppet 7 repository
wget https://apt.puppet.com/puppet7-release-jammy.deb -O /tmp/puppet7-release-jammy.deb
dpkg -i /tmp/puppet7-release-jammy.deb
apt-get update -y

# Install Puppet Agent
apt-get install -y puppet-agent

# Configure puppet.conf
cat <<EOF > /etc/puppetlabs/puppet/puppet.conf
[main]
certname = $NODE_NAME
server = puppet
environment = production
runinterval = 30m
EOF

# Add puppet binaries to PATH
echo 'export PATH=/opt/puppetlabs/bin:$PATH' >> /root/.bashrc
echo 'export PATH=/opt/puppetlabs/bin:$PATH' >> /home/ubuntu/.bashrc

# Enable and start puppet agent service
systemctl enable puppet
systemctl start puppet

# Wait a brief moment for puppet master DNS/startup, then attempt first sync
sleep 20
/opt/puppetlabs/bin/puppet agent -t || true

echo "Web node $NODE_NAME bootstrapped successfully."
