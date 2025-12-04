#!/bin/bash

# CDC Pipeline Benchmark Script
# Tests throughput, latency, and reliability of the MySQL -> Debezium -> Kafka -> StarRocks pipeline

set -e

# Configuration
MYSQL_HOST="localhost"
MYSQL_PORT="3307"
MYSQL_USER="root"
MYSQL_PASS="rootpass"
MYSQL_DB="testdb"

STARROCKS_HOST="127.0.0.1"
STARROCKS_PORT="9030"
STARROCKS_USER="root"
STARROCKS_DB="testdb"

# Benchmark parameters
BATCH_SIZES=(100 500 1000)
DEFAULT_BATCH_SIZE=1000
LATENCY_TEST_ROWS=10

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Results file
RESULTS_FILE="benchmark_results_$(date +%Y%m%d_%H%M%S).txt"

# Cross-platform millisecond timestamp function
get_timestamp_ms() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - use python for milliseconds
        python3 -c 'import time; print(int(time.time() * 1000))'
    else
        # Linux
        date +%s%3N
    fi
}

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗${NC} $1"
}

mysql_exec() {
    docker exec mysql-source mysql -u$MYSQL_USER -p$MYSQL_PASS -N $MYSQL_DB -e "$1" 2>/dev/null
}

starrocks_exec() {
    docker exec -i starrocks mysql -u$STARROCKS_USER -h$STARROCKS_HOST -P$STARROCKS_PORT -N -e "$1" 2>/dev/null
}

