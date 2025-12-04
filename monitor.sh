#!/bin/bash

# Monitor CDC Pipeline

echo "========================================"
echo "CDC Pipeline Monitoring"
echo "========================================"

echo ""
echo "--- Debezium Connector Status ---"
curl -s http://localhost:8083/connectors/mysql-connector/status | jq

echo ""
echo "--- Routine Load Jobs ---"
docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e "
SHOW ROUTINE LOAD\G"

echo ""
echo "--- Routine Load Tasks (Orders) ---"
docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e "
SHOW ROUTINE LOAD TASK WHERE JobName='load_orders'\G"

echo ""
echo "--- Kafka Topics ---"
docker exec -i kafka kafka-topics --list --bootstrap-server localhost:9092

echo ""
echo "========================================"
echo "Kafka UI available at: http://localhost:8080"
echo "StarRocks FE HTTP: http://localhost:8030"
echo "========================================"
