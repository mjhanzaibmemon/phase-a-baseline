variable "hostname" { type = string }
variable "instance_type" { type = string }
variable "ssh_public_key" { type = string }
variable "allowed_ssh_cidrs" { type = list(string) }
variable "user_data" { type = string }
variable "root_volume_gb" {
  type    = number
  default = 20
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# Canonical's own account. Looking the AMI up by owner and name pattern keeps this
# working across regions instead of hardcoding an id that is only valid in one.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_key_pair" "this" {
  key_name   = "${var.hostname}-key"
  public_key = var.ssh_public_key

  tags = {
    ManagedBy = "opentofu"
  }
}

resource "aws_security_group" "this" {
  name        = "${var.hostname}-sg"
  description = "Disposable baseline host"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH while the box is being built, closed by Ansible once Tailscale is up"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  ingress {
    description = "Tailscale direct path. Without it the tunnel still works over DERP, just slower."
    from_port   = 41641
    to_port     = 41641
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP, so the box is diagnosable"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${var.hostname}-sg"
    ManagedBy = "opentofu"
  }
}

resource "aws_instance" "this" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.this.id]
  key_name                    = aws_key_pair.this.key_name
  user_data                   = var.user_data
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_volume_gb
    volume_type = "gp3"
    encrypted   = true
  }

  # IMDSv2 only. Token-less metadata is how a request-forgery bug on the box turns
  # into stolen instance credentials, and there is no reason to leave v1 enabled.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name      = var.hostname
    ManagedBy = "opentofu"
    Purpose   = "disposable-baseline"
  }
}

output "ipv4" { value = aws_instance.this.public_ip }
output "id" { value = aws_instance.this.id }
