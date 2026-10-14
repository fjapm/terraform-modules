# cloudflare-r2-queues

An R2 bucket, a queue with a dead-letter queue and an HTTP pull consumer, bucket
events wired into the queue, and scoped API tokens for both.

The shape of an event-driven pipeline on Cloudflare: something uploads to R2, R2
publishes an event, a long-running worker elsewhere pulls it. This module owns
the storage and the plumbing; what consumes the queue, and anything that serves
the bucket, is yours.

```hcl
module "media" {
  source = "github.com/fjapm/terraform-modules.git//cloudflare-r2-queues?ref=v0.1.0"

  account_id   = var.cloudflare_account_id
  name_prefix  = "video"
  queue_suffix = "transcode"
  bucket_name  = "video"

  event_notification_rules = [{
    description = "Source uploads to the transcode queue"
    actions     = ["PutObject", "CompleteMultipartUpload", "CopyObject"]
    prefix      = "source/"
  }]

  r2_token_names = ["worker", "upload"]
}
```

## Why pull, not push

`cloudflare_queue_consumer` is created with `type = "http_pull"`, so there is no
`script_name` — a consumer somewhere else polls `/messages/pull`. That is the
only option when a unit of work can outlive a Worker's CPU limit. If your
consumer *is* a Worker, you want a push consumer and not this module.

Acking is what deletes a message; not acking is what retries it. The consumer's
token therefore needs **Queues Write as well as Read** — a read-only token
returns 403 on the first ack and the consumer loops forever on the same batch.

## R2 credentials are derived, not issued

```
Access Key ID     = the API token's ID
Secret Access Key = SHA-256 hex digest of the token's value
```

`r2_credentials` does this for you. Using the raw token value as the secret is
the single most common R2 mistake, and it surfaces only as an opaque
`SignatureDoesNotMatch` — nothing anywhere says the secret was merely in the
wrong encoding.

## Prefix scoping is not possible

R2 API tokens scope to a **bucket**, never to a key prefix — the four permission
tiers in [the R2 token docs](https://developers.cloudflare.com/r2/api/tokens/)
have no prefix dimension. So every name in `r2_token_names` gets the same reach
over the whole bucket. Separate tokens buy independent rotation and clearer
audit trails, not tighter scope. If you need a credential that genuinely cannot
read `other-prefix/`, you need a second bucket.

Permission groups are resolved by name at plan time via
`cloudflare_account_api_token_permission_groups_list`, so there are no
hardcoded hex IDs to go stale.

## The credential this module needs

An **account-owned** API token (the `cfat_` prefix) is enough. Nothing here
touches a `/user/...` endpoint, which matters because an account-owned token
gets `403` code `9109`, *"Valid user-level authentication not found"*, from
every one of them.

Two deliberate choices keep it that way, and both are easy to undo by accident:

- the permission-group lookup is the `..._account_api_token_...` data source,
  not the user-scoped `cloudflare_api_token_permission_groups_list`;
- the tokens are `cloudflare_account_token`, not `cloudflare_api_token`. The
  latter has no `account_id` because it POSTs to `/user/tokens`.

Required scopes on that token: *Workers R2 Storage Write*, *Queues Write*,
*Workers Scripts Write* and *API Tokens Write*.

The lookup is also filtered to the four groups actually used. That is not
tidiness: of the 410 groups the account list returns, seven names appear twice
under different scopes with different IDs, and a map comprehension over the
whole list evaluates its value expression for every key — so those seven would
break `one()` and the module with it, without being referenced anywhere.

## Inputs

| Name | Type | Default | |
|---|---|---|---|
| `account_id` | string | — | 32-char hex. |
| `name_prefix` | string | `"media"` | Prefixes queue, DLQ and token names. |
| `queue_suffix` | string | `"jobs"` | So one account can hold several pipelines. |
| `bucket_name` | string | — | |
| `bucket_location` | string | `"enam"` | One of `apac`, `eeur`, `enam`, `weur`, `wnam`, `oc`. |
| `queue_batch_size` | number | `5` | 1–100. |
| `queue_max_retries` | number | `3` | Then → DLQ. |
| `queue_visibility_timeout_ms` | number | `7200000` | Must exceed the slowest job. |
| `queue_message_retention_seconds` | number | `345600` | Queue and DLQ. |
| `event_notification_rules` | list(object) | `[]` | Empty disables notifications. |
| `r2_token_names` | list(string) | `[]` | One bucket-scoped R/W token each. |
| `create_queue_token` | bool | `true` | Account-scoped Queues R/W. |
| `api_token_ip_allowlist` | list(string) | `[]` | Applies to every token here. |

## Outputs

`bucket_name`, `bucket_id`, `r2_endpoint`, `queue_id`, `queue_name`,
`dead_letter_queue_id`, `dead_letter_queue_name`, `queue_consumer_id`, and the
sensitive `r2_credentials` (map of name → `{access_key_id, secret_access_key}`)
and `queue_api_token`.

## Things worth knowing

**The dead-letter queue has no consumer**, deliberately. Messages land there to
be inspected, not retried automatically. That means a job which exhausts its
retries disappears from your application's point of view — so whatever consumes
the queue should record its own durable failure before the last attempt is
acknowledged.

**Event notifications are created last**, with `depends_on` on the consumer.
Without that, the first upload can fire into a queue with no reader and burn a
delivery attempt. This is why the notification is inside the module rather than
in the caller.

**The `prefix` filter is coarse.** It matches everything under the prefix, so a
consumer still has to decide which keys are genuinely work — in particular, any
sidecar file written alongside the real payload will also produce an event.

**Provider version.** Pinned `>= 5.13.0, < 6.0.0`: 5.13 is the first release
where `r2_bucket_event_notification` can be applied repeatedly without erroring.
This is also why this is a sibling of `cloudflare-dns` rather than part of it —
that module pins `~> 4.0`, and v4's `cloudflare_record` became
`cloudflare_dns_record` in v5.
