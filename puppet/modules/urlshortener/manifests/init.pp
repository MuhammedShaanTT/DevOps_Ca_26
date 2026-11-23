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

  # Deploy Flask App script (Self-healing target)
  file { "${app_dir}/app.py":
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    source  => 'puppet:///modules/urlshortener/app.py',
    notify  => Service['urlshortener'],
    require => File[$app_dir],
  }

  # Install Python requirements
  exec { 'install_flask_gunicorn':
    command => '/usr/bin/pip3 install Flask==3.0.3 gunicorn==22.0.0',
    unless  => '/usr/local/bin/gunicorn --version',
    require => Package['python3-pip'],
  }

  # Systemd service unit definition
  file { '/etc/systemd/system/urlshortener.service':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => @(SERVICE)
      [Unit]
      Description=URL Shortener Flask Application (Puppet Managed)
      After=network.target

      [Service]
      User=root
      WorkingDirectory=/opt/urlshortener
      ExecStartPre=/usr/bin/python3 -c "import app; app.init_db()"
      ExecStart=/usr/local/bin/gunicorn --workers 2 --bind 127.0.0.1:5000 app:app
      Restart=always
      RestartSec=3
      Environment=PYTHONUNBUFFERED=1

      [Install]
      WantedBy=multi-user.target
      SERVICE
    ,
    notify  => [
      Exec['systemd_daemon_reload'],
      Service['urlshortener']
    ],
  }

  exec { 'systemd_daemon_reload':
    command     => '/bin/systemctl daemon-reload',
    refreshonly => true,
  }

  # Service enforcement (Self-healing target)
  service { 'urlshortener':
    ensure  => running,
    enable  => true,
    require => [
      File['/etc/systemd/system/urlshortener.service'],
      File["${app_dir}/app.py"],
      Exec['install_flask_gunicorn']
    ],
  }
}
