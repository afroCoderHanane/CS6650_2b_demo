output "db_instance_endpoint" {
  description = "Connection endpoint for the RDS instance"
  value       = aws_db_instance.mysql.endpoint
}

output "db_instance_address" {
  description = "Hostname of the RDS instance"
  value       = aws_db_instance.mysql.address
}

output "db_instance_port" {
  description = "Port the database is listening on"
  value       = aws_db_instance.mysql.port
}

output "db_name" {
  description = "Name of the database"
  value       = aws_db_instance.mysql.db_name
}

output "db_username" {
  description = "Master username"
  value       = aws_db_instance.mysql.username
  sensitive   = true
}

output "security_group_id" {
  description = "Security group ID for the RDS instance"
  value       = aws_security_group.rds.id
}