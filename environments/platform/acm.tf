locals {
  create_ingress_acm_certificate = try(trimspace(var.ingress_lb_acm_certificate_arn), "") == ""
}

resource "aws_acm_certificate" "ingress" {
  count = local.create_ingress_acm_certificate ? 1 : 0

  domain_name               = var.ingress_certificate_domain_name
  subject_alternative_names = var.ingress_certificate_subject_alternative_names
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

locals {
  ingress_acm_domain_validation_option = local.create_ingress_acm_certificate ? one(aws_acm_certificate.ingress[0].domain_validation_options) : null
}

resource "cloudflare_dns_record" "ingress_acm_validation" {
  count = local.create_ingress_acm_certificate ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = trimsuffix(local.ingress_acm_domain_validation_option.resource_record_name, ".")
  type    = local.ingress_acm_domain_validation_option.resource_record_type
  content = trimsuffix(local.ingress_acm_domain_validation_option.resource_record_value, ".")
  ttl     = 60
  proxied = false
}

resource "aws_acm_certificate_validation" "ingress" {
  count = local.create_ingress_acm_certificate ? 1 : 0

  certificate_arn         = aws_acm_certificate.ingress[0].arn
  validation_record_fqdns = ["${cloudflare_dns_record.ingress_acm_validation[0].name}."]
}

locals {
  resolved_ingress_lb_acm_certificate_arn = local.create_ingress_acm_certificate ? aws_acm_certificate_validation.ingress[0].certificate_arn : var.ingress_lb_acm_certificate_arn
}
