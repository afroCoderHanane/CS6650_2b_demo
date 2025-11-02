#!/bin/bash

# ============================================
# Complete AWS Deployment Script
# CS6650 - MySQL Shopping Cart System
# ============================================
# This script will:
# 1. Configure AWS credentials
# 2. Set up Terraform
# 3. Deploy infrastructure
# 4. Test the deployment
# ============================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================"
echo "CS6650 MySQL Shopping Cart - Complete Setup"
echo "============================================"
echo ""

# # ============================================
# # Step 1: AWS Configuration
# # ============================================
# echo "${BLUE}Step 1: AWS Configuration${NC}"
# echo "============================================"
# echo ""

# echo "Please enter your AWS credentials from AWS Academy Lab:"
# echo ""
# read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
# read -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
# read -p "AWS Session Token: " AWS_SESSION_TOKEN
# echo ""

# # Configure AWS CLI
# export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
# export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
# export AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN"
# export AWS_DEFAULT_REGION="us-west-2"

# # Save to AWS credentials file (optional but recommended)
# mkdir -p ~/.aws
# cat > ~/.aws/credentials << EOF
# [default]
# aws_access_key_id = $AWS_ACCESS_KEY_ID
# aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
# aws_session_token = $AWS_SESSION_TOKEN
# EOF

# cat > ~/.aws/config << EOF
# [default]
# region = us-west-2
# output = json
# EOF

# echo "${GREEN}✓ AWS credentials configured${NC}"
# echo ""

# # Verify AWS credentials
# echo "Verifying AWS credentials..."
# if aws sts get-caller-identity &> /dev/null; then
#     echo "${GREEN}✓ AWS credentials verified successfully${NC}"
#     aws sts get-caller-identity
# else
#     echo "${RED}✗ Failed to verify AWS credentials. Please check your credentials and try again.${NC}"
#     exit 1
# fi
# echo ""

# ============================================
# Step 2: Database Password Setup
# ============================================
echo "${BLUE}Step 2: Database Password Configuration${NC}"
echo "============================================"
echo ""

read -sp "Enter a secure database password (min 8 characters): " DB_PASSWORD
echo ""
read -sp "Confirm database password: " DB_PASSWORD_CONFIRM
echo ""

if [ "$DB_PASSWORD" != "$DB_PASSWORD_CONFIRM" ]; then
    echo "${RED}✗ Passwords do not match!${NC}"
    exit 1
fi

