# Class: profile::web
# Configures Nginx reverse proxy and URL Shortener microservice
class profile::web {
  # 1. Install & configure Nginx reverse proxy
  package { 'nginx':
    ensure => installed,
  }

  service { 'nginx':
    ensure    => running,
    enable    => true,
    subscribe => File['/etc/nginx/sites-available/default'],
    require   => Package['nginx'],
  }

  file { '/etc/nginx/sites-available/default':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => @(CONF)
      server {
          listen 80 default_server;
          listen [::]:80 default_server;

          server_name _;

          location / {
              proxy_pass http://127.0.0.1:5000;
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
          }

          location /health {
              proxy_pass http://127.0.0.1:5000/health;
              access_log off;
          }
      }
      CONF
    ,
    notify  => Service['nginx'],
    require => Package['nginx'],
  }

  # 2. Deploy URL Shortener Application
  class { 'urlshortener':
    require => Package['nginx'],
  }
}
