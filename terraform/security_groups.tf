resource "aws_security_group" "instance" {
  name_prefix = "ex-broadcaster-instance-"
  description = "ex_broadcaster instances"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "RTMP ingest from the internet via the NLB (client IP is preserved by the NLB, so this must be world-open, not VPC-scoped)"
    from_port   = 1935
    to_port     = 1935
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # No inbound SSH rule: SSH access goes over an SSM Session Manager tunnel
  # (see ssh.tf), not a direct port 22 opening.

  egress {
    description = "Allow all egress (ECR/S3 via NAT, SSM endpoints, etc.)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}
