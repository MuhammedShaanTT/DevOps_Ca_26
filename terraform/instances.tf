# EC2 Instances matching Section 6 & 7

# 1. Puppet Master Instance
resource "aws_instance" "puppet_master" {
  ami                         = data.aws_ami.ubuntu_22.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.public.id
  private_ip                  = "10.0.1.10"
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.puppet_master.id]
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/scripts/puppet-master-bootstrap.sh", {})

  tags = {
    Name = "${var.project_name}-puppet-master"
    Role = "puppet-master"
  }
}

resource "aws_ec2_instance_state" "puppet_master" {
  instance_id = aws_instance.puppet_master.id
  state       = "running"
}

# 2. Nagios Monitoring Server Instance
resource "aws_instance" "nagios_server" {
  ami                         = data.aws_ami.ubuntu_22.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.public.id
  private_ip                  = "10.0.1.20"
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.nagios_server.id]
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/scripts/nagios-bootstrap.sh", {
    admin_password = var.nagios_admin_password
  })

  tags = {
    Name = "${var.project_name}-nagios-server"
    Role = "nagios-server"
  }
}

resource "aws_ec2_instance_state" "nagios_server" {
  instance_id = aws_instance.nagios_server.id
  state       = "running"
}

# 3. Web Servers (Count-based scalable nodes)
resource "aws_instance" "web_nodes" {
  count                       = var.web_count
  ami                         = data.aws_ami.ubuntu_22.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  private_ip                  = format("10.0.1.%d", 31 + count.index)
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.web_nodes.id]
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/scripts/web-node-bootstrap.sh", {
    master_ip = aws_instance.puppet_master.private_ip
    node_name = "web-${count.index + 1}"
  })

  tags = {
    Name = "web-${count.index + 1}"
    Role = "web"
  }

  depends_on = [aws_instance.puppet_master]
}

resource "aws_ec2_instance_state" "web_nodes" {
  count       = var.web_count
  instance_id = aws_instance.web_nodes[count.index].id
  state       = "running"
}

# Auto-generate Nagios host definitions from Terraform outputs (Objective 5)
resource "local_file" "nagios_hosts_cfg" {
  content = templatefile("${path.module}/../nagios/templates/web_hosts.cfg.tpl", {
    web_nodes = [
      for idx, instance in aws_instance.web_nodes : {
        name       = "web-${idx + 1}"
        private_ip = instance.private_ip
      }
    ]
  })
  filename = "${path.module}/../nagios/generated_hosts.cfg"
}
