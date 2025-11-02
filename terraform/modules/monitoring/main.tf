# CloudWatch Dashboard for Shopping Cart System Monitoring

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.service_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # RDS CPU Utilization
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id, { stat = "Average", label = "CPU Average" }],
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id, { stat = "Maximum", label = "CPU Maximum" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "RDS CPU Utilization"
          period  = 300
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
        width  = 12
        height = 6
        x      = 0
        y      = 0
      },
      # RDS Database Connections
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_id, { stat = "Average", label = "Active Connections" }],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_id, { stat = "Maximum", label = "Max Connections" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "RDS Database Connections"
          period  = 300
        }
        width  = 12
        height = 6
        x      = 12
        y      = 0
      },
      # RDS I/O Latency
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", var.db_instance_id, { stat = "Average", label = "Read Latency" }],
            ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", var.db_instance_id, { stat = "Average", label = "Write Latency" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "RDS I/O Latency (seconds)"
          period  = 300
          yAxis = {
            left = {
              label = "Seconds"
            }
          }
        }
        width  = 12
        height = 6
        x      = 0
        y      = 6
      },
      # RDS IOPS
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", var.db_instance_id, { stat = "Average", label = "Read IOPS" }],
            ["AWS/RDS", "WriteIOPS", "DBInstanceIdentifier", var.db_instance_id, { stat = "Average", label = "Write IOPS" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "RDS IOPS"
          period  = 300
        }
        width  = 12
        height = 6
        x      = 12
        y      = 6
      },
      # ECS CPU
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ServiceName", var.service_name, "ClusterName", var.cluster_name, { stat = "Average", label = "CPU Average" }],
            ["AWS/ECS", "CPUUtilization", "ServiceName", var.service_name, "ClusterName", var.cluster_name, { stat = "Maximum", label = "CPU Maximum" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "ECS CPU Utilization"
          period  = 300
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
        width  = 12
        height = 6
        x      = 0
        y      = 12
      },
      # ECS Memory
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ECS", "MemoryUtilization", "ServiceName", var.service_name, "ClusterName", var.cluster_name, { stat = "Average", label = "Memory Average" }],
            ["AWS/ECS", "MemoryUtilization", "ServiceName", var.service_name, "ClusterName", var.cluster_name, { stat = "Maximum", label = "Memory Maximum" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "ECS Memory Utilization"
          period  = 300
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
        width  = 12
        height = 6
        x      = 12
        y      = 12
      },
      # ALB Response Time
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_name, { stat = "Average", label = "Response Time (avg)" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "ALB Response Time"
          period  = 300
          yAxis = {
            left = {
              label = "Seconds"
            }
          }
        }
        width  = 12
        height = 6
        x      = 0
        y      = 18
      },
      # ALB Request Count
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_name, { stat = "Sum", label = "Total Requests" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", var.alb_name, { stat = "Sum", label = "Success (2XX)" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_name, { stat = "Sum", label = "Server Errors (5XX)" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "ALB Request Count"
          period  = 300
        }
        width  = 12
        height = 6
        x      = 12
        y      = 18
      },
      # Target Health
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", var.target_group_name, "LoadBalancer", var.alb_name, { stat = "Average", label = "Healthy" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", var.target_group_name, "LoadBalancer", var.alb_name, { stat = "Average", label = "Unhealthy" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Target Health"
          period  = 300
        }
        width  = 12
        height = 6
        x      = 0
        y      = 24
      }
    ]
  })
}

# CloudWatch Alarms

# RDS High CPU Alarm
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${var.service_name}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU utilization is too high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }
}

# RDS High Connections Alarm
resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  alarm_name          = "${var.service_name}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 20
  alarm_description   = "RDS has too many connections"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }
}

# ECS High CPU Alarm
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${var.service_name}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS CPU utilization is too high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ServiceName = var.service_name
    ClusterName = var.cluster_name
  }
}

# ALB High Response Time Alarm
resource "aws_cloudwatch_metric_alarm" "alb_response_time_high" {
  alarm_name          = "${var.service_name}-alb-response-time-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 0.1
  alarm_description   = "ALB response time is too high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_name
  }
}

# ALB 5XX Errors Alarm
resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "${var.service_name}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Too many 5XX errors from targets"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_name
  }
}