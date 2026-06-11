module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.1"

  cluster_name    = "transcoder-cluster"
  cluster_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true

  cluster_endpoint_public_access = true

  cluster_addons = {
    coredns                = { most_recent = true }
    eks-pod-identity-agent = { most_recent = true }
    kube-proxy             = { most_recent = true }
    vpc-cni                = { most_recent = true }
  }

  eks_managed_node_groups = {
    general = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 1
      desired_size   = 1
    }

    gpu = {
      ami_type       = "AL2_x86_64_GPU"
      instance_types = ["g6.xlarge"]
      min_size       = 1
      max_size       = 1
      desired_size   = 1
      disk_size      = 80

      labels = {
        "node.kubernetes.io/accelerator" = "nvidia-l4"
      }

      taints = {
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  tags = {
    Environment = "transcoding-tutorial"
    GithubRepo  = "membraneframework/tutorial_vk_video"
  }
}
