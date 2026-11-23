#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y wget curl apache2 php libapache2-mod-php nagios4 nagios-plugins-basic nagios-plugins-standard nagios-nrpe-plugin

# Enable apache modules
a2enmod rewrite cgi authz_groupfile

# Set nagiosadmin password
htpasswd -b -c /etc/nagios4/htpasswd.users nagiosadmin "${admin_password}"

# Ensure Nagios directory permissions
chown -R nagios:nagios /etc/nagios4/
chmod -R 755 /etc/nagios4/

# Create dynamic hosts directory for auto-registered nodes
mkdir -p /etc/nagios4/conf.d/dynamic_hosts
sed -i 's|#cfg_dir=/etc/nagios4/conf.d|cfg_dir=/etc/nagios4/conf.d|g' /etc/nagios4/nagios.cfg

# Restart web server and nagios
systemctl enable apache2
systemctl restart apache2
systemctl enable nagios4
systemctl restart nagios4

echo "Nagios Monitoring Server installation completed successfully."
