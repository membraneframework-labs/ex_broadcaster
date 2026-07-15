variable "aws_region" {
  description = "AWS region (must match the ambient provider config)"
  type        = string
  default     = "eu-north-1"
}

variable "gpu_enabled" {
  description = "Whether the ASG instances have an NVIDIA GPU and should be bootstrapped for Vulkan Video hardware acceleration"
  type        = bool
  default     = true
}

variable "instance_type" {
  # Leave unset to pick a sensible default from gpu_enabled: g6.xlarge
  # (NVIDIA L4, matching the GPU node group previously used for the EKS
  # setup) when true, c6i.large (compute-optimized, no GPU) when false. Set
  # explicitly to override either default.
  description = "Instance type for the ASG. If null, derived from gpu_enabled (see locals.instance_type in asg.tf)"
  type        = string
  default     = null
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
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
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

variable "log_retention_days" {
  description = "Retention for the CloudWatch Logs groups (app + system logs)"
  type        = number
  default     = 14
}

variable "alarm_email" {
  description = "Email address to subscribe to the ex-broadcaster-alarms SNS topic. Leave empty to skip creating a subscription (alarms still fire and show up in the CloudWatch console either way)"
  type        = string
  default     = ""
}

variable "enable_cdn" {
  description = "Whether to provision a CloudFront distribution in front of the HLS bucket"
  type        = bool
  default     = true
}

variable "cloudfront_price_class" {
  description = "CloudFront price class — PriceClass_100 (NA/EU edge locations only, cheapest), PriceClass_200 (adds Asia/Africa/Oceania), or PriceClass_All (every edge location)"
  type        = string
  default     = "PriceClass_100"
}
