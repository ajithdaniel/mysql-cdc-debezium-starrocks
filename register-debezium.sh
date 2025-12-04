#!/bin/bash

# Register Debezium MySQL Connector

set -e

echo "========================================"
echo "Registering Debezium MySQL Connector"
echo "========================================"

# Register the connector
echo "Registering connector..."
curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
  http://localhost:8083/connectors/ -d @debezium-connector.json

echo ""
echo "Waiting for connector to initialize (10 seconds)..."
sleep 10

# Check connector status
echo "Checking connector status..."
curl -s http://localhost:8083/connectors/mysql-connector/status | jq

echo "========================================"
echo "Debezium connector registered!"
echo "========================================"
