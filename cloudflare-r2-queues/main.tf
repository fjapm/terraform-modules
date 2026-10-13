locals {
  queue_name = "${var.name_prefix}-${var.queue_suffix}"
  dlq_name   = "${var.name_prefix}-${var.queue_suffix}-dlq"

  # Permission groups are looked up by name rather than hardcoded as hex IDs.
  # The API returns duplicates for some groups (the same name under different
  # scopes), hence the grouping ellipsis and the one(distinct(...)) collapse.
  permission_groups_by_name = {
    for pg in data.cloudflare_api_token_permission_groups_list.all.result :
    pg.name => pg.id...
  }

  permission_group_ids = {
    for name, ids in local.permission_groups_by_name :
    name => one(distinct(ids))
  }

  # R2 API tokens scope to a bucket, never to a key prefix — the four
  # permission tiers at developers.cloudflare.com/r2/api/tokens/ have no prefix
  # dimension. Bucket-scoped Object Read & Write is therefore the narrowest
  # grant the platform supports.
  r2_bucket_scope = jsonencode({
    "com.cloudflare.edge.r2.bucket.${var.account_id}_default_${cloudflare_r2_bucket.this.name}" = "*"
  })

  account_scope = jsonencode({
    "com.cloudflare.api.account.${var.account_id}" = "*"
  })

  token_condition = length(var.api_token_ip_allowlist) > 0 ? {
    request_ip = {
      in     = var.api_token_ip_allowlist
      not_in = null
    }
  } : null
}

data "cloudflare_api_token_permission_groups_list" "all" {
  max_items = 1000
}

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------

resource "cloudflare_r2_bucket" "this" {
  account_id    = var.account_id
  name          = var.bucket_name
  location      = var.bucket_location
  storage_class = "Standard"
}

# ---------------------------------------------------------------------------
# Queue, dead-letter queue, and an HTTP pull consumer
# ---------------------------------------------------------------------------
# The DLQ is declared first so the main queue's consumer can name it. It gets
# no consumer of its own on purpose: messages land there to be looked at, not
# to be retried automatically.

resource "cloudflare_queue" "dlq" {
  account_id = var.account_id
  queue_name = local.dlq_name

  settings = {
    message_retention_period = var.queue_message_retention_seconds
  }
}

resource "cloudflare_queue" "this" {
  account_id = var.account_id
  queue_name = local.queue_name

  settings = {
    message_retention_period = var.queue_message_retention_seconds
  }
}

# type = "http_pull" means no script_name: a consumer somewhere else polls
# /messages/pull rather than Cloudflare pushing batches into a Worker. That is
# the only option for work that outlives a Worker's CPU limit.
resource "cloudflare_queue_consumer" "this" {
  account_id        = var.account_id
  queue_id          = cloudflare_queue.this.queue_id
  type              = "http_pull"
  dead_letter_queue = cloudflare_queue.dlq.queue_name

  settings = {
    batch_size            = var.queue_batch_size
    max_retries           = var.queue_max_retries
    visibility_timeout_ms = var.queue_visibility_timeout_ms
  }
}

# ---------------------------------------------------------------------------
# Bucket events into the queue
# ---------------------------------------------------------------------------
# Lives here rather than in the caller so the depends_on below stays correct
# and internal: without it, the very first upload can fire into a queue that
# has no reader yet and burn a delivery attempt.
#
# Note that R2's prefix filter is the only filtering available, and it is
# coarse. A consumer still has to decide which keys are actually work.

resource "cloudflare_r2_bucket_event_notification" "this" {
  count = length(var.event_notification_rules) > 0 ? 1 : 0

  account_id  = var.account_id
  bucket_name = cloudflare_r2_bucket.this.name
  queue_id    = cloudflare_queue.this.queue_id

  rules = var.event_notification_rules

  depends_on = [cloudflare_queue_consumer.this]
}

# ---------------------------------------------------------------------------
# Scoped credentials
# ---------------------------------------------------------------------------

resource "cloudflare_api_token" "r2" {
  for_each = toset(var.r2_token_names)

  name   = "${var.name_prefix}-${each.key}-r2"
  status = "active"

  policies = [{
    effect    = "allow"
    resources = local.r2_bucket_scope
    permission_groups = [
      { id = local.permission_group_ids["Workers R2 Storage Bucket Item Read"] },
      { id = local.permission_group_ids["Workers R2 Storage Bucket Item Write"] },
    ]
  }]

  condition = local.token_condition
}

# Queues Write is required as well as Read: acknowledging a message is a write,
# so a read-only token produces a 403 on the first ack and the consumer loops
# forever on the same batch.
resource "cloudflare_api_token" "queue" {
  count = var.create_queue_token ? 1 : 0

  name   = "${var.name_prefix}-queue-consumer"
  status = "active"

  policies = [{
    effect    = "allow"
    resources = local.account_scope
    permission_groups = [
      { id = local.permission_group_ids["Queues Read"] },
      { id = local.permission_group_ids["Queues Write"] },
    ]
  }]

  condition = local.token_condition
}
