#!/bin/bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "Applying schema via ECS task..."

# Get values from terraform
cd ../terraform
CLUSTER=$(terraform output -raw ecs_cluster_name)
TASK_DEF=$(aws ecs describe-services --cluster $CLUSTER --services CS6650L2-service --region us-west-2 --query 'services[0].taskDefinition' --output text)
SUBNET_IDS=$(terraform output -json subnet_ids | jq -r '.[]' | head -1)
SG_ID=$(terraform output -raw security_group_id)

echo "Cluster: $CLUSTER"
echo "Subnet: $SUBNET_IDS"
echo "Security Group: $SG_ID"

# Run a one-off task with schema application command
echo ""
echo "${YELLOW}Running ECS task to apply schema...${NC}"

TASK_ARN=$(aws ecs run-task \
    --cluster $CLUSTER \
    --task-definition $TASK_DEF \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
    --region us-west-2 \
    --overrides '{
        "containerOverrides": [{
            "name": "CS6650L2-container",
            "command": ["/bin/sh", "-c", "mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME < schema.sql && echo Schema applied successfully"]
        }]
    }' \
    --query 'tasks[0].taskArn' \
    --output text)

echo "Task ARN: $TASK_ARN"
echo ""
echo "${YELLOW}Waiting for task to complete (this may take 2-3 minutes)...${NC}"

# Wait for task to stop
aws ecs wait tasks-stopped \
    --cluster $CLUSTER \
    --tasks $TASK_ARN \
    --region us-west-2

# Get task exit code
EXIT_CODE=$(aws ecs describe-tasks \
    --cluster $CLUSTER \
    --tasks $TASK_ARN \
    --region us-west-2 \
    --query 'tasks[0].containers[0].exitCode' \
    --output text)

if [ "$EXIT_CODE" = "0" ]; then
    echo ""
    echo "${GREEN}✓ Schema applied successfully!${NC}"
else
    echo ""
    echo "${RED}✗ Schema application failed (exit code: $EXIT_CODE)${NC}"
    echo "Check logs:"
    echo "aws logs tail /ecs/CS6650L2 --since 5m --region us-west-2"
fi
