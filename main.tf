locals {
  s3_domain_name = "${var.local_prefix}.sctp-sandbox.com"
}

resource "aws_s3_bucket" "s3_bucket" {
  bucket = local.s3_domain_name
  force_destroy = true
}

resource "aws_s3_bucket_policy" "s3_policy" {
  bucket = aws_s3_bucket.s3_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontServicePrincipal",
      Effect    = "Allow"
      Principal = { "Service": "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.s3_bucket.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.cloudfront.arn }
      }
    }]
  })
}

resource "aws_acm_certificate" "cert" {
  domain_name       = local.s3_domain_name
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.local_prefix}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cloudfront" {
  origin {
    domain_name              = aws_s3_bucket.s3_bucket.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.s3_bucket.id
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = [local.s3_domain_name]

  web_acl_id = aws_wafv2_web_acl.waf_acl.arn

  default_cache_behavior {
    target_origin_id       = aws_s3_bucket.s3_bucket.id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id  = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS Managed CachingOptimized
    compress = true

  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Description = "lukecode"
  }

}

resource "aws_wafv2_web_acl" "waf_acl" {
  name        = "${var.local_prefix}-waf"
  scope       = "CLOUDFRONT"
  description = "WAF for ${var.local_prefix}"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.local_prefix}-waf"
    sampled_requests_enabled   = true
  }
 }

resource "aws_route53_record" "dns_record" {
  zone_id = "Z00541411T1NGPV97B5C0"  # SCTP-SANDBOX.COM's ID
  name    = local.s3_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cloudfront.domain_name
    zone_id                = aws_cloudfront_distribution.cloudfront.hosted_zone_id
    evaluate_target_health = false
  }
}