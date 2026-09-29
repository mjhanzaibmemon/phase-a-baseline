variable "hostname" { type = string }
variable "location" { type = string }
variable "server_type" { type = string }
variable "ssh_public_key" { type = string }
variable "allowed_ssh_cidrs" { type = list(string) }
variable "user_data" { type = string }

terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.48"
    }
  }
}

resource "hcloud_ssh_key" "this" {
  name       = "${var.hostname}-key"
  public_key = var.ssh_public_key
}

resource "hcloud_firewall" "this" {
  name = "${var.hostname}-fw"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.allowed_ssh_cidrs
  }

  # Tailscale prefers a direct path. Without this it still connects over DERP,
  # just slower, so this is a performance rule rather than a requirement.
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "41641"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "this" {
  name         = var.hostname
  image        = "ubuntu-24.04"
  server_type  = var.server_type
  location     = var.location
  ssh_keys     = [hcloud_ssh_key.this.id]
  firewall_ids = [hcloud_firewall.this.id]
  user_data    = var.user_data

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  labels = {
    managed_by = "opentofu"
    purpose    = "disposable-baseline"
  }
}

output "ipv4" { value = hcloud_server.this.ipv4_address }
output "id" { value = hcloud_server.this.id }
