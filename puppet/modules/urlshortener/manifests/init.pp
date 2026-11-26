# Class: urlshortener
# Deploys Python Flask application managed by Systemd
class urlshortener (
  String $app_dir = '/opt/urlshortener',
  String $port    = '5000'
) {
  $python_packages = [
    'python3',
    'python3-pip',
    'python3-venv',
    'python3-flask',
    'python3-gunicorn',
    'sqlite3'
  ]

  package { $python_packages:
    ensure => installed,
  }

  file { $app_dir:
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { "${app_dir}/app.py":
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    source  => 'puppet:///modules/urlshortener/app.py',
    notify  => Service['urlshortener'],
    require => File[$app_dir],
  }

  file { '/etc/systemd/system/urlshortener.service':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => @("SERVICE")
      [Unit]
      Description=URL Shortener Flask Application (Puppet Managed)
      After=network.target

      [Service]
      User=root
      WorkingDirectory=${app_dir}
      ExecStartPre=/usr/bin/python3 -c "import app; app.init_db()"
      ExecStart=/usr/bin/python3 -m gunicorn --workers 2 --bind 127.0.0.1:${port} app:app
      Restart=always
      RestartSec=3
      Environment=PYTHONUNBUFFERED=1

      [Install]
      WantedBy=multi-user.target
      SERVICE
    ,
    notify  => Exec['systemd_daemon_reload'],
  }

  exec { 'systemd_daemon_reload':
    command     => '/bin/systemctl daemon-reload',
    refreshonly => true,
    before      => Service['urlshortener'],
    notify      => Service['urlshortener'],
  }

  service { 'urlshortener':
    ensure  => running,
    enable  => true,
    require => [
      File['/etc/systemd/system/urlshortener.service'],
      File["${app_dir}/app.py"],
      Package['python3-flask'],
      Package['python3-gunicorn']
    ],
  }
}
