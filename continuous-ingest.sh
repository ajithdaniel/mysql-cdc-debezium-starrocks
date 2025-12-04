#!/bin/bash

# Continuous Data Ingestion Script
# Simulates realistic workload: inserts, updates, and deletes

set -e

# Configuration
MYSQL_HOST="localhost"
MYSQL_PORT="3307"
MYSQL_USER="root"
MYSQL_PASS="rootpass"
MYSQL_DB="testdb"

# Default parameters
INSERT_RATE=10        # Inserts per second
UPDATE_RATE=5         # Updates per second
DELETE_RATE=1         # Deletes per second
DURATION=0            # 0 = run forever
BATCH_MODE=false      # If true, insert in batches
BATCH_SIZE=100        # Batch size for batch mode

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
TOTAL_INSERTS=0
TOTAL_UPDATES=0
TOTAL_DELETES=0
START_TIME=$(date +%s)

# Products and statuses for realistic data
PRODUCTS=("Laptop" "Mouse" "Keyboard" "Monitor" "Headphones" "Webcam" "USB Hub" "SSD" "RAM" "GPU" "CPU" "Motherboard" "Power Supply" "Case" "Cooling Fan")
STATUSES=("pending" "processing" "shipped" "delivered" "cancelled")
FIRST_NAMES=("John" "Jane" "Bob" "Alice" "Charlie" "Diana" "Edward" "Fiona" "George" "Helen" "Ivan" "Julia" "Kevin" "Laura" "Michael" "Nancy" "Oscar" "Patricia" "Quinn" "Rachel")
LAST_NAMES=("Smith" "Johnson" "Williams" "Brown" "Jones" "Garcia" "Miller" "Davis" "Rodriguez" "Martinez" "Anderson" "Taylor" "Thomas" "Moore" "Jackson" "Martin" "Lee" "Thompson" "White" "Harris")

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Continuous data ingestion for CDC pipeline testing"
    echo ""
    echo "Options:"
    echo "  -i, --insert-rate N    Inserts per second (default: $INSERT_RATE)"
    echo "  -u, --update-rate N    Updates per second (default: $UPDATE_RATE)"
    echo "  -d, --delete-rate N    Deletes per second (default: $DELETE_RATE)"
    echo "  -t, --duration N       Run for N seconds (0 = forever, default: $DURATION)"
    echo "  -b, --batch            Enable batch mode for inserts"
    echo "  -s, --batch-size N     Batch size (default: $BATCH_SIZE)"
    echo "  --orders-only          Only generate orders (no customers)"
    echo "  --customers-only       Only generate customers (no orders)"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Default rates, run forever"
    echo "  $0 -i 50 -u 10 -d 2          # Higher throughput"
    echo "  $0 -t 60                     # Run for 60 seconds"
    echo "  $0 -b -s 500                 # Batch mode with 500 rows per batch"
    echo ""
}

mysql_exec() {
    docker exec mysql-source mysql -u$MYSQL_USER -p$MYSQL_PASS -N $MYSQL_DB -e "$1" 2>/dev/null
}

random_element() {
    local arr=("$@")
    echo "${arr[$RANDOM % ${#arr[@]}]}"
}

random_name() {
    echo "$(random_element "${FIRST_NAMES[@]}") $(random_element "${LAST_NAMES[@]}")"
}

random_email() {
    local name=$1
    local domain=$(random_element "gmail.com" "yahoo.com" "outlook.com" "company.com" "example.com")
    echo "${name// /.}.$RANDOM@$domain" | tr '[:upper:]' '[:lower:]'
}

random_product() {
    random_element "${PRODUCTS[@]}"
}

random_status() {
    random_element "${STATUSES[@]}"
}

random_amount() {
    echo "$((RANDOM % 2000 + 10)).$((RANDOM % 100))"
}

