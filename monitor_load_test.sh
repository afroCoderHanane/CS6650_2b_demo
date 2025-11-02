#!/bin/bash

# ============================================
# CloudWatch Metrics Viewer
# Real-time monitoring for Shopping Cart System
# macOS compatible version
# ============================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get deployment info
cd terraform 2>/dev/null || cd ../terraform
SERVICE_NAME=$(terraform output -raw ecs_service_name 2>/dev/null)
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null)
DB_INSTANCE_ID="cs6650l2-mysql"
REGION="us-west-2"
cd - > /dev/null

echo "============================================"
echo "CloudWatch Metrics - Shopping Cart System"
echo "============================================"
echo "Time: $(date)"
echo ""

# macOS compatible date for 10 minutes ago
START_TIME=$(date -u -v-10M +"%Y-%m-%dT%H:%M:%S")
END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S")

# Function to get latest metric value
get_latest_metric() {
    local value=$1
    if [ "$value" = "None" ] || [ -z "$value" ]; then
        echo "0"
    else
        echo "$value"
    fi
}

echo "${BLUE}RDS Metrics:${NC}"
echo "----------------------------------------"

# RDS CPU
RDS_CPU=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBInstanceIdentifier,Value=$DB_INSTANCE_ID \
    --start-time $START_TIME \
    --end-time $END_TIME \
    --period 300 \
    --statistics Average \
    --region $REGION \
    --query 'Datapoints[-1].Average' \
    --output text 2>/dev/null)
printf "CPU Utilization:        %.2f%%\n" $(get_latest_metric "$RDS_CPU")

# RDS Connections
RDS_CONN=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBInstanceIdentifier,Value=$DB_INSTANCE_ID \
    --start-time $START_TIME \
    --end-time $END_TIME \
    --period 300 \
    --statistics Average \
    --region $REGION \
    --query 'Datapoints[-1].Average' \
    --output text 2>/dev/null)
printf "Database Connections:   %.0f\n" $(get_latest_metric "$RDS_CONN")

# RDS Read Latency
RDS_READ_LAT=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name ReadLatency \
    --dimensions Name=DBInstanceIdentifier,Value=$DB_INSTANCE_ID \
    --start-time $START_TIME \
    --end-time $END_TIME \
    --period 300 \
    --statistics Average \
    --region $REGION \
    --query 'Datapoints[-1].Average' \
    --output text 2>/dev/null)
RDS_READ_LAT_VAL=$(get_latest_metric "$RDS_READ_LAT")
printf "Read Latency:           %.4f sec (%.2f ms)\n" $RDS_READ_LAT_VAL $(echo "$RDS_READ_LAT_VAL * 1000" | bc)

# RDS Write Latency
RDS_WRITE_LAT=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name WriteLatency \
    --dimensions Name=DBInstanceIdentifier,Value=$DB_INSTANCE_ID \
    --start-time $START_TIME \
    --end-time $END_TIME \
    --period 300 \
    --statistics Average \
    --region $REGION \
    --query 'Datapoints[-1].Average' \
    --output text 2>/dev/null)
RDS_WRITE_LAT_VAL=$(get_latest_metric "$RDS_WRITE_LAT")
printf "Write Latency:          %.4f sec (%.2f ms)\n" $RDS_WRITE_LAT_VAL $(echo "$RDS_WRITE_LAT_VAL * 1000" | bc)

# RDS IOPS
RDS_READ_IOPS=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name ReadIOPS \
    --dimensions Name=DBInstanceIdentifier,Value=$DB_INSTANCE_ID \
    --start-time $START_TIME \
    --end-time $END_TIME \
    --period 300 \
    --statistics Average \
    --region $REGION \
    --query 'Datapoints[-1].Average' \
    --output text 2>/dev/null)
printf "Read IOPS:              %.2f\n" $(get_latest_metric "$RDS_READ_IOPS")

