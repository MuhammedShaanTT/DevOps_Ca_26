output "puppet_master_public_ip" {
  description = "Public IP of Puppet Master"
  value       = aws_instance.puppet_master.public_ip
}

output "puppet_master_private_ip" {
  description = "Private IP of Puppet Master"
  value       = aws_instance.puppet_master.private_ip
}

output "nagios_server_public_ip" {
  description = "Public IP of Nagios Server"
  value       = aws_instance.nagios_server.public_ip
}

output "nagios_server_private_ip" {
  description = "Private IP of Nagios Server"
  value       = aws_instance.nagios_server.private_ip
}

output "nagios_web_url" {
  description = "Nagios Web Dashboard URL"
  value       = "http://${aws_instance.nagios_server.public_ip}/nagios4/"
}

output "web_nodes_info" {
  description = "Public IPs and Web Application URLs for URL Shortener nodes"
  value = [
    for idx, inst in aws_instance.web_nodes : {
      node_name  = "web-${idx + 1}"
      public_ip  = inst.public_ip
      private_ip = inst.private_ip
      app_url    = "http://${inst.public_ip}/"
      health_url = "http://${inst.public_ip}/health"
    }
  ]
}

output "ssh_commands" {
  description = "Convenient SSH commands to connect to each node"
  value = {
    puppet_master = "ssh -i <your-key.pem> ubuntu@${aws_instance.puppet_master.public_ip}"
    nagios_server = "ssh -i <your-key.pem> ubuntu@${aws_instance.nagios_server.public_ip}"
    web_nodes = [
      for idx, inst in aws_instance.web_nodes :
      "ssh -i <your-key.pem> ubuntu@${inst.public_ip}"
    ]
  }
}
