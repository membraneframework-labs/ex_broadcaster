terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.79.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
  }
}

# Ties the whole configuration to var.aws_region so that changing it (instead
# of relying on the ambient AWS_REGION/profile default) is enough to deploy
# into a different region end to end.
provider "aws" {
  region = var.aws_region
}