# Insert a new order
insert_order() {
    local customer_name=$(random_name)
    local product=$(random_product)
    local amount=$(random_amount)
    local status="pending"

    mysql_exec "INSERT INTO orders (customer_name, product, amount, status) VALUES ('$customer_name', '$product', $amount, '$status');"
    TOTAL_INSERTS=$((TOTAL_INSERTS + 1))
}

# Insert a new customer
insert_customer() {
    local name=$(random_name)
    local email=$(random_email "$name")

    mysql_exec "INSERT INTO customers (name, email) VALUES ('$name', '$email');"
    TOTAL_INSERTS=$((TOTAL_INSERTS + 1))
}

# Batch insert orders
batch_insert_orders() {
    local count=$1
    local sql="INSERT INTO orders (customer_name, product, amount, status) VALUES "

    for ((i=1; i<=count; i++)); do
        local customer_name=$(random_name)
        local product=$(random_product)
        local amount=$(random_amount)
        sql+="('$customer_name', '$product', $amount, 'pending')"
        if [ $i -lt $count ]; then
            sql+=","
        fi
    done

    mysql_exec "$sql;"
    TOTAL_INSERTS=$((TOTAL_INSERTS + count))
}

# Update random orders
update_order() {
    local new_status=$(random_status)
    local order_id=$(mysql_exec "SELECT order_id FROM orders ORDER BY RAND() LIMIT 1;" | tr -d '[:space:]')

    if [ -n "$order_id" ]; then
        mysql_exec "UPDATE orders SET status='$new_status' WHERE order_id=$order_id;"
        TOTAL_UPDATES=$((TOTAL_UPDATES + 1))
    fi
}

# Delete random old orders (simulate cleanup)
delete_order() {
    local order_id=$(mysql_exec "SELECT order_id FROM orders WHERE status IN ('delivered', 'cancelled') ORDER BY RAND() LIMIT 1;" | tr -d '[:space:]')

    if [ -n "$order_id" ]; then
        mysql_exec "DELETE FROM orders WHERE order_id=$order_id;"
        TOTAL_DELETES=$((TOTAL_DELETES + 1))
    fi
}

# Print statistics
print_stats() {
    local elapsed=$(($(date +%s) - START_TIME))
    local insert_rate=0
    local update_rate=0
    local delete_rate=0

    if [ $elapsed -gt 0 ]; then
        insert_rate=$(echo "scale=1; $TOTAL_INSERTS / $elapsed" | bc)
        update_rate=$(echo "scale=1; $TOTAL_UPDATES / $elapsed" | bc)
        delete_rate=$(echo "scale=1; $TOTAL_DELETES / $elapsed" | bc)
    fi

    local mysql_orders=$(mysql_exec "SELECT COUNT(*) FROM orders;" 2>/dev/null | tr -d '[:space:]')
    local mysql_customers=$(mysql_exec "SELECT COUNT(*) FROM customers;" 2>/dev/null | tr -d '[:space:]')

    echo -e "\r${CYAN}[${elapsed}s]${NC} Inserts: ${GREEN}$TOTAL_INSERTS${NC} ($insert_rate/s) | Updates: ${YELLOW}$TOTAL_UPDATES${NC} ($update_rate/s) | Deletes: ${RED}$TOTAL_DELETES${NC} ($delete_rate/s) | MySQL Orders: $mysql_orders | Customers: $mysql_customers    "
}

# Cleanup on exit
cleanup() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   Ingestion Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    local elapsed=$(($(date +%s) - START_TIME))
    echo -e "Duration:       ${elapsed}s"
    echo -e "Total Inserts:  ${GREEN}$TOTAL_INSERTS${NC}"
    echo -e "Total Updates:  ${YELLOW}$TOTAL_UPDATES${NC}"
    echo -e "Total Deletes:  ${RED}$TOTAL_DELETES${NC}"
    echo -e "Total Ops:      $((TOTAL_INSERTS + TOTAL_UPDATES + TOTAL_DELETES))"
    if [ $elapsed -gt 0 ]; then
        echo -e "Avg Ops/sec:    $(echo "scale=1; ($TOTAL_INSERTS + $TOTAL_UPDATES + $TOTAL_DELETES) / $elapsed" | bc)"
    fi
    echo -e "${BLUE}========================================${NC}"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Parse arguments