RDS_WRITE_IOPS=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name WriteIOPS \
    --dimensions Name=DBInstanceIdentifier,Value=$DB_INSTANCE_ID \
    --start-time $START_TIME \
    --end-time $END_TIME \
    --period 300 \
    --statistics Average \
    --region $REGION \
    --query 'Datapoints[-1].Average' \
    --output text 2>/dev/null)
printf "Write IOPS:             %.2f\n" $(get_latest_metric "$RDS_WRITE_IOPS")

echo ""
echo "${BLUE}ECS Metrics:${NC}"
echo "----------------------------------------"

# ECS CPU
ECS_CPU=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/ECS \
    --metric-name CPUUtilization \
    --dimensions Name=ServiceName,Value=$SERVICE_NAME Name=ClusterName,Value=$CLUSTER_NAME \
    --start-time $START_TIME \
    --end-time $END_TIME \
    --period 300 \
    --statistics Average \
    --region $REGION \
    --query 'Datapoints[-1].Average' \
    --output text 2>/dev/null)
printf "CPU Utilization:        %.2f%%\n" $(get_latest_metric "$ECS_CPU")

# ECS Memory
ECS_MEM=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/ECS \
    --metric-name MemoryUtilization \
    --dimensions Name=ServiceName,Value=$SERVICE_NAME Name=ClusterName,Value=$CLUSTER_NAME \
    --start-time $START_TIME \
    --end-time $END_TIME \
    --period 300 \
    --statistics Average \
    --region $REGION \
    --query 'Datapoints[-1].Average' \
    --output text 2>/dev/null)
printf "Memory Utilization:     %.2f%%\n" $(get_latest_metric "$ECS_MEM")

echo ""
echo "${BLUE}ALB Metrics:${NC}"
echo "----------------------------------------"

# Get ALB name from terraform
cd terraform
ALB_ARN=$(terraform output -raw alb_arn 2>/dev/null || echo "")
cd - > /dev/null

if [ -n "$ALB_ARN" ]; then
    ALB_NAME=$(echo $ALB_ARN | cut -d':' -f6 | cut -d'/' -f2-)
    
    # ALB Response Time
    ALB_RESPONSE=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/ApplicationELB \
        --metric-name TargetResponseTime \
        --dimensions Name=LoadBalancer,Value=$ALB_NAME \
        --start-time $START_TIME \
        --end-time $END_TIME \
        --period 300 \
        --statistics Average \
        --region $REGION \
        --query 'Datapoints[-1].Average' \
        --output text 2>/dev/null)
    ALB_RESPONSE_VAL=$(get_latest_metric "$ALB_RESPONSE")
    printf "Response Time (avg):    %.4f sec (%.2f ms)\n" $ALB_RESPONSE_VAL $(echo "$ALB_RESPONSE_VAL * 1000" | bc)
    
    # ALB Request Count
    ALB_REQUESTS=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/ApplicationELB \
        --metric-name RequestCount \
        --dimensions Name=LoadBalancer,Value=$ALB_NAME \
        --start-time $START_TIME \
        --end-time $END_TIME \
        --period 300 \
        --statistics Sum \
        --region $REGION \
        --query 'Datapoints[-1].Sum' \
        --output text 2>/dev/null)
    printf "Request Count (5min):   %.0f\n" $(get_latest_metric "$ALB_REQUESTS")
    
    # ALB 5XX Errors
    ALB_5XX=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/ApplicationELB \
        --metric-name HTTPCode_Target_5XX_Count \
        --dimensions Name=LoadBalancer,Value=$ALB_NAME \
        --start-time $START_TIME \
        --end-time $END_TIME \
        --period 300 \
        --statistics Sum \
        --region $REGION \
        --query 'Datapoints[-1].Sum' \
        --output text 2>/dev/null)
    printf "5XX Errors (5min):      %.0f\n" $(get_latest_metric "$ALB_5XX")
fi

echo ""
echo "============================================"
echo ""
echo "${YELLOW}To monitor continuously:${NC}"
echo "  watch -n 5 ./view_metrics.sh"
echo ""