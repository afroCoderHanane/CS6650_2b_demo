# RDS MySQL Instance for Product and Shopping Cart Data

# Get the default VPC
data "aws_vpc" "default" {
  default = true
}

# DB Subnet Group using provided subnet IDs
resource "aws_db_subnet_group" "main" {
  name       = lower("${var.project_name}-db-subnet-group")
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS MySQL instance"
  vpc_id      = data.aws_vpc.default.id

  # Allow MySQL access from ECS tasks only
  ingress {
    description     = "MySQL from ECS tasks"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.ecs_security_group_id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# RDS MySQL Instance
resource "aws_db_instance" "mysql" {
  identifier     = lower("${var.project_name}-mysql")
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp2"
  storage_encrypted     = false

  db_name  = var.database_name
  username = var.database_username
  password = var.database_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Assignment settings (not for production!)
  skip_final_snapshot       = true
  deletion_protection       = false
  backup_retention_period   = 0
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  # Wait for network resources
  depends_on = [aws_db_subnet_group.main]

  tags = {
    Name = "${var.project_name}-mysql"
  }
}