data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "hls" {
  bucket = "ex-broadcaster-hls-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "hls" {
  bucket = aws_s3_bucket.hls.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "hls_public_read" {
  bucket = aws_s3_bucket.hls.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.hls.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.hls]
}

resource "aws_s3_bucket_cors_configuration" "hls" {
  bucket = aws_s3_bucket.hls.id

  cors_rule {
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

output "hls_bucket_name" {
  value       = aws_s3_bucket.hls.bucket
  description = "Bucket name to put in k8s/configmap.yaml as S3_BUCKET"
}

output "hls_bucket_url" {
  value       = "https://${aws_s3_bucket.hls.bucket}.s3.${aws_s3_bucket.hls.region}.amazonaws.com"
  description = "Base URL for unauthenticated HLS playback"
}
