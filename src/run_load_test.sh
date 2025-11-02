#!/bin/bash

# ============================================
# MySQL Shopping Cart Load Test
# CS6650 - Performance Testing
# ============================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "============================================"
echo "MySQL Shopping Cart Performance Test"
echo "============================================"
echo ""

# Check if server is running
if ! curl -s http://localhost:8080/health > /dev/null 2>&1; then
    echo "${RED}Error: Server is not running on localhost:8080${NC}"
    echo "Start the server first: go run main.go"
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
HOST="http://localhost:8080"
USERS=100
SPAWN_RATE=20
RUN_TIME="2m"

# Remove old results
rm -f mysql_test_results.json
rm -f performance_report.html
rm -f locust_report.html
rm -f locust_results*.csv

echo "Test Configuration:"
echo "  Host: $HOST"
echo "  Concurrent Users: $USERS"
echo "  Spawn Rate: $SPAWN_RATE users/sec"
echo "  Max Duration: $RUN_TIME"
echo "  Target Operations: 150 (50 create, 50 add items, 50 get cart)"
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
    --html=locust_report.html \
    --csv=locust_results \
    --headless \
    --stop-timeout=10

echo ""
echo "============================================"
echo "${GREEN}Test Complete!${NC}"
echo "============================================"
echo ""

# Check if results file was created
if [ -f "mysql_test_results.json" ]; then
    echo "${GREEN}✓ Results saved to: mysql_test_results.json${NC}"
    
    # Show operation counts
    if command -v jq &> /dev/null; then
        echo ""
        echo "Operation Summary:"
        echo "----------------------------------------"
        
        total=$(jq 'length' mysql_test_results.json)
        create_count=$(jq '[.[] | select(.operation == "create_cart")] | length' mysql_test_results.json)
        add_count=$(jq '[.[] | select(.operation == "add_items")] | length' mysql_test_results.json)
        get_count=$(jq '[.[] | select(.operation == "get_cart")] | length' mysql_test_results.json)
        
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
        
        get_avg=$(jq '[.[] | select(.operation == "get_cart") | .response_time] | add / length' mysql_test_results.json)
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
    python3 generate_report.py mysql_test_results.json performance_report.html
    
    echo ""
    echo "============================================"
    echo "${GREEN}Reports Generated!${NC}"
    echo "============================================"
    echo ""
    echo "Available Reports:"
    echo "  📊 performance_report.html - Interactive charts and tables"
    echo "  📋 mysql_test_results.json - Raw data for Week 6c comparison"
    echo "  📈 locust_report.html - Locust detailed report"
    echo ""
    echo "Open the report:"
    echo "  ${YELLOW}open performance_report.html${NC}"
    echo ""
    echo "${GREEN}✓ Save mysql_test_results.json for Week 6c comparison!${NC}"
    
else
    echo "${RED}✗ Results file not created!${NC}"
fi