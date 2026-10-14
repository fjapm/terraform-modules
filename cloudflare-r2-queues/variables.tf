variable "account_id" {
  description = "Cloudflare account ID that owns the bucket and the queues."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "The account ID is a 32-character lowercase hex string."
  }
}

variable "name_prefix" {
  description = "Prefix for the queue, DLQ and API token names."
  type        = string
  default     = "media"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,24}$", var.name_prefix))
    error_message = "Lowercase alphanumerics and hyphens, starting with alphanumeric, max 25 characters."
  }
}

variable "queue_suffix" {
  description = "Suffix for the queue name, so one account can hold several pipelines."
  type        = string
  default     = "jobs"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,24}$", var.queue_suffix))
    error_message = "Lowercase alphanumerics and hyphens, starting with alphanumeric, max 25 characters."
  }
}

# ---------------------------------------------------------------------------
# Bucket
# ---------------------------------------------------------------------------

variable "bucket_name" {
  description = "R2 bucket name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,62}$", var.bucket_name))
    error_message = "Lowercase alphanumerics and hyphens, starting with alphanumeric, 3-63 characters."
  }
}

variable "bucket_location" {
  description = "R2 location hint."
  type        = string
  default     = "enam"

  validation {
    condition     = contains(["apac", "eeur", "enam", "weur", "wnam", "oc"], var.bucket_location)
    error_message = "Must be one of apac, eeur, enam, weur, wnam, oc."
  }
}

# ---------------------------------------------------------------------------
# Queue
# ---------------------------------------------------------------------------

variable "queue_batch_size" {
  description = "Messages returned per pull."
  type        = number
  default     = 5

  validation {
    condition     = var.queue_batch_size >= 1 && var.queue_batch_size <= 100
    error_message = "Between 1 and 100."
  }
}

variable "queue_max_retries" {
  description = "Delivery attempts before a message goes to the dead-letter queue."
  type        = number
  default     = 3

  validation {
    condition     = var.queue_max_retries >= 1 && var.queue_max_retries <= 100
    error_message = "Between 1 and 100."
  }
}

variable "queue_visibility_timeout_ms" {
  description = <<-EOT
    How long a pulled message stays invisible to other consumers.

    Must comfortably exceed the slowest unit of work, or a job still running
    will be handed to a second consumer while the first is mid-flight.
  EOT
  type        = number
  default     = 7200000

  validation {
    condition     = var.queue_visibility_timeout_ms >= 1000 && var.queue_visibility_timeout_ms <= 43200000
    error_message = "Between 1000 and 43200000 milliseconds (1 second to 12 hours)."
  }
}

variable "queue_message_retention_seconds" {
  description = <<-EOT
    How long the queue and its DLQ keep an unconsumed message.

    Capped at 24 hours by the API, which is lower than the retention figure
    quoted in parts of the Cloudflare Queues documentation. The default used to
    be 345600 (4 days) and every apply failed on it:

      POST /accounts/{id}/queues -> 400, code 100128
      "Queue '<name>-dlq' has invalid settings:
       message_retention_period must be between 60 and 86400 seconds."

    The default is now the maximum, because the value matters most for the DLQ:
    it bounds how long you have to notice and inspect a failed job before the
    evidence is discarded.
  EOT
  type        = number
  default     = 86400

  validation {
    condition     = var.queue_message_retention_seconds >= 60 && var.queue_message_retention_seconds <= 86400
    error_message = "Between 60 and 86400 seconds (1 minute to 24 hours)."
  }
}

# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------

variable "event_notification_rules" {
  description = <<-EOT
    Bucket event rules that publish into the queue. Empty disables the
    notification entirely.

    `actions` is the full list to react to. Note that `aws s3 cp` switches to
    multipart above 8 MiB, so a large upload arrives as
    CompleteMultipartUpload while a small one arrives as PutObject —
    registering only PutObject is the classic "works for my small test file,
    silently drops every real one" bug.

    `prefix`/`suffix` are the only filtering R2 offers, and they are coarse.
    The consumer still has to decide which keys are genuinely work.
  EOT
  type = list(object({
    description = optional(string)
    actions     = list(string)
    prefix      = optional(string)
    suffix      = optional(string)
  }))
  default = []
}

# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------

variable "r2_token_names" {
  description = <<-EOT
    One bucket-scoped Read+Write R2 token per name, exposed in the
    `r2_credentials` output under the same key.

    Separate names for separate consumers (say "worker" and "upload") buy
    independent rotation and clearer audit, not tighter scope: R2 tokens cannot
    scope to a key prefix, so every token here has the same reach.
  EOT
  type        = list(string)
  default     = []
}

variable "create_queue_token" {
  description = "Create an account-scoped Queues Read+Write token for a pull consumer."
  type        = bool
  default     = true
}

variable "api_token_ip_allowlist" {
  description = <<-EOT
    Restrict every token created here to these source IPs. Empty means no
    restriction.

    Cannot usefully contain a server that this same configuration creates —
    that would be circular. Use it for fixed operator or NAT addresses.
  EOT
  type        = list(string)
  default     = []
}
