# Wire together six focused modules: network, ecr, logging, alb, rds, ecs.

module "network" {
  source         = "./modules/network"
  service_name   = var.service_name
  container_port = var.container_port
}

module "ecr" {
  source          = "./modules/ecr"
  repository_name = var.ecr_repository_name
}

module "logging" {
  source            = "./modules/logging"
  service_name      = var.service_name
  retention_in_days = var.log_retention_days
}

# Application Load Balancer
module "alb" {
  source = "./modules/alb"

  service_name   = var.service_name
  subnet_ids     = module.network.subnet_ids
  container_port = var.container_port
}

# Reuse an existing IAM role for ECS tasks
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# RDS Module - uses default VPC and network subnets
module "rds" {
  source = "./modules/rds"

  project_name           = var.service_name
  private_subnet_ids     = module.network.subnet_ids
  ecs_security_group_id  = module.network.security_group_id

  database_name     = var.db_name
  database_username = var.db_username
  database_password = var.db_password
}

# ECS Module - uses RDS outputs for database connection and ALB for load balancing
module "ecs" {
  source             = "./modules/ecs"
  service_name       = var.service_name
  image              = "${module.ecr.repository_url}:latest"
  container_port     = var.container_port
  subnet_ids         = module.network.subnet_ids
  security_group_ids = [module.network.security_group_id]
  execution_role_arn = data.aws_iam_role.lab_role.arn
  task_role_arn      = data.aws_iam_role.lab_role.arn
  log_group_name     = module.logging.log_group_name
  ecs_count          = var.ecs_count
  region             = var.aws_region
  
  # ALB integration
  target_group_arn  = module.alb.target_group_arn
  alb_listener_arn  = module.alb.alb_arn
  
  # Database configuration from RDS module
  db_host     = module.rds.db_instance_address
  db_port     = module.rds.db_instance_port
  db_name     = module.rds.db_name
  db_user     = var.db_username
  db_password = var.db_password

  depends_on = [module.rds, module.alb]
}

# Build & push the Go app image into ECR
resource "docker_image" "app" {
  name = "${module.ecr.repository_url}:latest"

  build {
    context  = "../src"
    platform = "linux/amd64"
  }
}

resource "docker_registry_image" "app" {
  name = docker_image.app.name
}