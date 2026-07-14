resource "aws_cloudwatch_log_group" "app" {
  name              = "/ex-broadcaster/app"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "system" {
  name              = "/ex-broadcaster/system"
  retention_in_days = var.log_retention_days
}

locals {
  cloudwatch_agent_config = templatefile("${path.module}/amazon-cloudwatch-agent.json.tpl", {
    system_log_group = aws_cloudwatch_log_group.system.name
    gpu_enabled      = var.gpu_enabled
  })
}

resource "aws_sns_topic" "alarms" {
  name = "ex-broadcaster-alarms"
}

resource "aws_sns_topic_subscription" "alarms_email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# Fires when any RTMP target fails health checks — the NLB will stop routing
# to it, but instance_refresh/ASG health checks can lag behind, so this is
# the fastest signal that a node has gone bad.
resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  alarm_name          = "ex-broadcaster-unhealthy-targets"
  namespace           = "AWS/NetworkELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.rtmp.arn_suffix
    LoadBalancer = aws_lb.rtmp.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# Fires when there is zero ingest capacity left — a full outage, distinct
# from "some targets are unhealthy" above.
resource "aws_cloudwatch_metric_alarm" "no_healthy_targets" {
  alarm_name          = "ex-broadcaster-no-healthy-targets"
  namespace           = "AWS/NetworkELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.rtmp.arn_suffix
    LoadBalancer = aws_lb.rtmp.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# Sustained near-100% GPU utilization is the real capacity signal for this
# workload (the ASG scales on CPU, which the Vulkan Video transcode path
# barely touches) — this is a heads-up to raise cpu_target_value/instance
# count or move to GPU-based scaling, not an outage alarm. Skipped entirely
# when gpu_enabled=false since the metric would never get published.
resource "aws_cloudwatch_metric_alarm" "gpu_utilization_high" {
  count               = var.gpu_enabled ? 1 : 0
  alarm_name          = "ex-broadcaster-gpu-utilization-high"
  namespace           = "ExBroadcaster"
  metric_name         = "utilization_gpu"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 95
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.ex_broadcaster.name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
}

locals {
  # GPU/encoder widgets only make sense when there's a GPU publishing them.
  gpu_dashboard_widgets = var.gpu_enabled ? [
    {
      title = "GPU utilization"
      metrics = [
        ["ExBroadcaster", "utilization_gpu", "AutoScalingGroupName", aws_autoscaling_group.ex_broadcaster.name, { stat = "Average" }]
      ]
    },
    {
      title = "NVENC encoder sessions / fps"
      metrics = [
        ["ExBroadcaster", "encoder_stats_session_count", "AutoScalingGroupName", aws_autoscaling_group.ex_broadcaster.name, { stat = "Average" }],
        ["ExBroadcaster", "encoder_stats_average_fps", "AutoScalingGroupName", aws_autoscaling_group.ex_broadcaster.name, { stat = "Average", yAxis = "right" }]
      ]
    }
  ] : []

  base_dashboard_widgets = [
    {
      title = "ASG CPU utilization"
      metrics = [
        ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.ex_broadcaster.name, { stat = "Average" }]
      ]
    },
    {
      title = "NLB healthy / unhealthy targets"
      metrics = [
        ["AWS/NetworkELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.rtmp.arn_suffix, "LoadBalancer", aws_lb.rtmp.arn_suffix, { stat = "Minimum" }],
        ["AWS/NetworkELB", "UnHealthyHostCount", "TargetGroup", aws_lb_target_group.rtmp.arn_suffix, "LoadBalancer", aws_lb.rtmp.arn_suffix, { stat = "Maximum" }]
      ]
    }
  ]

  dashboard_widgets = [
    for idx, w in concat(local.gpu_dashboard_widgets, local.base_dashboard_widgets) : {
      type   = "metric"
      x      = (idx % 2) * 12
      y      = floor(idx / 2) * 6
      width  = 12
      height = 6
      properties = {
        title   = w.title
        region  = var.aws_region
        stacked = false
        metrics = w.metrics
      }
    }
  ]
}

resource "aws_cloudwatch_dashboard" "ex_broadcaster" {
  dashboard_name = "ex-broadcaster"

  dashboard_body = jsonencode({
    widgets = local.dashboard_widgets
  })
}

output "cloudwatch_dashboard_url" {
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.ex_broadcaster.dashboard_name}"
  description = "CloudWatch dashboard with GPU/encoder/CPU/target-health widgets"
}
