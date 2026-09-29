variable "cloud_provider" {
  description = "Which provider to build on. Swapping this is a variable change, not a rewrite."
  type        = string
  default     = "hetzner"

  validation {
    condition     = contains(["hetzner", "digitalocean", "aws"], var.cloud_provider)
    error_message = "cloud_provider must be one of: hetzner, digitalocean, aws."
  }
}

variable "hostname" {
  description = "Server hostname, also used as the resource name."
  type        = string
  default     = "baseline-dev"
}

variable "region" {
  description = "Provider-neutral region. Mapped per provider in locals."
  type        = string
  default     = "eu-central"
}

variable "size" {
  description = "Provider-neutral size class: small, medium, large."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "medium", "large"], var.size)
    error_message = "size must be one of: small, medium, large."
  }
}

variable "ssh_public_key" {
  description = "Public key registered with the provider and installed by cloud-init."
  type        = string
}

variable "admin_username" {
  description = "Non-root user created at first boot. Ansible connects as this user."
  type        = string
  default     = "deploy"
}

variable "allowed_ssh_cidrs" {
  description = <<-EOT
    Who may reach port 22 on the public interface while the box is being built.
    Narrow this to your own address. Once Tailscale is verified up, Ansible closes
    public SSH entirely and this list stops mattering.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "hcloud_token" {
  description = "Hetzner Cloud API token. Unused when cloud_provider is not hetzner."
  type        = string
  default     = ""
  sensitive   = true
}

variable "do_token" {
  description = "DigitalOcean API token. Unused when cloud_provider is not digitalocean."
  type        = string
  default     = ""
  sensitive   = true
}

variable "write_inventory" {
  description = "Write the Ansible inventory from the apply, so there is no manual copy step."
  type        = bool
  default     = true
}

variable "aws_region" {
  description = "Concrete AWS region for the provider. Kept separate from the neutral region variable because the provider has to be configured before any module is selected."
  type        = string
  default     = "eu-central-1"
}
