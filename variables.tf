# Addon-owned inputs — fed per install from the consuming fork's matrix entry
# via the runner's `contract` input (--contract KEY=JSON). Nothing is bound
# statically in manifest.yaml: every value here is tenant- or
# environment-specific, so the entry is the request AND the config. Contract
# variables (instance_id, organization_id, ...) are NOT declared here: see
# 20-variables.tf and author rule 1 in feature.tf.

variable "custom_domains" {
  description = "Custom hostnames the tenant routes to their instance (e.g. [\"play.them.com\"]). Each becomes one CloudFront distribution tenant with its own managed certificate. CloudFront serves the certificate validation token itself; the domain must be NEW (not carrying existing traffic) — see the two-step activation contract in README.md."
  type        = list(string)
}

variable "distribution_id" {
  description = "ID of the platform's CloudFront multi-tenant distribution (SaaS Manager). Created and owned by namazu-cloud-terraform's global module — see that repo's custom-dns platform issue for the prerequisite."
  type        = string
}

variable "connection_group_id" {
  description = "ID of the CloudFront connection group the distribution tenants attach to. The platform publishes this alongside the distribution. Optional: omitted, CloudFront assigns the default connection group."
  type        = string
  default     = null
}

variable "connection_group_endpoint" {
  description = "The connection group's routing endpoint (dXXXX.cloudfront.net). The per-domain slug records in our zone alias to it, and it is the value behind every tenant CNAME after indirection."
  type        = string
}

variable "subdomain_zone_id" {
  description = "Route 53 zone id of the reservable subdomain zone (e.g. the cloud.namazustudios.com zone). The addon writes its slug records here — same zone every tenant A-alias record already lives in."
  type        = string
}

variable "subdomain_zone_name" {
  description = "The zone's DNS name (e.g. cloud.namazustudios.com), used to build the slug fqdn published to the tenant."
  type        = string
}

variable "register_routing" {
  description = "Also write the cloud_domains DynamoDB routing rows for the custom hostnames (strategy B: the custom Host is forwarded end to end, so cloud-proxy must answer for it). Default false PENDING the design-notebook decision on who writes cloud_domains (addon direct write vs a control-plane endpoint). While false, this addon mints the edge objects and emits its outputs but custom hostnames will not route."
  type        = bool
  default     = false
}

variable "source_fqdn" {
  description = "The tenant's existing reserved subdomain fqdn whose routing row is mirrored onto the custom hostnames (required when register_routing is true). The row is READ and copied — instance, instance_fqdn, port, owner — never invented."
  type        = string
  default     = null
}

variable "cloud_domains_table" {
  description = "Name of the cloud_domains DynamoDB table (e.g. production_cloud_domains). Required only when register_routing is true."
  type        = string
  default     = null
}

variable "slug_ttl" {
  description = "TTL of the slug CNAME / challenge TXT records, seconds."
  type        = number
  default     = 300
}
