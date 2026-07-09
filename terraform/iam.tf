data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ex_broadcaster" {
  name               = "ex-broadcaster-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

# S3 access scoped to the HLS bucket only. ex_aws's default credential chain
# falls back to this instance role via IMDS when no AWS_ACCESS_KEY_ID/
# AWS_SECRET_ACCESS_KEY env vars are set, so no static credentials are needed.
data "aws_iam_policy_document" "hls_bucket_access" {
  statement {
    sid       = "HlsBucketObjectAccess"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.hls.arn}/*"]
  }

  statement {
    sid       = "HlsBucketListAccess"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.hls.arn]
  }
}

resource "aws_iam_role_policy" "hls_bucket_access" {
  name   = "hls-bucket-access"
  role   = aws_iam_role.ex_broadcaster.id
  policy = data.aws_iam_policy_document.hls_bucket_access.json
}

# ECR pull permissions so user-data can `docker login`/`docker pull` without
# static credentials.
resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.ex_broadcaster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# SSM Session Manager access, for debugging/verification without SSH or a
# public IP.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ex_broadcaster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ex_broadcaster" {
  name = "ex-broadcaster-instance-profile"
  role = aws_iam_role.ex_broadcaster.name
}
