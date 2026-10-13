output "public_ip" {
  description = "Public IPv4 address."
  value       = hcloud_server.this.ipv4_address
}

output "ipv6_address" {
  description = "Public IPv6 address."
  value       = hcloud_server.this.ipv6_address
}

output "instance_id" {
  description = "Hetzner server ID. Use this to attach volumes."
  value       = hcloud_server.this.id
}

output "instance_name" {
  value = hcloud_server.this.name
}

output "server_type" {
  value = hcloud_server.this.server_type
}

output "location" {
  value = hcloud_server.this.location
}

output "firewall_id" {
  value = hcloud_firewall.base.id
}

output "ssh_key_id" {
  value = hcloud_ssh_key.this.id
}

# There is deliberately no output for user_data. It is the fully rendered
# cloud-config, which for any real consumer contains credentials — an
# `output "user" { value = hcloud_server.this.user_data }` used to live here and
# published all of them in the clear.
