#!/bin/bash

# Create StarRocks Tables

set -e

echo "========================================"
echo "Creating StarRocks Tables"
echo "========================================"

docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 <<'EOF'
-- Create database
CREATE DATABASE IF NOT EXISTS testdb;
USE testdb;

-- Create Primary Key table for orders (supports updates/deletes)
CREATE TABLE IF NOT EXISTS orders (
    order_id INT,
    customer_name VARCHAR(100),
    product VARCHAR(100),
    amount DECIMAL(10,2),
    order_date DATETIME,
    status VARCHAR(20)
)
PRIMARY KEY (order_id)
DISTRIBUTED BY HASH(order_id) BUCKETS 4
PROPERTIES (
    "replication_num" = "1",
    "enable_persistent_index" = "true"
);

-- Create Primary Key table for customers
CREATE TABLE IF NOT EXISTS customers (
    customer_id INT,
    name VARCHAR(100),
    email VARCHAR(100),
    created_at DATETIME
)
PRIMARY KEY (customer_id)
DISTRIBUTED BY HASH(customer_id) BUCKETS 4
PROPERTIES (
    "replication_num" = "1",
    "enable_persistent_index" = "true"
);

SHOW TABLES;
EOF

echo "========================================"
echo "StarRocks tables created!"
echo "========================================"
