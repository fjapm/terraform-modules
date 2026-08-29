variable "vps" {
  type = object({
    name             = string
    image            = string
    server_type      = string
    location         = string
    ssh_authorized_keys = list(string)
    sshd_config_file = optional(string, <<-EOT
      PasswordAuthentication no
      PermitRootLogin prohibit-password
      PubkeyAuthentication yes
      X11Forwarding no
      AllowTcpForwarding yes
      MaxAuthTries 5
    EOT
    )
  })
}

variable "cloudinit_config_packages" {
  description = "Additional packages to install via cloud-init"
  type        = list(string)
  default     = [] 
}

variable "cloudinit_config_write_files" {
  description = "Additional files to create via cloud-init"
  type        = list(object({
    path        = string
    permissions =  string
    content     = string
  }))
  default     = [] 
}

variable "cloudinit_config_runcmd" {
  description = "Additional commands to run via cloud-init. Each command is a cloud-init runcmd item."
  type        = list(list(string))
  default     = []
}

variable "firewall_rules" {
  description = "Additional firewall rules to extend the base set."
  type = list(object({
    direction        = string
    protocol         = string
    port             = optional(string)
    source_ips       = optional(list(string), [])
    destination_ips  = optional(list(string), [])
    description      = optional(string)
  }))
  default = []
}