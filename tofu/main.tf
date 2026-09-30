locals {
  # Provider-neutral inputs, translated once, here.
  region_map = {
    hetzner = {
      "eu-central" = "nbg1"
      "eu-west"    = "fsn1"
      "us-east"    = "ash"
      "us-west"    = "hil"
    }
    digitalocean = {
      "eu-central" = "fra1"
      "eu-west"    = "ams3"
      "us-east"    = "nyc3"
      "us-west"    = "sfo3"
    }
    aws = {
      "eu-central" = "eu-central-1"
      "eu-west"    = "eu-west-1"
      "us-east"    = "us-east-1"
      "us-west"    = "us-west-2"
    }
  }

  size_map = {
    hetzner = {
      small  = "cx22"
      medium = "cx32"
      large  = "cx42"
    }
    digitalocean = {
      small  = "s-2vcpu-4gb"
      medium = "s-4vcpu-8gb"
      large  = "s-8vcpu-16gb"
    }
    aws = {
      small  = "t3.small"
      medium = "t3.medium"
      large  = "t3.large"
    }
  }

  cloud_init = templatefile("${path.module}/../cloud-init/bootstrap.yaml.tftpl", {
    hostname       = var.hostname
    admin_username = var.admin_username
    ssh_public_key = trimspace(var.ssh_public_key)
  })
}

module "hetzner" {
  source = "./modules/hetzner"
  count  = var.cloud_provider == "hetzner" ? 1 : 0

  hostname          = var.hostname
  location          = local.region_map.hetzner[var.region]
  server_type       = local.size_map.hetzner[var.size]
  ssh_public_key    = var.ssh_public_key
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  user_data         = local.cloud_init
}

module "digitalocean" {
  source = "./modules/digitalocean"
  count  = var.cloud_provider == "digitalocean" ? 1 : 0

  hostname          = var.hostname
  region            = local.region_map.digitalocean[var.region]
  droplet_size      = local.size_map.digitalocean[var.size]
  ssh_public_key    = var.ssh_public_key
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  user_data         = local.cloud_init
}

module "aws" {
  source = "./modules/aws"
  count  = var.cloud_provider == "aws" ? 1 : 0

  hostname          = var.hostname
  instance_type     = local.size_map.aws[var.size]
  ssh_public_key    = var.ssh_public_key
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  user_data         = local.cloud_init
}

locals {
  server_ipv4 = coalesce(
    try(module.aws[0].ipv4, null),
    try(module.hetzner[0].ipv4, null),
    try(module.digitalocean[0].ipv4, null),
  )
}

resource "local_file" "inventory" {
  count = var.write_inventory ? 1 : 0

  filename        = "${path.module}/../ansible/inventory/hosts.yml"
  file_permission = "0600"

  content = yamlencode({
    all = {
      hosts = {
        (var.hostname) = {
          ansible_host = local.server_ipv4
          ansible_user = var.admin_username
        }
      }
      vars = {
        cloud_provider = var.cloud_provider
      }
    }
  })
}
