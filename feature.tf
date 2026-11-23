# Per-tenant custom DNS — CloudFront SaaS Manager edge objects for hostnames
# the tenant owns, routing to the existing cloud-proxy subdomain system.
#
# Design of record: the "Custom DNS Addon" Design Notebook (Namazu Cloud
# Design Notebook, org "Namazu Studios"). Decisions this code encodes:
#   * CloudFront SaaS Manager: one shared multi-tenant distribution (platform,
#     namazu-cloud-terraform global module) + one distribution tenant per
#     custom hostname (this addon, per-tenant state).
#   * Managed ACM certificates (us-east-1, HTTP validation, CloudFront-served
#     tokens): the tenant publishes exactly ONE CNAME and zero TXT records.
#     New domains only — no migrating-live-domains path in v1.
#   * The provider-subdomain CNAME pattern: the tenant points their hostname
#     at a slug we own (<slug>.<zone>), never at a volatile AWS endpoint.
#   * Host-header strategy B: the custom Host is forwarded end to end (the
#     instance's CORS and host-dependent behavior need it). The platform's
#     distribution carries the origin-request-policy that forwards Host.
#   * The two-step activation contract: apply #1 never blocks on the tenant's
#     DNS change (wait_for_deployment = false); the runner's reporting treats
#     tenant status "Deployed" — not the apply exit code — as green.
#
# The two author rules (contract, stated inline so consumers inherit them):
#  1. NEVER re-declare a variable from 20-variables.tf — those are the tenant
#     contract, not yours. Addon-semantics inputs live in variables.tf and are
#     fed from the fork's matrix contract values.
#  2. NEVER couple to another addon except through its outputs (via
#     `$addon.<id>.<output>` bindings in manifest.yaml).

locals {
  # custom hostname -> slug label: deterministic, DNS-safe (dots become
  # dashes). Two tenants can never collide on one slug: the same custom
  # hostname cannot be served for two tenants (CloudFront rejects the
  # duplicate distribution tenant, and the matrix entry is operator-curated).
  custom_domain_slugs = {
    for domain in var.custom_domains :
    domain => "cdn-${replace(lower(domain), "/[^a-z0-9.-]/", "-")}"
  }
}

# The shared subdomain zone, looked up by id — same zone every tenant's
# A-alias record lives in (see namazu-cloud-terraform
# aws_route53_record.cloud_proxy_canonical for the sibling convention).
data "aws_route53_zone" "subdomain" {
  zone_id = var.subdomain_zone_id
}

# ── The per-domainname edge objects ─────────────────────────────────────────
#
# One distribution tenant per custom hostname, each with its own
# CloudFront-managed ACM certificate. wait_for_deployment is deliberately
# false: the certificate cannot issue until the tenant's CNAME resolves to
# the connection group, and apply #1 must never block on a human at a
# registrar (the two-step activation contract, README §"How activation
# works").

resource "aws_cloudfront_distribution_tenant" "custom_domain" {
  for_each = toset(var.custom_domains)

  name            = "${local.addon_namespace}-${local.custom_domain_slugs[each.value]}"
  distribution_id = var.distribution_id
  enabled         = true

  domain {
    domain = each.value
  }

  connection_group_id = var.connection_group_id

  managed_certificate_request {
    primary_domain_name                         = each.value
    validation_token_host                       = "cloudfront"
    certificate_transparency_logging_preference = "enabled"
  }

  # Two-step contract: never wait here. The fork's NEXT apply reports status;
  # "Deployed" is the green signal for the runner's reporting, not this apply.
  wait_for_deployment = false

  tags = local.common_labels
}

# ── The provider-subdomain indirection (AWS's documented SaaS pattern) ──────
#
# For each custom hostname we mint a name WE own and the tenant CNAMEs to it:
#
#   <custom hostname> CNAME <slug>.<zone>   (the tenant's one record)
#   <slug>.<zone>      CNAME <connection group routing endpoint>
#   _cf-challenge.<slug>.<zone> TXT <connection group routing endpoint>
#
# The tenant's DNS then points at a label we control: every future change —
# new distribution, new connection group, even a non-CloudFront origin — is a
# re-point behind our own name, never a tenant DNS edit. The _cf-challenge TXT
# is the record CloudFront's managed-certificate domain-ownership flow checks
# when the tenant has not pointed DNS directly at CloudFront.

resource "aws_route53_record" "slug" {
  for_each = toset(var.custom_domains)

  zone_id = data.aws_route53_zone.subdomain.zone_id
  name    = "${local.custom_domain_slugs[each.value]}.${var.subdomain_zone_name}"
  type    = "CNAME"
  ttl     = var.slug_ttl
  records = [var.connection_group_endpoint]
}

resource "aws_route53_record" "slug_challenge" {
  for_each = toset(var.custom_domains)

  zone_id = data.aws_route53_zone.subdomain.zone_id
  name    = "_cf-challenge.${local.custom_domain_slugs[each.value]}.${var.subdomain_zone_name}"
  type    = "TXT"
  ttl     = var.slug_ttl
  records = [var.connection_group_endpoint]
}

# ── The routing rows (strategy B) — GATED, decision pending ─────────────────
#
# The platform forwards the custom Host to cloud-proxy, which answers from
# the cloud_domains table keyed by fqdn — so a custom hostname needs a row
# mirroring the tenant's reserved subdomain row. The DESIGN NOTEBOOK has an
# OPEN QUESTION on who writes that row (this addon's direct DynamoDB write
# vs a thin control-plane endpoint that owns the table and its audit trail).
# Until it is settled, the write is opt-in via register_routing = false.
#
# The row is MIRRORED, never invented: the source row (the tenant's reserved
# subdomain registration, written by the platform's own deploy lambda) is
# read by fqdn and copied — instance, instance_fqdn, port, owner — so this
# addon can never disagree with what the platform registered. Timestamps are
# copied too (not regenerated), so repeated applies are no-ops.

data "aws_dynamodb_table_item" "source_routing" {
  count = var.register_routing ? 1 : 0

  table_name = var.cloud_domains_table
  key        = jsonencode({ fqdn = { S = var.source_fqdn } })
}

locals {
  source_routing_row = one(data.aws_dynamodb_table_item.source_routing[*].item)
}

resource "aws_dynamodb_table_item" "custom_domain_routing" {
  for_each = var.register_routing ? toset(var.custom_domains) : toset([])

  table_name = var.cloud_domains_table
  hash_key   = "fqdn"

  item = jsonencode(merge(
    local.source_routing_row,
    { fqdn = { S = each.value } },
  ))
}
