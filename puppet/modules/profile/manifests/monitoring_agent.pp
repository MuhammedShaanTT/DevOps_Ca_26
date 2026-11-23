# Class: profile::monitoring_agent
# Installs and hardens NRPE agent to report to Nagios
class profile::monitoring_agent {
  class { 'nrpe':
    nagios_server_ip => '10.0.1.20',
  }
}