# Header
print_header() {
    echo "========================================"
    echo "   CDC Pipeline Benchmark Suite"
    echo "   MySQL -> Debezium -> Kafka -> StarRocks"
    echo "========================================"
    echo ""
    echo "Results will be saved to: $RESULTS_FILE"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check Docker containers
    if ! docker ps | grep -q mysql-source; then
        log_error "MySQL container not running"
        exit 1
    fi

    if ! docker ps | grep -q starrocks; then
        log_error "StarRocks container not running"
        exit 1
    fi

    if ! docker ps | grep -q debezium-connect; then
        log_error "Debezium container not running"
        exit 1
    fi

    # Check Debezium connector
    CONNECTOR_STATUS=$(curl -s http://localhost:8083/connectors/mysql-connector/status | jq -r '.connector.state' 2>/dev/null)
    if [ "$CONNECTOR_STATUS" != "RUNNING" ]; then
        log_error "Debezium connector not running (status: $CONNECTOR_STATUS)"
        exit 1
    fi

    log_success "All prerequisites met"
}

# Setup benchmark table
setup_benchmark_table() {
    log "Setting up benchmark table..."

    # Create benchmark table in MySQL
    docker exec mysql-source mysql -u$MYSQL_USER -p$MYSQL_PASS $MYSQL_DB -e "
    DROP TABLE IF EXISTS benchmark_orders;
    CREATE TABLE benchmark_orders (
        id INT PRIMARY KEY AUTO_INCREMENT,
        customer_name VARCHAR(100),
        product VARCHAR(100),
        amount DECIMAL(10,2),
        quantity INT,
        order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        status VARCHAR(20) DEFAULT 'pending',
        notes TEXT
    ) ENGINE=InnoDB;
    " 2>/dev/null

    # Wait for Debezium to pick up schema change
    sleep 5

    # Create corresponding table in StarRocks
    docker exec -i starrocks mysql -u$STARROCKS_USER -h$STARROCKS_HOST -P$STARROCKS_PORT -e "
    USE $STARROCKS_DB;
    DROP TABLE IF EXISTS benchmark_orders;
    CREATE TABLE benchmark_orders (
        id INT,
        customer_name VARCHAR(100),
        product VARCHAR(100),
        amount DECIMAL(10,2),
        quantity INT,
        order_date DATETIME,
        status VARCHAR(20),
        notes VARCHAR(65533)
    )
    PRIMARY KEY (id)
    DISTRIBUTED BY HASH(id) BUCKETS 4
    PROPERTIES (
        'replication_num' = '1',
        'enable_persistent_index' = 'true'
    );
    " 2>/dev/null

    # Create Routine Load for benchmark table
    docker exec -i starrocks mysql -u$STARROCKS_USER -h$STARROCKS_HOST -P$STARROCKS_PORT -e "
    USE $STARROCKS_DB;
    CREATE ROUTINE LOAD ${STARROCKS_DB}.load_benchmark ON benchmark_orders
    COLUMNS(id, customer_name, product, amount, quantity, order_date, status, notes)
    PROPERTIES
    (
        'desired_concurrent_number' = '1',
        'format' = 'json',
        'jsonpaths' = '[\"$.payload.id\",\"$.payload.customer_name\",\"$.payload.product\",\"$.payload.amount\",\"$.payload.quantity\",\"$.payload.order_date\",\"$.payload.status\",\"$.payload.notes\"]',
        'strip_outer_array' = 'false'
    )
    FROM KAFKA
    (
        'kafka_broker_list' = 'kafka:9092',
        'kafka_topic' = 'mysql.testdb.benchmark_orders',
        'property.group.id' = 'starrocks_benchmark_group',
        'property.kafka_default_offsets' = 'OFFSET_BEGINNING'
    );
    " 2>/dev/null || true

    log_success "Benchmark table created"
}

# Cleanup benchmark data
cleanup_benchmark_data() {
    log "Cleaning up previous benchmark data..."
    mysql_exec "TRUNCATE TABLE benchmark_orders;" 2>/dev/null || true
    sleep 2
}

# Generate random data
generate_insert_sql() {
    local count=$1
    local sql="INSERT INTO benchmark_orders (customer_name, product, amount, quantity, status, notes) VALUES "

    for ((i=1; i<=count; i++)); do
        local customer="Customer_$RANDOM"
        local product="Product_$((RANDOM % 100))"
        local amount="$((RANDOM % 10000)).$((RANDOM % 100))"
        local quantity="$((RANDOM % 100 + 1))"
        local status="pending"
        local notes="Benchmark test order $i"

        sql+="('$customer', '$product', $amount, $quantity, '$status', '$notes')"

        if [ $i -lt $count ]; then
            sql+=","
        fi
    done

    echo "$sql;"
}

# Test 1: Insert Throughput
test_insert_throughput() {
    local batch_size=$1
    log "Testing INSERT throughput with $batch_size rows..."

    cleanup_benchmark_data

    # Generate and execute insert
    local start_time=$(get_timestamp_ms)

    local sql=$(generate_insert_sql $batch_size)
    docker exec mysql-source mysql -u$MYSQL_USER -p$MYSQL_PASS $MYSQL_DB -e "$sql" 2>/dev/null

    local insert_time=$(get_timestamp_ms)
    local insert_duration=$((insert_time - start_time))

    # Wait for CDC propagation
    local max_wait=120  # seconds
    local wait_interval=2
    local elapsed=0
    local sr_count=0

    while [ $elapsed -lt $max_wait ]; do
        sr_count=$(starrocks_exec "SELECT COUNT(*) FROM $STARROCKS_DB.benchmark_orders;" 2>/dev/null | tr -d '[:space:]')
        if [ "$sr_count" == "$batch_size" ]; then
            break
        fi
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done

    local end_time=$(get_timestamp_ms)
    local total_duration=$((end_time - start_time))
    local cdc_latency=$((end_time - insert_time))

    # Calculate metrics
    local insert_rate=$(echo "scale=2; $batch_size / ($insert_duration / 1000)" | bc 2>/dev/null || echo "N/A")
    local total_rate=$(echo "scale=2; $batch_size / ($total_duration / 1000)" | bc 2>/dev/null || echo "N/A")

    echo ""
    echo "  Batch Size:        $batch_size rows"
    echo "  MySQL Insert Time: ${insert_duration}ms"
    echo "  CDC Latency:       ${cdc_latency}ms"
    echo "  Total Time:        ${total_duration}ms"
    echo "  Insert Rate:       ${insert_rate} rows/sec"
    echo "  End-to-End Rate:   ${total_rate} rows/sec"
    echo "  StarRocks Count:   $sr_count / $batch_size"

    if [ "$sr_count" == "$batch_size" ]; then
        log_success "All rows replicated successfully"
    else
        log_warn "Only $sr_count of $batch_size rows replicated"
    fi

    # Save to results
    echo "INSERT_THROUGHPUT,$batch_size,$insert_duration,$cdc_latency,$total_duration,$insert_rate,$total_rate,$sr_count" >> $RESULTS_FILE
}

# Test 2: Update Throughput
test_update_throughput() {
    local batch_size=$1
    log "Testing UPDATE throughput with $batch_size rows..."

    # Get initial count
    local initial_count=$(starrocks_exec "SELECT COUNT(*) FROM $STARROCKS_DB.benchmark_orders WHERE status='pending';" 2>/dev/null | tr -d '[:space:]')

    # Perform updates in MySQL
    local start_time=$(get_timestamp_ms)

    mysql_exec "UPDATE benchmark_orders SET status='processing', notes=CONCAT(notes, ' - Updated') WHERE status='pending' LIMIT $batch_size;"

    local update_time=$(get_timestamp_ms)
    local update_duration=$((update_time - start_time))

    # Wait for CDC propagation
    local max_wait=120
    local wait_interval=2
    local elapsed=0
    local updated_count=0

    while [ $elapsed -lt $max_wait ]; do
        updated_count=$(starrocks_exec "SELECT COUNT(*) FROM $STARROCKS_DB.benchmark_orders WHERE status='processing';" 2>/dev/null | tr -d '[:space:]')
        if [ "$updated_count" -ge "$batch_size" ] 2>/dev/null; then
            break
        fi
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done

    local end_time=$(get_timestamp_ms)
    local total_duration=$((end_time - start_time))
    local cdc_latency=$((end_time - update_time))

    local update_rate=$(echo "scale=2; $batch_size / ($update_duration / 1000)" | bc 2>/dev/null || echo "N/A")
    local total_rate=$(echo "scale=2; $batch_size / ($total_duration / 1000)" | bc 2>/dev/null || echo "N/A")

    echo ""
    echo "  Rows Updated:      $batch_size"
    echo "  MySQL Update Time: ${update_duration}ms"
    echo "  CDC Latency:       ${cdc_latency}ms"
    echo "  Total Time:        ${total_duration}ms"
    echo "  Update Rate:       ${update_rate} rows/sec"
    echo "  End-to-End Rate:   ${total_rate} rows/sec"

    log_success "Update test completed"

    echo "UPDATE_THROUGHPUT,$batch_size,$update_duration,$cdc_latency,$total_duration,$update_rate,$total_rate,$updated_count" >> $RESULTS_FILE
}

# Test 3: Single Row Latency
test_single_row_latency() {
    log "Testing single row CDC latency ($LATENCY_TEST_ROWS iterations)..."

    local total_latency=0
    local min_latency=999999
    local max_latency=0
    local latencies=()

    for ((i=1; i<=LATENCY_TEST_ROWS; i++)); do
        # Insert single row
        local start_time=$(get_timestamp_ms)

        mysql_exec "INSERT INTO benchmark_orders (customer_name, product, amount, quantity, status) VALUES ('LatencyTest_$i', 'TestProduct', 99.99, 1, 'latency_test_$i');"

        # Wait for it to appear in StarRocks
        local max_wait=30
        local elapsed=0
        while [ $elapsed -lt $max_wait ]; do
            local count=$(starrocks_exec "SELECT COUNT(*) FROM $STARROCKS_DB.benchmark_orders WHERE status='latency_test_$i';" 2>/dev/null | tr -d '[:space:]')
            if [ "$count" == "1" ]; then
                break
            fi
            sleep 0.5
            elapsed=$((elapsed + 1))
        done

        local end_time=$(get_timestamp_ms)
        local latency=$((end_time - start_time))

        latencies+=($latency)
        total_latency=$((total_latency + latency))

        if [ $latency -lt $min_latency ]; then
            min_latency=$latency
        fi
        if [ $latency -gt $max_latency ]; then
            max_latency=$latency
        fi

        echo "    Iteration $i: ${latency}ms"
    done

    local avg_latency=$((total_latency / LATENCY_TEST_ROWS))

    # Calculate P95 (simple approximation)
    IFS=$'\n' sorted=($(sort -n <<<"${latencies[*]}")); unset IFS
    local p95_index=$(( (LATENCY_TEST_ROWS * 95) / 100 ))
    local p95_latency=${sorted[$p95_index]:-$max_latency}

    echo ""
    echo "  Iterations:    $LATENCY_TEST_ROWS"
    echo "  Min Latency:   ${min_latency}ms"
    echo "  Max Latency:   ${max_latency}ms"
    echo "  Avg Latency:   ${avg_latency}ms"
    echo "  P95 Latency:   ${p95_latency}ms"

    log_success "Latency test completed"

    echo "SINGLE_ROW_LATENCY,$LATENCY_TEST_ROWS,$min_latency,$max_latency,$avg_latency,$p95_latency" >> $RESULTS_FILE
}

# Test 4: Delete Propagation
test_delete_propagation() {
    local delete_count=100
    log "Testing DELETE propagation with $delete_count rows..."

    # Get current count
    local initial_mysql=$(mysql_exec "SELECT COUNT(*) FROM benchmark_orders;" | tr -d '[:space:]')
    local initial_sr=$(starrocks_exec "SELECT COUNT(*) FROM $STARROCKS_DB.benchmark_orders;" 2>/dev/null | tr -d '[:space:]')

    echo "  Initial MySQL count:     $initial_mysql"
    echo "  Initial StarRocks count: $initial_sr"

    # Delete rows
    local start_time=$(get_timestamp_ms)

    mysql_exec "DELETE FROM benchmark_orders ORDER BY id LIMIT $delete_count;"

    local delete_time=$(get_timestamp_ms)
    local delete_duration=$((delete_time - start_time))

    # Wait for propagation
    sleep 15

    local final_sr=$(starrocks_exec "SELECT COUNT(*) FROM $STARROCKS_DB.benchmark_orders;" 2>/dev/null | tr -d '[:space:]')
    local end_time=$(get_timestamp_ms)
    local total_duration=$((end_time - start_time))

    echo "  Delete Time:             ${delete_duration}ms"
    echo "  Total Time:              ${total_duration}ms"
    echo "  Final StarRocks count:   $final_sr"

    log_success "Delete test completed"

    echo "DELETE_PROPAGATION,$delete_count,$delete_duration,$total_duration,$initial_sr,$final_sr" >> $RESULTS_FILE
}

# Test 5: Concurrent Load Test
test_concurrent_load() {
    log "Testing concurrent insert/update/select load..."

    local duration=30  # seconds
    local insert_count=0
    local update_count=0
    local select_count=0

    cleanup_benchmark_data

    # Pre-populate with some data
    local sql=$(generate_insert_sql 500)
    docker exec mysql-source mysql -u$MYSQL_USER -p$MYSQL_PASS $MYSQL_DB -e "$sql" 2>/dev/null
    sleep 10

    local start_time=$(date +%s)
    local end_time=$((start_time + duration))

    echo "  Running concurrent operations for ${duration}s..."

    while [ $(date +%s) -lt $end_time ]; do
        # Insert
        mysql_exec "INSERT INTO benchmark_orders (customer_name, product, amount, quantity) VALUES ('Concurrent_$RANDOM', 'Product_$RANDOM', $((RANDOM % 1000)), $((RANDOM % 10)));" &
        insert_count=$((insert_count + 1))

        # Update
        mysql_exec "UPDATE benchmark_orders SET status='updated' WHERE id = (SELECT id FROM (SELECT id FROM benchmark_orders WHERE status='pending' LIMIT 1) as t);" 2>/dev/null &
        update_count=$((update_count + 1))

        # Select from StarRocks
        starrocks_exec "SELECT COUNT(*) FROM $STARROCKS_DB.benchmark_orders;" > /dev/null 2>&1 &
        select_count=$((select_count + 1))

        sleep 0.1
    done

    wait

    # Final counts
    sleep 10
    local mysql_count=$(mysql_exec "SELECT COUNT(*) FROM benchmark_orders;" | tr -d '[:space:]')
    local sr_count=$(starrocks_exec "SELECT COUNT(*) FROM $STARROCKS_DB.benchmark_orders;" 2>/dev/null | tr -d '[:space:]')

    echo ""
    echo "  Duration:          ${duration}s"
    echo "  Inserts:           $insert_count"
    echo "  Updates:           $update_count"
    echo "  Selects:           $select_count"
    echo "  MySQL Count:       $mysql_count"
    echo "  StarRocks Count:   $sr_count"
    echo "  Ops/sec:           $(( (insert_count + update_count + select_count) / duration ))"

    log_success "Concurrent load test completed"

    echo "CONCURRENT_LOAD,$duration,$insert_count,$update_count,$select_count,$mysql_count,$sr_count" >> $RESULTS_FILE
}

# Generate summary report
generate_report() {
    echo ""
    echo "========================================"
    echo "   Benchmark Summary Report"
    echo "========================================"
    echo ""
    echo "Results saved to: $RESULTS_FILE"
    echo ""
    echo "Test Results:"
    echo "-------------"
    cat $RESULTS_FILE
    echo ""

    # Create markdown report
    local md_report="benchmark_report_$(date +%Y%m%d_%H%M%S).md"

    cat > $md_report << 'REPORT_HEADER'
# CDC Pipeline Benchmark Report

## Test Environment
- **Source**: MySQL 8.0
- **CDC**: Debezium 2.5
- **Message Queue**: Kafka (Confluent 7.5.0)
- **Target**: StarRocks 3.2

## Test Results

REPORT_HEADER

    echo "### Insert Throughput" >> $md_report
    echo "| Batch Size | Insert Time (ms) | CDC Latency (ms) | Total Time (ms) | Insert Rate (rows/s) | E2E Rate (rows/s) |" >> $md_report
    echo "|------------|------------------|------------------|-----------------|----------------------|-------------------|" >> $md_report
    grep "INSERT_THROUGHPUT" $RESULTS_FILE | while IFS=',' read -r type batch insert_time cdc_lat total_time insert_rate e2e_rate count; do
        echo "| $batch | $insert_time | $cdc_lat | $total_time | $insert_rate | $e2e_rate |" >> $md_report
    done

    echo "" >> $md_report
    echo "### Single Row Latency" >> $md_report
    grep "SINGLE_ROW_LATENCY" $RESULTS_FILE | while IFS=',' read -r type iters min max avg p95; do
        echo "- **Iterations**: $iters" >> $md_report
        echo "- **Min Latency**: ${min}ms" >> $md_report
        echo "- **Max Latency**: ${max}ms" >> $md_report
        echo "- **Avg Latency**: ${avg}ms" >> $md_report
        echo "- **P95 Latency**: ${p95}ms" >> $md_report
    done

    echo "" >> $md_report
    echo "---" >> $md_report
    echo "*Report generated on $(date)*" >> $md_report

    log_success "Markdown report saved to: $md_report"
}

# Cleanup
cleanup() {
    log "Cleaning up..."

    # Stop routine load
    docker exec -i starrocks mysql -u$STARROCKS_USER -h$STARROCKS_HOST -P$STARROCKS_PORT -e "
    STOP ROUTINE LOAD FOR ${STARROCKS_DB}.load_benchmark;
    " 2>/dev/null || true

    log_success "Cleanup completed"
}

# Main execution
main() {
    print_header

    # Initialize results file
    echo "TEST_TYPE,PARAM1,PARAM2,PARAM3,PARAM4,PARAM5,PARAM6,PARAM7" > $RESULTS_FILE

    check_prerequisites
    setup_benchmark_table

    echo ""
    echo "========================================"
    echo "   Running Benchmarks"
    echo "========================================"

    # Test 1: Insert Throughput with different batch sizes
    echo ""
    echo "--- Test 1: Insert Throughput ---"
    for batch in "${BATCH_SIZES[@]}"; do
        test_insert_throughput $batch
        echo ""
    done

    # Test 2: Single Row Latency
    echo ""
    echo "--- Test 2: Single Row Latency ---"
    test_single_row_latency

    # Test 3: Update Throughput
    echo ""
    echo "--- Test 3: Update Throughput ---"
    cleanup_benchmark_data
    local sql=$(generate_insert_sql 1000)
    docker exec mysql-source mysql -u$MYSQL_USER -p$MYSQL_PASS $MYSQL_DB -e "$sql" 2>/dev/null
    sleep 15
    test_update_throughput 500

    # Test 4: Delete Propagation
    echo ""
    echo "--- Test 4: Delete Propagation ---"
    test_delete_propagation

    # Test 5: Concurrent Load
    echo ""
    echo "--- Test 5: Concurrent Load ---"
    test_concurrent_load

    # Generate report
    generate_report

    # Cleanup
    cleanup

    echo ""
    echo "========================================"
    echo "   Benchmark Complete!"
    echo "========================================"
}

# Parse arguments
case "${1:-}" in
    --insert)
        check_prerequisites
        setup_benchmark_table
        test_insert_throughput ${2:-$DEFAULT_BATCH_SIZE}
        ;;
    --latency)
        check_prerequisites
        setup_benchmark_table
        test_single_row_latency
        ;;
    --update)
        check_prerequisites
        test_update_throughput ${2:-500}
        ;;
    --concurrent)
        check_prerequisites
        setup_benchmark_table
        test_concurrent_load
        ;;
    --cleanup)
        cleanup
        ;;
    --help)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --insert [count]   Run insert throughput test only"
        echo "  --latency          Run single row latency test only"
        echo "  --update [count]   Run update throughput test only"
        echo "  --concurrent       Run concurrent load test only"
        echo "  --cleanup          Clean up benchmark tables"
        echo "  --help             Show this help message"
        echo ""
        echo "Without options, runs all benchmarks."
        ;;
    *)
        main
        ;;
esac
