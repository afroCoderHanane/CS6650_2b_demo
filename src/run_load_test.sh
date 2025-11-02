#!/bin/bash

# ============================================
# MySQL Shopping Cart Load Test
# CS6650 - Performance Testing
# ============================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================"
echo "MySQL Shopping Cart Performance Test"
echo "============================================"
echo ""

# Create results directory with timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS_DIR="results/test_${TIMESTAMP}"
mkdir -p "$RESULTS_DIR"

echo "${BLUE}Results will be saved to: $RESULTS_DIR${NC}"
echo ""

# Get ALB URL from deployment info or use localhost
if [ -f "../terraform/deployment_info.txt" ]; then
    HOST=$(grep "Application URL:" ../terraform/deployment_info.txt | awk '{print $3}')
    if [ -z "$HOST" ]; then
        HOST="http://localhost:8080"
    fi
else
    HOST="http://localhost:8080"
fi

echo "Target Host: ${BLUE}$HOST${NC}"
echo ""

# Check if server is running
echo "Checking server availability..."
if ! curl -s -f "$HOST/health" > /dev/null 2>&1; then
    echo "${RED}Error: Server is not responding at $HOST${NC}"
    echo ""
    echo "Options:"
    echo "  1. If testing locally: Start the server first (go run main.go)"
    echo "  2. If testing AWS: Check deployment with 'terraform output alb_url'"
    echo "  3. Wait 1-2 minutes for health checks to pass after deployment"
    exit 1
fi

echo "${GREEN}✓ Server is running${NC}"
echo ""

# Check if locust is installed
if ! command -v locust &> /dev/null; then
    echo "${YELLOW}Installing Locust...${NC}"
    pip3 install locust
fi

echo "${GREEN}✓ Locust is installed${NC}"
echo ""

# Configuration
USERS=100
SPAWN_RATE=20
RUN_TIME="2m"

echo "Test Configuration:"
echo "  Host: $HOST"
echo "  Concurrent Users: $USERS"
echo "  Spawn Rate: $SPAWN_RATE users/sec"
echo "  Max Duration: $RUN_TIME"
echo "  Target Operations: 150 (50 create, 50 add items, 50 get cart)"
echo "  Results Directory: $RESULTS_DIR"
echo ""
echo "${YELLOW}Starting load test...${NC}"
echo "============================================"
echo ""

# Run Locust
locust -f locustfile.py \
    --host=$HOST \
    --users=$USERS \
    --spawn-rate=$SPAWN_RATE \
    --run-time=$RUN_TIME \
    --html="$RESULTS_DIR/locust_report.html" \
    --csv="$RESULTS_DIR/locust_results" \
    --headless \
    --stop-timeout=10

echo ""
echo "============================================"
echo "${GREEN}Test Complete!${NC}"
echo "============================================"
echo ""

# Move results file if it was created in current directory
if [ -f "mysql_test_results.json" ]; then
    mv mysql_test_results.json "$RESULTS_DIR/"
fi

# Check if results file was created
if [ -f "$RESULTS_DIR/mysql_test_results.json" ]; then
    echo "${GREEN}✓ Results saved to: $RESULTS_DIR/mysql_test_results.json${NC}"
    
    # Show operation counts
    if command -v jq &> /dev/null; then
        echo ""
        echo "Operation Summary:"
        echo "----------------------------------------"
        
        total=$(jq 'length' "$RESULTS_DIR/mysql_test_results.json")
        create_count=$(jq '[.[] | select(.operation == "create_cart")] | length' "$RESULTS_DIR/mysql_test_results.json")
        add_count=$(jq '[.[] | select(.operation == "add_items")] | length' "$RESULTS_DIR/mysql_test_results.json")
        get_count=$(jq '[.[] | select(.operation == "get_cart")] | length' "$RESULTS_DIR/mysql_test_results.json")
        
        echo "  Total operations: $total"
        echo "  create_cart: $create_count / 50"
        echo "  add_items: $add_count / 50"
        echo "  get_cart: $get_count / 50"
        
        if [ $create_count -ge 50 ] && [ $add_count -ge 50 ] && [ $get_count -ge 50 ]; then
            echo ""
            echo "${GREEN}✓ All 150 operations completed successfully!${NC}"
        else
            echo ""
            echo "${YELLOW}⚠ Not all operations completed. Consider increasing run-time.${NC}"
        fi
        
        echo ""
        echo "Performance Metrics:"
        echo "----------------------------------------"
        
        get_avg=$(jq '[.[] | select(.operation == "get_cart") | .response_time] | add / length' "$RESULTS_DIR/mysql_test_results.json")
        printf "  GET cart average: %.2fms" $get_avg
        
        if (( $(echo "$get_avg < 50" | bc -l) )); then
            echo " ${GREEN}✓ Meets <50ms requirement${NC}"
        else
            echo " ${RED}✗ Exceeds 50ms requirement${NC}"
        fi
    fi
    
    # Generate HTML report with graphs
    echo ""
    echo "${YELLOW}Generating interactive HTML report...${NC}"
    python3 generate_report.py "$RESULTS_DIR/mysql_test_results.json" "$RESULTS_DIR/performance_report.html"
    
    # Create summary file
    cat > "$RESULTS_DIR/test_summary.txt" << EOF
MySQL Shopping Cart Performance Test
=====================================
Test Date: $(date)
Test Duration: $RUN_TIME
Concurrent Users: $USERS
Target Host: $HOST

Results:
--------
Total Operations: $total
- create_cart: $create_count / 50
- add_items: $add_count / 50
- get_cart: $get_count / 50

Performance:
-----------
GET cart average: ${get_avg}ms
Target: <50ms

Files Generated:
---------------
- mysql_test_results.json (for Week 6c comparison)
- performance_report.html (interactive charts)
- locust_report.html (detailed Locust report)
- locust_results_stats.csv (statistics)
- locust_results_failures.csv (failures log)
EOF
    
    echo ""
    echo "============================================"
    echo "${GREEN}Reports Generated!${NC}"
    echo "============================================"
    echo ""
    echo "Results Location: ${BLUE}$RESULTS_DIR${NC}"
    echo ""
    echo "Available Reports:"
    echo "  📊 performance_report.html - Interactive charts and tables"
    echo "  📋 mysql_test_results.json - Raw data for Week 6c comparison"
    echo "  📈 locust_report.html - Locust detailed report"
    echo "  📝 test_summary.txt - Test summary"
    echo "  📉 locust_results_stats.csv - Statistics CSV"
    echo ""
    echo "Open the report:"
    echo "  ${YELLOW}open $RESULTS_DIR/performance_report.html${NC}"
    echo ""
    echo "View all results:"
    echo "  ${YELLOW}ls -lh $RESULTS_DIR/${NC}"
    echo ""
    echo "${GREEN}✓ Save $RESULTS_DIR for Week 6c comparison!${NC}"
    echo ""
    
    # List all files in results directory
    echo "Files created:"
    echo "----------------------------------------"
    ls -lh "$RESULTS_DIR/"
    
else
    echo "${RED}✗ Results file not created!${NC}"
    echo "Check locust output above for errors."
fi

echo ""
echo "============================================"
echo "Test results saved to: ${BLUE}$RESULTS_DIR${NC}"
echo "============================================"