# hetzner-vps-bare

A single Hetzner Cloud server with key-only SSH, a firewall, ufw + fail2ban, and
extensible cloud-init.

Deliberately *bare*: it creates a host and gets you in. Anything the host then
runs — Docker, a database, a web server — is supplied through the three
`cloudinit_config_*` escape hatches rather than baked in.

```hcl
module "server" {
  source = "github.com/fjapm/terraform-modules.git//hetzner-vps-bare?ref=v0.1.0"

  vps = {
    name                = "my-host"
    image               = "debian-12"
    server_type         = "ccx33"
    location            = "ash"
    ssh_authorized_keys = [file("~/.ssh/id_ed25519.pub")]
    ssh_source_ips      = ["203.0.113.4/32"]
  }

  labels = { managed-by = "terraform" }
}
```

## Inputs

| Name | Type | Default | |
|---|---|---|---|
| `vps.name` | string | — | Also prefixes the firewall and SSH key names. |
| `vps.hostname` | string | `vps.name` | |
| `vps.image` | string | — | Must be Debian/Ubuntu; cloud-init assumes apt. |
| `vps.server_type` | string | — | |
| `vps.location` | string | — | |
| `vps.ssh_authorized_keys` | list(string) | — | All reach the host; only the first is registered as an `hcloud_ssh_key`. |
| `vps.ssh_source_ips` | list(string) | `["0.0.0.0/0", "::/0"]` | Who may reach port 22. Narrow it if you can — it is the whole inbound surface. |
| `vps.package_upgrade` | bool | `true` | Full apt upgrade on first boot. `false` is faster and cannot pull a kernel. |
| `vps.sshd_config_file` | string | hardened defaults | Written to `/etc/ssh/sshd_config.d/99-hardening.conf`. |
| `labels` | map(string) | `{}` | Applied to server, firewall and SSH key. |
| `cloudinit_config_packages` | list(string) | `[]` | Appended to the base set. |
| `cloudinit_config_write_files` | list(object) | `[]` | `{path, permissions, content}`. |
| `cloudinit_config_runcmd` | list(list(string)) | `[]` | Each item is one cloud-init `runcmd` entry, e.g. `["bash", "-lc", "..."]`. |
| `firewall_rules` | list(object) | `[]` | Added to the base SSH rule. |

## Outputs

`public_ip`, `ipv6_address`, `instance_id`, `instance_name`, `server_type`,
`location`, `firewall_id`, `ssh_key_id`.

`instance_id` is what you need to attach a volume from the calling module.

## Things worth knowing

**No egress rules.** Hetzner firewalls allow all outbound when no `out` rule is
present, which is what package mirrors, registries and object storage need.
Adding a single egress rule starts denying everything else.

**`ssh_keys` is under `ignore_changes`.** Hetzner rejects changes to `ssh_keys`
on an existing server, so a rotated key would otherwise plan as a forced
replacement — destroying the host to change a value the API will not accept.
Rotate by editing `authorized_keys` on the host, or replace deliberately.

**No volume support.** Attach one from the calling module:

```hcl
resource "hcloud_volume" "scratch" {
  name     = "my-host-scratch"
  size     = 200
  location = "ash"
  format   = "ext4"
}

resource "hcloud_volume_attachment" "scratch" {
  volume_id = hcloud_volume.scratch.id
  server_id = module.server.instance_id
  automount = false
}
```

Keeping the volume outside is not an oversight. If cloud-init needs the volume's
device path — and it does, to write an `/etc/fstab` entry — then a volume created
*inside* this module would be a dependency cycle: the module needs `user_data`,
and `user_data` needs the device path. Creating it with `location` (rather than
`server_id`) makes `linux_device` known at plan time, and `format = "ext4"`
means cloud-init never runs `mkfs` and so can never wipe a volume that already
holds data.

**No output for `user_data`.** It is the rendered cloud-config, which for any
real consumer contains credentials.
