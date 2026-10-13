terraform {
  required_version = ">= 1.6.0"

  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      # v5 reworked almost every resource schema relative to v4, and 5.13 is
      # the first release where r2_bucket_event_notification can be applied
      # repeatedly without erroring. The upper bound keeps a v6 from arriving
      # unannounced.
      #
      # This is also why this module is a sibling of cloudflare-dns rather than
      # part of it: that module pins ~> 4.0, and v4's cloudflare_record was
      # renamed cloudflare_dns_record in v5. One module cannot hold both.
      version = ">= 5.13.0, < 6.0.0"
    }
  }
}
