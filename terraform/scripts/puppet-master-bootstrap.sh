#!/bin/bash
set -e

# Update and install dependencies
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y wget curl ca-certificates git

# Add Puppet 7 repository
wget https://apt.puppet.com/puppet7-release-jammy.deb -O /tmp/puppet7-release-jammy.deb
dpkg -i /tmp/puppet7-release-jammy.deb
apt-get update -y

# Install Puppet Server
apt-get install -y puppetserver

# Configure JVM heap size (Limit to 1GB for t3.small instance memory safety)
sed -i 's/-Xms2g -Xmx2g/-Xms1g -Xmx1g/g' /etc/default/puppetserver

# Map puppet to local IP in hosts
echo "127.0.0.1 puppet" >> /etc/hosts
echo "10.0.1.10 puppet" >> /etc/hosts

# Enable auto-signing for lab environment instances
echo "*" > /etc/puppetlabs/puppet/autosign.conf

# Start and enable Puppet Server service
systemctl daemon-reload
systemctl enable puppetserver
systemctl start puppetserver

# Add puppet binaries to PATH
echo 'export PATH=/opt/puppetlabs/bin:$PATH' >> /root/.bashrc
echo 'export PATH=/opt/puppetlabs/bin:$PATH' >> /home/ubuntu/.bashrc

echo "Puppet Server installation completed successfully."
