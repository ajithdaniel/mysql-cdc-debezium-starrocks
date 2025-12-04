#!/bin/bash

# CDC Pipeline Setup Script

set -e

echo "========================================"
echo "Starting CDC Pipeline Setup"
echo "========================================"

# Start all services
echo "Starting Docker containers..."
docker-compose up -d

# Wait for services to be healthy
echo "Waiting for services to be healthy (90 seconds)..."
sleep 90

# Check services are running
echo "Checking service status..."
docker-compose ps

# Check StarRocks logs
echo "Checking StarRocks logs..."
docker logs starrocks 2>&1 | tail -20

echo "========================================"
echo "Setup complete! Next steps:"
echo "1. Run: ./register-debezium.sh"
echo "2. Run: ./create-starrocks-tables.sh"
echo "3. Run: ./create-routine-load.sh"
echo "========================================"
