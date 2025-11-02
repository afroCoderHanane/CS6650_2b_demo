variable "service_name" {
  description = "Name of the service"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "db_instance_id" {
  description = "RDS database instance identifier"
  type        = string
}

variable "alb_name" {
  description = "ALB name (from ARN)"
  type        = string
}

variable "target_group_name" {
  description = "Target group name (from ARN)"
  type        = string
}