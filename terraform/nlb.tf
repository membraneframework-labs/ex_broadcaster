resource "aws_lb" "rtmp" {
  name               = "ex-broadcaster-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = module.vpc.public_subnets

  # Required: NLBs default this to false. With desired_capacity starting at 1
  # instance in a single AZ, the NLB node in the other AZ would otherwise have
  # no local healthy target and fail ~50% of new connections.
  enable_cross_zone_load_balancing = true
}

resource "aws_lb_target_group" "rtmp" {
  name        = "ex-broadcaster-rtmp"
  port        = 1935
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = module.vpc.vpc_id

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  # Long-lived RTMP connections: give in-flight streams a best-effort chance
  # to finish before the target is fully deregistered.
  deregistration_delay = 120
}

resource "aws_lb_listener" "rtmp" {
  load_balancer_arn = aws_lb.rtmp.arn
  port              = 1935
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rtmp.arn
  }
}

output "rtmp_ingest_endpoint" {
  value       = "rtmp://${aws_lb.rtmp.dns_name}:1935"
  description = "Point OBS/streaming clients at this base URL (append your stream app/stream key path)"
}
