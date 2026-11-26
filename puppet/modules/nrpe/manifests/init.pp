# Class: nrpe
# Configures Nagios Remote Plugin Executor (NRPE)
class nrpe (
  String $nagios_server_ip = '10.0.1.20'
) {
  $nrpe_packages = [
    'nagios-nrpe-server',
    'monitoring-plugins-basic',
    'monitoring-plugins-standard'
  ]

  package { $nrpe_packages:
    ensure => installed,
  }

  file { '/etc/nagios/nrpe.cfg':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => @("NRPECFG")
      log_facility=daemon
      pid_file=/var/run/nagios/nrpe.pid
      server_port=5666
      nrpe_user=nagios
      nrpe_group=nagios
      allowed_hosts=127.0.0.1,::1,${nagios_server_ip}
      dont_blame_nrpe=0
      allow_bash_command_substitution=0

      # Command Definitions checked by Nagios Server
      command[check_users]=/usr/lib/nagios/plugins/check_users -w 5 -c 10
      command[check_load]=/usr/lib/nagios/plugins/check_load -r -w 1.5,1.5,1.5 -c 3.0,3.0,3.0
      command[check_disk]=/usr/lib/nagios/plugins/check_disk -w 20% -c 10% -p /
      command[check_total_procs]=/usr/lib/nagios/plugins/check_procs -w 150 -c 200
      command[check_zombie_procs]=/usr/lib/nagios/plugins/check_procs -w 5 -c 10 -s Z
      command[check_urlshortener_proc]=/usr/lib/nagios/plugins/check_procs -c 1:10 -C python3 -a app:app
      command[check_nginx_proc]=/usr/lib/nagios/plugins/check_procs -c 1:10 -C nginx
      NRPECFG
    ,
    notify  => Service['nagios-nrpe-server'],
    require => Package['nagios-nrpe-server'],
  }

  service { 'nagios-nrpe-server':
    ensure  => running,
    enable  => true,
    require => File['/etc/nagios/nrpe.cfg'],
  }
}
