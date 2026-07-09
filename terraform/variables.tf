variable "aws_region" {
  description = "AWS region (must match the ambient provider config)"
  type        = string
  default     = "eu-north-1"
}

variable "instance_type" {
  description = "Instance type for the ASG (compute-optimized; no GPU needed, transcoding runs in software)"
  type        = string
  default     = "c6i.large"
}

variable "asg_min_size" {
  type    = number
  default = 1
}

variable "asg_max_size" {
  type    = number
  default = 3
}

variable "asg_desired_capacity" {
  type    = number
  default = 1
}

variable "cpu_target_value" {
  description = "Target average CPU utilization (%) for the ASG target-tracking scaling policy"
  type        = number
  default     = 60
}

variable "root_volume_size_gb" {
  type    = number
  default = 30
}

variable "app_image_tag" {
  description = "ECR image tag to deploy"
  type        = string
  default     = "latest"
}

variable "s3_prefix" {
  type    = string
  default = "hls"
}
