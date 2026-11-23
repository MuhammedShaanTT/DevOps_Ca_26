# Class: profile::base
# Baseline security, system utilities, and time synchronization
class profile::base {
  $base_packages = [
    'curl',
    'wget',
    'htop',
    'git',
    'unzip',
    'ufw',
    'chrony'
  ]

  package { $base_packages:
    ensure => installed,
  }

  service { 'chrony':
    ensure  => running,
    enable  => true,
    require => Package['chrony'],
  }
}
