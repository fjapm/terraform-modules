variable "vps" {
  type = object({
    name                = string
    hostname            = optional(string)
    image               = string
    server_type         = string
    location            = string
    ssh_authorized_keys = list(string)

    # Who may reach port 22. Defaults to the whole internet, which is what
    # key-only SSH behind ufw's rate limit was designed for — but a host with
    # a known set of operators should narrow it, because this is the entire
    # inbound attack surface.
    ssh_source_ips = optional(list(string), ["0.0.0.0/0", "::/0"])

    # A full apt upgrade on first boot. Safe, but it adds minutes and can pull
    # a new kernel; set false when first-boot time matters.
    package_upgrade = optional(bool, true)

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

variable "labels" {
  description = "Labels applied to the server, firewall and SSH key."
  type        = map(string)
  default     = {}
}

variable "cloudinit_config_packages" {
  description = "Additional packages to install via cloud-init"
  type        = list(string)
  default     = []
}

variable "cloudinit_config_write_files" {
  description = "Additional files to create via cloud-init"
  type = list(object({
    path        = string
    permissions = string
    content     = string
  }))
  default = []
}

variable "cloudinit_config_runcmd" {
  description = "Additional commands to run via cloud-init. Each command is a cloud-init runcmd item."
  type        = list(list(string))
  default     = []
}

variable "firewall_rules" {
  description = "Additional firewall rules to extend the base set."
  type = list(object({
    direction       = string
    protocol        = string
    port            = optional(string)
    source_ips      = optional(list(string), [])
    destination_ips = optional(list(string), [])
    description     = optional(string)
  }))
  default = []
}
