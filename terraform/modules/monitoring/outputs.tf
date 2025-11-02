output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "dashboard_url" {
  description = "URL to view the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "alarm_names" {
  description = "Names of CloudWatch alarms"
  value = {
    rds_cpu_high          = aws_cloudwatch_metric_alarm.rds_cpu_high.alarm_name
    rds_connections_high  = aws_cloudwatch_metric_alarm.rds_connections_high.alarm_name
    ecs_cpu_high          = aws_cloudwatch_metric_alarm.ecs_cpu_high.alarm_name
    alb_response_time     = aws_cloudwatch_metric_alarm.alb_response_time_high.alarm_name
    alb_5xx_errors        = aws_cloudwatch_metric_alarm.alb_5xx_errors.alarm_name
  }
}