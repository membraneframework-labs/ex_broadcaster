# CloudFront distribution fronting the HLS bucket. Uses the bucket's public REST
# endpoint as a custom origin (no Origin Access Control) since aws_s3_bucket_policy.hls_public_read
# in s3.tf already allows unauthenticated s3:GetObject — CloudFront just adds edge caching and
# HTTPS/HTTP2-3 in front of that same, already-public origin.

# Hardcoded IDs for AWS-managed CloudFront policies (stable across all accounts/regions).
# Using the IDs directly instead of the data.aws_cloudfront_cache_policy/data.aws_cloudfront_origin_request_policy
# data sources avoids requiring cloudfront:ListCachePolicies/ListOriginRequestPolicies permissions,
# which the deploying IAM user doesn't have.
locals {
  cloudfront_cache_policy_caching_optimized_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  cloudfront_cache_policy_caching_disabled_id  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  cloudfront_origin_request_policy_cors_s3_id  = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
}

resource "aws_cloudfront_distribution" "hls" {
  count = var.enable_cdn ? 1 : 0

  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = var.cloudfront_price_class
  comment         = "ex-broadcaster HLS distribution"

  origin {
    domain_name = aws_s3_bucket.hls.bucket_regional_domain_name
    origin_id   = "hls-s3-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Segments (.m4s/.mp4): immutable once written, safe to cache aggressively at the edge.
  default_cache_behavior {
    target_origin_id         = "hls-s3-origin"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = local.cloudfront_cache_policy_caching_optimized_id
    origin_request_policy_id = local.cloudfront_origin_request_policy_cors_s3_id
  }

  # Playlists (.m3u8): rewritten on every new segment, must not be cached at the edge or
  # viewers get served a stale variant/segment list.
  ordered_cache_behavior {
    path_pattern             = "*.m3u8"
    target_origin_id         = "hls-s3-origin"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = local.cloudfront_cache_policy_caching_disabled_id
    origin_request_policy_id = local.cloudfront_origin_request_policy_cors_s3_id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

output "cdn_domain_name" {
  value       = var.enable_cdn ? aws_cloudfront_distribution.hls[0].domain_name : null
  description = "CloudFront distribution domain (d111111abcdef8.cloudfront.net). Prefix HLS URLs with https://<this>/ instead of the S3 bucket URL once DNS/cache propagation completes"
}
