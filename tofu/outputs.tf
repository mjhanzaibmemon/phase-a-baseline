output "server_ipv4" {
  description = "Public address. Used until Tailscale takes over, then only for break-glass."
  value       = local.server_ipv4
}

output "hostname" {
  value = var.hostname
}

output "cloud_provider" {
  value = var.cloud_provider
}

output "ssh_command" {
  description = "Convenience only. The documented path in is Tailscale once the box is converged."
  value       = "ssh ${var.admin_username}@${local.server_ipv4}"
}
