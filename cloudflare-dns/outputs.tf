output "records" {
  value = {
    for k, r in cloudflare_record.cdn_record : k => {
      id       = r.id
      hostname = r.hostname
      name     = r.name
      type     = r.type
      value    = r.value
      proxied  = r.proxied
    }
  }
  description = "Complete information about all DNS records"
}
