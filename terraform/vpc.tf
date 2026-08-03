# Picks 2 AZs from whichever region var.aws_region resolves to, instead of
# hardcoding region-specific AZ names that would break the moment aws_region
# is changed.
data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "ex-broadcaster-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true # Required for instances in private subnets to reach ECR/S3
  single_nat_gateway = true
}
