data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

locals {
  instance_type = coalesce(var.instance_type, var.gpu_enabled ? "g6.xlarge" : "c6i.large")
}

resource "aws_launch_template" "ex_broadcaster" {
  name_prefix   = "ex-broadcaster-"
  image_id      = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type = local.instance_type
  key_name      = aws_key_pair.ex_broadcaster.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ex_broadcaster.name
  }

  vpc_security_group_ids = [aws_security_group.instance.id]

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = var.root_volume_size_gb
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    aws_region              = var.aws_region
    ecr_repository_url      = aws_ecr_repository.ex_broadcaster.repository_url
    image_tag               = var.app_image_tag
    s3_bucket               = aws_s3_bucket.hls.bucket
    s3_prefix               = var.s3_prefix
    app_log_group           = aws_cloudwatch_log_group.app.name
    cloudwatch_agent_config = local.cloudwatch_agent_config
    gpu_enabled             = var.gpu_enabled
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "ex-broadcaster" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "ex_broadcaster" {
  name                      = "ex-broadcaster-asg"
  vpc_zone_identifier       = module.vpc.private_subnets
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  health_check_type         = "ELB"
  health_check_grace_period = 300
  target_group_arns         = [aws_lb_target_group.rtmp.arn]

  launch_template {
    id      = aws_launch_template.ex_broadcaster.id
    version = aws_launch_template.ex_broadcaster.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 300
    }
  }

  tag {
    key                 = "Name"
    value               = "ex-broadcaster"
    propagate_at_launch = true
  }
}

# NOTE: RTMP streams are long-lived stateful TCP connections. Scale-in or a
# rolling instance refresh cuts off any in-progress stream on the terminated
# instance with no graceful drain. A future aws_autoscaling_lifecycle_hook
# could wait for zero active pipelines before allowing termination.
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "ex-broadcaster-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.ex_broadcaster.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target_value
  }
}