if [ ${#DB_PASSWORD} -lt 8 ]; then
    echo "${RED}✗ Password must be at least 8 characters!${NC}"
    exit 1
fi

echo "${GREEN}✓ Database password configured${NC}"
echo ""

# ============================================
# Step 3: Create terraform.tfvars
# ============================================
echo "${BLUE}Step 3: Creating Terraform Configuration${NC}"
echo "============================================"
echo ""

cd terraform

cat > terraform.tfvars << EOF
# AWS Configuration
aws_region = "us-west-2"

# Service Configuration
service_name        = "CS6650L2"
ecr_repository_name = "ecr_service"
container_port      = 8080
ecs_count           = 2

# Logging
log_retention_days = 7

# Database Configuration
db_name     = "productdb"
db_username = "admin"
db_password = "$DB_PASSWORD"
EOF

echo "${GREEN}✓ terraform.tfvars created${NC}"
echo ""

# ============================================
# Step 4: Initialize Terraform
# ============================================
echo "${BLUE}Step 4: Initializing Terraform${NC}"
echo "============================================"
echo ""

if ! command -v terraform &> /dev/null; then
    echo "${RED}✗ Terraform not found!${NC}"
    echo "Please install Terraform from: https://www.terraform.io/downloads"
    exit 1
fi

echo "Terraform version:"
terraform version
echo ""

echo "Initializing Terraform..."
terraform init -upgrade

if [ $? -eq 0 ]; then
    echo "${GREEN}✓ Terraform initialized successfully${NC}"
else
    echo "${RED}✗ Terraform initialization failed${NC}"
    exit 1
fi
echo ""

# ============================================
# Step 5: Terraform Plan
# ============================================
echo "${BLUE}Step 5: Creating Deployment Plan${NC}"
echo "============================================"
echo ""

echo "Generating deployment plan..."
terraform plan -out=tfplan

if [ $? -eq 0 ]; then
    echo "${GREEN}✓ Deployment plan created${NC}"
else
    echo "${RED}✗ Failed to create deployment plan${NC}"
    exit 1
fi
echo ""

echo "${YELLOW}Review the plan above. This will create:${NC}"
echo "  - VPC with public/private subnets"
echo "  - RDS MySQL database (db.t3.micro)"
echo "  - ECS Fargate cluster and service"
echo "  - Application Load Balancer"
echo "  - ECR repository"
echo "  - CloudWatch log groups"
echo ""

read -p "Do you want to proceed with deployment? (yes/no): " PROCEED

if [ "$PROCEED" != "yes" ]; then
    echo "${YELLOW}Deployment cancelled${NC}"
    exit 0
fi
echo ""

# ============================================
# Step 6: Deploy Infrastructure
# ============================================
echo "${BLUE}Step 6: Deploying Infrastructure${NC}"
echo "============================================"
echo ""
echo "${YELLOW}This will take 15-20 minutes (RDS provisioning is slow)...${NC}"
echo ""

terraform apply tfplan

if [ $? -eq 0 ]; then
    echo ""
    echo "${GREEN}✓ Infrastructure deployed successfully!${NC}"
else
    echo "${RED}✗ Deployment failed${NC}"
    exit 1
fi
echo ""

# ============================================
# Step 7: Get Deployment Information
# ============================================
echo "${BLUE}Step 7: Retrieving Deployment Information${NC}"
echo "============================================"
echo ""

ALB_URL=$(terraform output -raw alb_url 2>/dev/null)
ECS_CLUSTER=$(terraform output -raw ecs_cluster_name 2>/dev/null)
ECS_SERVICE=$(terraform output -raw ecs_service_name 2>/dev/null)
RDS_ENDPOINT=$(terraform output -raw rds_address 2>/dev/null)
LOG_GROUP=$(terraform output -raw log_group_name 2>/dev/null)

echo "Deployment Information:"
echo "----------------------"
echo "Application URL: ${GREEN}$ALB_URL${NC}"
echo "ECS Cluster: $ECS_CLUSTER"
echo "ECS Service: $ECS_SERVICE"
echo "RDS Endpoint: $RDS_ENDPOINT"
echo "Log Group: $LOG_GROUP"
echo ""

# ============================================
# Step 8: Wait for Services to be Ready
# ============================================
echo "${BLUE}Step 8: Waiting for Services to Stabilize${NC}"
echo "============================================"
echo ""

echo "Waiting for ECS service to become stable (this may take 2-5 minutes)..."
aws ecs wait services-stable \
    --cluster $ECS_CLUSTER \
    --services $ECS_SERVICE \
    --region us-west-2

if [ $? -eq 0 ]; then
    echo "${GREEN}✓ ECS service is stable${NC}"
else
    echo "${YELLOW}⚠ Service may still be starting. Check AWS console for details.${NC}"
fi
echo ""

# Wait a bit more for ALB health checks
echo "Waiting for health checks to pass (30 seconds)..."
sleep 30
echo ""

# ============================================
# Step 9: Test Deployment
# ============================================
echo "${BLUE}Step 9: Testing Deployment${NC}"
echo "============================================"
echo ""

echo "Testing health endpoint..."
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $ALB_URL/health)

if [ "$HEALTH_STATUS" == "200" ]; then
    echo "${GREEN}✓ Health check passed (HTTP $HEALTH_STATUS)${NC}"
else
    echo "${YELLOW}⚠ Health check returned HTTP $HEALTH_STATUS${NC}"
    echo "The service may still be starting. Wait a minute and try again."
fi
echo ""

echo "Creating a test shopping cart..."
CART_RESPONSE=$(curl -s -X POST $ALB_URL/shopping-carts \
    -H "Content-Type: application/json" \
    -d '{"customerId": 1, "customerName": "Test User", "customerEmail": "test@example.com"}')

CART_ID=$(echo $CART_RESPONSE | grep -o '"id":[0-9]*' | grep -o '[0-9]*' | head -1)

if [ -n "$CART_ID" ]; then
    echo "${GREEN}✓ Shopping cart created successfully (ID: $CART_ID)${NC}"
    echo "Response: $CART_RESPONSE"
    echo ""
    
    echo "Adding item to cart..."
    ADD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST $ALB_URL/shopping-carts/$CART_ID/items \
        -H "Content-Type: application/json" \
        -d '{"productId": 1, "quantity": 2}')
    
    if [ "$ADD_STATUS" == "204" ]; then
        echo "${GREEN}✓ Item added to cart (HTTP $ADD_STATUS)${NC}"
    else
        echo "${YELLOW}⚠ Failed to add item (HTTP $ADD_STATUS)${NC}"
    fi
    echo ""
    
    echo "Retrieving cart with items..."
    CART_WITH_ITEMS=$(curl -s $ALB_URL/shopping-carts/$CART_ID)
    echo "$CART_WITH_ITEMS" | python3 -m json.tool 2>/dev/null || echo "$CART_WITH_ITEMS"
