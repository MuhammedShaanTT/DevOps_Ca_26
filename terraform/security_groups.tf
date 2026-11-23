# Security Groups matching Section 7 & Section 8.1 of the Synopsis

# 1. Puppet Master Security Group
resource "aws_security_group" "puppet_master" {
  name        = "${var.project_name}-puppet-master-sg"
  description = "Security group for Puppet Master"
  vpc_id      = aws_vpc.main.id

  # SSH from Administrator
  ingress {
    description = "SSH from Administrator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  # Puppet Server port 8140 from internal subnet
  ingress {
    description = "Puppet Agent to Master communication"
    from_port   = 8140
    to_port     = 8140
    protocol    = "tcp"
    cidr_blocks = [var.public_subnet_cidr]
  }

  # Ping / ICMP within subnet
  ingress {
    description = "ICMP inside VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.public_subnet_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-puppet-master-sg"
  }
}

# 2. Nagios Server Security Group
resource "aws_security_group" "nagios_server" {
  name        = "${var.project_name}-nagios-server-sg"
  description = "Security group for Nagios Monitoring Server"
  vpc_id      = aws_vpc.main.id

  # SSH from Administrator
  ingress {
    description = "SSH from Administrator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  # HTTP Web Dashboard
  ingress {
    description = "Nagios Web UI"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  # ICMP within subnet
  ingress {
    description = "ICMP inside VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.public_subnet_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-nagios-server-sg"
  }
}

# 3. Web Nodes Security Group
resource "aws_security_group" "web_nodes" {
  name        = "${var.project_name}-web-nodes-sg"
  description = "Security group for Web Server nodes"
  vpc_id      = aws_vpc.main.id

  # SSH from Administrator
  ingress {
    description = "SSH from Administrator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  # HTTP public access (URL Shortener web interface & API)
  ingress {
    description = "HTTP Public Web Traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # App direct port (optional / internal)
  ingress {
    description = "Direct URL Shortener Port"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip, var.public_subnet_cidr]
  }

  # NRPE from Nagios Server only
  ingress {
    description = "NRPE from Nagios Server"
    from_port   = 5666
    to_port     = 5666
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.20/32"]
  }

  # ICMP within subnet
  ingress {
    description = "ICMP inside VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.public_subnet_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-web-nodes-sg"
  }
}
