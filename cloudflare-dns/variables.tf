variable "zone_id" {
  description = "Cloudflare zone ID where the record will be created"
  type        = string
}

variable "records" {
  type = list(object({
    name = string
    type = string
    value = string
    proxied = bool
  }))
  description = <<-EOT
    name : "DNS record name (e.g. assets.classpert.com)"
    type : "DNS record type (e.g. CNAME)"
    value : "DNS record value (e.g sub.otherdomain.com)"
    proxied : "Whether the record should be proxied through Cloudflare"
  EOT
}
