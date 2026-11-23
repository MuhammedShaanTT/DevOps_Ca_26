# /etc/puppetlabs/code/environments/production/manifests/site.pp

# Global defaults
File { backup => false }

# Node definition for Web nodes (e.g. web-1, web-2, web-3...)
node /^web-\d+$/ {
  include role::web_server
}

# Fallback default node
node default {
  include profile::base
}
