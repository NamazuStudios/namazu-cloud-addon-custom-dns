# What other addons (and operators) can wire against. Resolves per install:
# $addon.custom-dns.<variant>.<output>
#
# The activation-related outputs ARE the deliverable of apply #1: they carry
# the exact DNS records the tenant must publish and the pending/Deployed
# status the fork's reporting surface treats as the completion signal
# (the two-step activation contract).

output "custom_domains" {
  description = "Per custom hostname: the distribution tenant (id, arn, status), the slug record we minted, and the single CNAME the tenant must publish."
  value = {
    for domain in var.custom_domains : domain => {
      distribution_tenant_id  = aws_cloudfront_distribution_tenant.custom_domain[domain].id
      distribution_tenant_arn = aws_cloudfront_distribution_tenant.custom_domain[domain].arn
      # PendingValidation until the tenant's CNAME resolves; Deployed after.
      status    = aws_cloudfront_distribution_tenant.custom_domain[domain].status
      slug_fqdn = aws_route53_record.slug[domain].fqdn
      tenant_cname = {
        name   = domain
        type   = "CNAME"
        target = aws_route53_record.slug[domain].fqdn
      }
    }
  }
}

output "activation_instructions" {
  description = "The exact copy to hand the tenant (operator-curated flow): one CNAME per custom hostname, nothing else. The managed certificate issues automatically once the record resolves — that moment is the ownership proof."
  value = join("\n", [
    for domain in var.custom_domains :
    "${domain} CNAME ${aws_route53_record.slug[domain].fqdn}"
  ])
}

output "routing_rows_registered" {
  description = "Whether the cloud_domains routing rows were written (strategy B). False while the design-notebook decision on the row writer is open; when true, custom hostnames route through cloud-proxy exactly like reserved subdomains."
  value       = var.register_routing
}

output "instance_cors_hostnames" {
  description = "The custom hostnames the instance's CORS allow-list must additionally accept (host-header strategy B: the instance sees the custom Host). This is the SECOND out-of-band step of activation — an operator/portal step, not something this addon can push."
  value       = var.custom_domains
}
