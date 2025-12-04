#!/bin/bash

# Test CDC Pipeline

set -e

echo "========================================"
echo "Testing CDC Pipeline"
echo "========================================"

# Insert data into MySQL
echo "Inserting test data into MySQL..."
docker exec -i mysql-source mysql -uroot -prootpass testdb -e "
INSERT INTO orders (customer_name, product, amount, status) VALUES
('Alice Brown', 'Monitor', 399.99, 'pending');"

echo "Updating data in MySQL..."
docker exec -i mysql-source mysql -uroot -prootpass testdb -e "
UPDATE orders SET status='shipped' WHERE order_id=1;"

echo "Deleting data from MySQL..."
docker exec -i mysql-source mysql -uroot -prootpass testdb -e "
DELETE FROM orders WHERE order_id=2;"

# Wait for CDC to propagate
echo "Waiting for CDC to propagate (10 seconds)..."
sleep 10

# Check Kafka topics
echo "Listing Kafka topics..."
docker exec -i kafka kafka-topics --list --bootstrap-server localhost:9092

# Verify data in StarRocks
echo "Verifying data in StarRocks..."
docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e "
USE testdb;
SELECT * FROM orders;
SELECT COUNT(*) as order_count FROM orders;
SELECT * FROM customers;
SELECT COUNT(*) as customer_count FROM customers;"

echo "========================================"
echo "Pipeline test complete!"
echo "========================================"
