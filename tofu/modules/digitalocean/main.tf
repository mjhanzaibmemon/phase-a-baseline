variable "hostname" { type = string }
variable "region" { type = string }
variable "droplet_size" { type = string }
variable "ssh_public_key" { type = string }
variable "allowed_ssh_cidrs" { type = list(string) }
variable "user_data" { type = string }

terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.40"
    }
  }
}

resource "digitalocean_ssh_key" "this" {
  name       = "${var.hostname}-key"
  public_key = var.ssh_public_key
}

resource "digitalocean_droplet" "this" {
  name      = var.hostname
  image     = "ubuntu-24-04-x64"
  size      = var.droplet_size
  region    = var.region
  ssh_keys  = [digitalocean_ssh_key.this.fingerprint]
  user_data = var.user_data
  ipv6      = true

  tags = ["opentofu", "disposable-baseline"]
}

resource "digitalocean_firewall" "this" {
  name        = "${var.hostname}-fw"
  droplet_ids = [digitalocean_droplet.this.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.allowed_ssh_cidrs
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "41641"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

output "ipv4" { value = digitalocean_droplet.this.ipv4_address }
output "id" { value = digitalocean_droplet.this.id }
