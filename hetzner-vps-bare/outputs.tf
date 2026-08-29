output "public_ip"    { value = hcloud_server.this.ipv4_address }
output "user"         { value = hcloud_server.this.user_data }
output "instance_id"  { value = hcloud_server.this.id }
output "instance_name" { value = hcloud_server.this.name }