else
    echo "${YELLOW}⚠ Failed to create shopping cart. Check logs for details.${NC}"
fi
echo ""

# ============================================
# Step 10: Display Final Information
# ============================================
echo "============================================"
echo "${GREEN}🎉 Deployment Complete!${NC}"
echo "============================================"
echo ""
echo "Application URL: ${GREEN}$ALB_URL${NC}"
echo ""
echo "${BLUE}Quick Test Commands:${NC}"
echo "-------------------"
echo "# Health check"
echo "curl $ALB_URL/health"
echo ""
echo "# Create shopping cart"
echo "curl -X POST $ALB_URL/shopping-carts \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"customerId\": 1, \"customerName\": \"John Doe\", \"customerEmail\": \"john@example.com\"}'"
echo ""
echo "# Get cart (replace 1 with actual cart ID)"
echo "curl $ALB_URL/shopping-carts/1"
echo ""
echo "# Add item to cart"
echo "curl -X POST $ALB_URL/shopping-carts/1/items \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"productId\": 1, \"quantity\": 2}'"
echo ""
echo "${BLUE}Monitoring Commands:${NC}"
echo "-------------------"
echo "# View logs"
echo "aws logs tail $LOG_GROUP --follow --region us-west-2"
echo ""
echo "# View ECS service status"
echo "aws ecs describe-services --cluster $ECS_CLUSTER --services $ECS_SERVICE --region us-west-2"
echo ""
echo "# Force new deployment (after code changes)"
echo "aws ecs update-service --cluster $ECS_CLUSTER --service $ECS_SERVICE --force-new-deployment --region us-west-2"
echo ""
echo "${BLUE}Performance Testing:${NC}"
echo "-------------------"
echo "cd ../src"
echo "locust -f locustfile.py --host=$ALB_URL --users=100 --spawn-rate=20 --run-time=2m --headless"
echo "python3 generate_report.py"
echo "open performance_report.html"
echo ""
echo "${BLUE}Cleanup (when done):${NC}"
echo "-------------------"
echo "cd terraform"
echo "terraform destroy"
echo ""
echo "${GREEN}Deployment successful!${NC}"
echo "============================================"
echo ""

# Save deployment info to file
cat > deployment_info.txt << EOF
Deployment Information
======================
Deployment Date: $(date)
Application URL: $ALB_URL
ECS Cluster: $ECS_CLUSTER
ECS Service: $ECS_SERVICE
RDS Endpoint: $RDS_ENDPOINT
Log Group: $LOG_GROUP
Region: us-west-2

Quick Commands:
===============
Test: curl $ALB_URL/health
Logs: aws logs tail $LOG_GROUP --follow --region us-west-2
EOF

echo "${GREEN}✓ Deployment info saved to terraform/deployment_info.txt${NC}"
echo ""