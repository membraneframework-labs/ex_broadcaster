variable "aws_region" {
  description = "AWS region (must match the ambient provider config)"
  type        = string
  default     = "eu-north-1"
}

variable "instance_type" {
  description = "Instance type for the ASG. Must be a GPU instance — the pipeline uses Membrane.Transcoder with Vulkan Video hardware acceleration. g6.xlarge (NVIDIA L4) matches the GPU node group previously used for the EKS setup"
  type        = string
  default     = "g6.xlarge"
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
