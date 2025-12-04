#!/bin/bash

# Create StarRocks Routine Load Jobs

set -e

echo "========================================"
echo "Creating StarRocks Routine Load Jobs"
echo "========================================"

docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 <<'EOF'
USE testdb;

-- Routine Load for orders
CREATE ROUTINE LOAD testdb.load_orders ON orders
COLUMNS(order_id, customer_name, product, amount, order_date, status)
PROPERTIES
(
    "desired_concurrent_number" = "1",
    "format" = "json",
    "jsonpaths" = "[\"$.order_id\",\"$.customer_name\",\"$.product\",\"$.amount\",\"$.order_date\",\"$.status\"]",
    "strip_outer_array" = "false"
)
FROM KAFKA
(
    "kafka_broker_list" = "kafka:9092",
    "kafka_topic" = "mysql.testdb.orders",
    "property.group.id" = "starrocks_orders_group",
    "property.kafka_default_offsets" = "OFFSET_BEGINNING"
);

-- Routine Load for customers
CREATE ROUTINE LOAD testdb.load_customers ON customers
COLUMNS(customer_id, name, email, created_at)
PROPERTIES
(
    "desired_concurrent_number" = "1",
    "format" = "json",
    "jsonpaths" = "[\"$.customer_id\",\"$.name\",\"$.email\",\"$.created_at\"]",
    "strip_outer_array" = "false"
)
FROM KAFKA
(
    "kafka_broker_list" = "kafka:9092",
    "kafka_topic" = "mysql.testdb.customers",
    "property.group.id" = "starrocks_customers_group",
    "property.kafka_default_offsets" = "OFFSET_BEGINNING"
);

-- Check routine load status
SHOW ROUTINE LOAD\G
EOF

echo "========================================"
echo "Routine Load jobs created!"
echo "========================================"
