variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-south-1" # Default region (Mumbai, India) or us-east-1
}

variable "project_name" {
  description = "Project name prefix for tags and resources"
  type        = string
  default     = "int333-devops"
}

variable "key_name" {
  description = "Name of existing EC2 Key Pair for SSH access"
  type        = string
}

variable "admin_ip" {
  description = "Administrator public IP in CIDR notation (e.g. 203.0.113.50/32 or 0.0.0.0/0)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "web_count" {
  description = "Number of web server instances to provision"
  type        = number
  default     = 2
}

variable "nagios_admin_password" {
  description = "Password for Nagios Web UI (nagiosadmin)"
  type        = string
  default     = "DevOpsAdmin2026!"
  sensitive   = true
}
