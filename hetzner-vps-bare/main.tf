terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
      # Upper bound so a future major release cannot silently change schemas.
      version = ">= 1.50.0, < 2.0.0"
    }
    # Used by data.cloudinit_config below. Declared explicitly rather than
    # resolved implicitly, so a consumer's lock file records it.
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = ">= 2.3.0"
    }
  }
}

resource "hcloud_firewall" "base" {
  name   = "${var.vps.name}-fw"
  labels = var.labels

  # --- Allow SSH (key-only), rate-limited at the UFW level ---
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = var.vps.ssh_source_ips
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

  # Note the absence of any "out" rule. Hetzner firewalls default to allow-all
  # outbound when no egress rule is present, which is what most workloads need
  # (package mirrors, registries, object storage). Adding one egress rule here
  # would start denying everything else.
}

data "cloudinit_config" "init" {
  part {
    content_type = "text/cloud-config"
    content = yamlencode({
      hostname          = coalesce(var.vps.hostname, var.vps.name),
      preserve_hostname = false,
      manage_etc_hosts  = true,
      disable_root      = false,
      users = [
        {
          name                = "root"
          shell               = "/bin/bash"
          ssh_authorized_keys = var.vps.ssh_authorized_keys
        }
      ]
      package_update  = true,
      package_upgrade = var.vps.package_upgrade,
      # A reboot partway through first boot would strand anything the runcmds
      # below have started.
      package_reboot_if_required = false,
      packages = concat([
        "ufw",
        "fail2ban",
        "openssh-server",
        "curl"
      ], var.cloudinit_config_packages),
      write_files = concat([
        {
          path        = "/etc/ssh/sshd_config.d/99-hardening.conf"
          permissions = "0644"
          content     = var.vps.sshd_config_file
        }
      ], var.cloudinit_config_write_files),
      runcmd = concat([
        ["bash", "-lc", "ufw default deny incoming"],
        ["bash", "-lc", "ufw default allow outgoing"],
        ["bash", "-lc", "ufw limit 22/tcp"],
        ["bash", "-lc", "ufw --force enable"],
        ["bash", "-lc", "systemctl restart ssh"]
      ], var.cloudinit_config_runcmd)
    })
  }
}

resource "hcloud_ssh_key" "this" {
  # Only the first key is registered with Hetzner; every key in the list still
  # reaches the host through cloud-init above.
  name       = "${var.vps.name}-ssh-key"
  public_key = var.vps.ssh_authorized_keys[0]
  labels     = var.labels
}

resource "hcloud_server" "this" {
  name         = var.vps.name
  image        = var.vps.image
  server_type  = var.vps.server_type
  location     = var.vps.location
  labels       = var.labels
  firewall_ids = [hcloud_firewall.base.id]
  ssh_keys     = [hcloud_ssh_key.this.id]
  user_data    = data.cloudinit_config.init.rendered

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  # Give the OS a chance to flush and stop cleanly instead of pulling the plug.
  shutdown_before_deletion = true

  lifecycle {
    # Hetzner rejects changes to ssh_keys on an existing server, so a rotated
    # key would otherwise show up as a forced replacement — destroying the host
    # to change a value the API will not accept anyway. Rotate by editing
    # authorized_keys on the host, or replace deliberately.
    ignore_changes = [ssh_keys]
  }
}
