terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# Create DNS record in Cloudflare
resource "cloudflare_record" "cdn_record" {
  for_each = { for r in var.records : r.name => r }
  zone_id = var.zone_id
  name    = each.value.name
  type    = each.value.type
  value   = each.value.value
  ttl     = 1
  proxied = each.value.proxied
}
