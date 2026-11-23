# Class: role::web_server
# Aggregates profiles required for a production URL Shortener web node
class role::web_server {
  include profile::base
  include profile::web
  include profile::monitoring_agent
}