ORDERS_ONLY=false
CUSTOMERS_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--insert-rate)
            INSERT_RATE="$2"
            shift 2
            ;;
        -u|--update-rate)
            UPDATE_RATE="$2"
            shift 2
            ;;
        -d|--delete-rate)
            DELETE_RATE="$2"
            shift 2
            ;;
        -t|--duration)
            DURATION="$2"
            shift 2
            ;;
        -b|--batch)
            BATCH_MODE=true
            shift
            ;;
        -s|--batch-size)
            BATCH_SIZE="$2"
            shift 2
            ;;
        --orders-only)
            ORDERS_ONLY=true
            shift
            ;;
        --customers-only)
            CUSTOMERS_ONLY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Header
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Continuous Data Ingestion${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Insert Rate:  ${GREEN}$INSERT_RATE/s${NC}"
echo -e "Update Rate:  ${YELLOW}$UPDATE_RATE/s${NC}"
echo -e "Delete Rate:  ${RED}$DELETE_RATE/s${NC}"
echo -e "Duration:     $([ $DURATION -eq 0 ] && echo 'Forever (Ctrl+C to stop)' || echo "${DURATION}s")"
echo -e "Batch Mode:   $([ "$BATCH_MODE" = true ] && echo "Yes (size: $BATCH_SIZE)" || echo 'No')"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check MySQL connection
echo -n "Checking MySQL connection... "
if mysql_exec "SELECT 1;" > /dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    echo "Make sure MySQL container is running: docker-compose ps"
    exit 1
fi

echo "Starting ingestion..."
echo ""

# Calculate sleep intervals
INSERT_INTERVAL=$(echo "scale=6; 1 / $INSERT_RATE" | bc)
UPDATE_INTERVAL=$(echo "scale=6; 1 / $UPDATE_RATE" | bc)
DELETE_INTERVAL=$(echo "scale=6; 1 / $DELETE_RATE" | bc)

LAST_INSERT=0
LAST_UPDATE=0
LAST_DELETE=0
LAST_STATS=0

# Main loop
while true; do
    CURRENT_TIME=$(date +%s.%N)
    ELAPSED_TIME=$(echo "$CURRENT_TIME - $START_TIME" | bc)

    # Check duration
    if [ $DURATION -gt 0 ]; then
        if (( $(echo "$ELAPSED_TIME >= $DURATION" | bc -l) )); then
            cleanup
        fi
    fi

    # Batch mode
    if [ "$BATCH_MODE" = true ]; then
        batch_insert_orders $BATCH_SIZE
        print_stats
        sleep 1
        continue
    fi

    # Insert
    if (( $(echo "$CURRENT_TIME - $LAST_INSERT >= $INSERT_INTERVAL" | bc -l) )); then
        if [ "$CUSTOMERS_ONLY" = false ]; then
            insert_order &
        fi
        if [ "$ORDERS_ONLY" = false ] && [ $((RANDOM % 3)) -eq 0 ]; then
            insert_customer &
        fi
        LAST_INSERT=$CURRENT_TIME
    fi

    # Update
    if (( $(echo "$CURRENT_TIME - $LAST_UPDATE >= $UPDATE_INTERVAL" | bc -l) )); then
        update_order &
        LAST_UPDATE=$CURRENT_TIME
    fi

    # Delete
    if (( $(echo "$CURRENT_TIME - $LAST_DELETE >= $DELETE_INTERVAL" | bc -l) )); then
        delete_order &
        LAST_DELETE=$CURRENT_TIME
    fi

    # Print stats every second
    if (( $(echo "$CURRENT_TIME - $LAST_STATS >= 1" | bc -l) )); then
        print_stats
        LAST_STATS=$CURRENT_TIME
    fi

    # Small sleep to prevent CPU spinning
    sleep 0.05
done
