locals {
  acm_dns_validation_records = var.cloudflare_zone_id == null ? {} : var.acm_dns_validation_records
}

resource "cloudflare_record" "acm_dns_validation" {
  for_each = local.acm_dns_validation_records

  zone_id = var.cloudflare_zone_id
  name    = trimsuffix(each.value.name, ".")
  content = trimsuffix(each.value.content, ".")
  type    = "CNAME"
  ttl     = 1
  proxied = false
  comment = "ACM DNS validation record for managed certificate renewal."

  lifecycle {
    prevent_destroy = true
  }
}
