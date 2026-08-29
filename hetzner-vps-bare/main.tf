terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.45.0"
    }
  }
}

resource "hcloud_firewall" "base" {
  name = "${var.vps.name}-fw"

  # --- Allow SSH (key-only) globally, rate-limited at UFW level ---
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "SSH (key-only)"
  }

  # --- User-supplied rules ---
  dynamic "rule" {
    for_each = var.firewall_rules
    content {
      direction       = rule.value.direction
      protocol        = rule.value.protocol
      port            = rule.value.port
      source_ips      = rule.value.source_ips
      destination_ips = rule.value.destination_ips
      description     = rule.value.description
    }
  }
}

data "cloudinit_config" "init" {
  part {
    content_type = "text/cloud-config"
    content = yamlencode({
      disable_root = false,
      users = [
        {
          name              = "root"
          shell             = "/bin/bash"
          ssh_authorized_keys = var.vps.ssh_authorized_keys
        }
      ]
      package_update = true,
      package_upgrade = true,
      packages = concat([
        "ufw",
        "fail2ban",
        "openssh-server",
        "curl"
      ], var.cloudinit_config_packages),
      write_files = concat([
        {
          path = "/etc/ssh/sshd_config.d/99-hardening.conf"
          permissions =  "0644"
          content = var.vps.sshd_config_file
        }
      ], var.cloudinit_config_write_files),
      runcmd = concat([
        [ "bash", "-lc", "ufw default deny incoming" ],
        [ "bash", "-lc", "ufw default allow outgoing" ],
        [ "bash", "-lc", "ufw limit 22/tcp" ],
        [ "bash", "-lc", "ufw --force enable" ],
        [ "bash", "-lc", "systemctl restart ssh" ]
      ],var.cloudinit_config_runcmd)
    })
  }
}

resource "hcloud_ssh_key" "this" {
  name       = "${var.vps.name}-ssh-key"
  public_key = var.vps.ssh_authorized_keys[0]
}

resource "hcloud_server" "this" {
  name          = var.vps.name
  image         = var.vps.image 
  server_type   = var.vps.server_type
  location      = var.vps.location
  firewall_ids  = [hcloud_firewall.base.id]
  ssh_keys      = [hcloud_ssh_key.this.id]
  user_data     = data.cloudinit_config.init.rendered
}
