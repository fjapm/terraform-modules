output "bucket_name" {
  value = cloudflare_r2_bucket.this.name
}

output "bucket_id" {
  value = cloudflare_r2_bucket.this.id
}

output "r2_endpoint" {
  description = "S3-compatible endpoint for this account."
  value       = "https://${var.account_id}.r2.cloudflarestorage.com"
}

output "queue_id" {
  value = cloudflare_queue.this.queue_id
}

output "queue_name" {
  value = cloudflare_queue.this.queue_name
}

output "dead_letter_queue_id" {
  value = cloudflare_queue.dlq.queue_id
}

output "dead_letter_queue_name" {
  value = cloudflare_queue.dlq.queue_name
}

output "queue_consumer_id" {
  description = "Depend on this if you add bucket notifications outside this module."
  value       = cloudflare_queue_consumer.this.consumer_id
}

# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------
#
# R2 speaks the S3 API, but its credentials are derived from an API token
# rather than issued as a keypair:
#
#   Access Key ID     = the token's ID
#   Secret Access Key = SHA-256 hex digest of the token's *value*
#
# Using the raw token value as the secret is the single most common R2 mistake
# and surfaces only as an opaque SignatureDoesNotMatch, with nothing in any log
# to say the secret was merely in the wrong encoding.

output "r2_credentials" {
  description = "Per-token S3 credentials for the bucket, keyed by r2_token_names."
  sensitive   = true
  value = {
    for name, token in cloudflare_account_token.r2 :
    name => {
      access_key_id     = token.id
      secret_access_key = sha256(token.value)
    }
  }
}

output "queue_api_token" {
  description = "Bearer token for the Queues pull/ack API. Null when create_queue_token is false."
  sensitive   = true
  value       = var.create_queue_token ? cloudflare_account_token.queue[0].value : null
}
