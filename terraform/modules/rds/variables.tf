variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where RDS will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for RDS subnet group"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "Security group ID of ECS tasks that need database access"
  type        = string
}

variable "database_name" {
  description = "Name of the default database to create"
  type        = string
  default     = "productdb"
}

variable "database_username" {
  description = "Master username for the database"
  type        = string
  default     = "admin"
}

variable "database_password" {
  description = "Master password for the database"
  type        = string
  sensitive   = true
}