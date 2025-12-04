# Manual Setup Guide

Step-by-step instructions to set up the MySQL CDC pipeline with Debezium and StarRocks.

## Prerequisites

- Docker & Docker Compose installed
- 8GB+ RAM available
- Terminal/Command line access

## Step 1: Start the Infrastructure

### 1.1 Start All Docker Containers

```bash
cd mysql-cdc-debezium-starrocks
docker-compose up -d
```

### 1.2 Verify Containers are Running

```bash
docker-compose ps
```

Expected output - all containers should show `Up`:
```
NAME               IMAGE                             STATUS
debezium-connect   quay.io/debezium/connect:3.0      Up
debezium-ui        debezium/debezium-ui:2.5          Up
kafka              confluentinc/cp-kafka:7.7.1       Up
kafka-ui           provectuslabs/kafka-ui:latest     Up
mysql-source       mysql:8.4                         Up
starrocks          starrocks/allin1-ubuntu:latest    Up (healthy)
zookeeper          confluentinc/cp-zookeeper:7.7.1   Up
```

### 1.3 Wait for Services to Initialize

Wait approximately 60 seconds for all services to be ready, especially StarRocks.

```bash
# Check StarRocks health
curl -s http://localhost:8030/api/health
```

---

## Step 2: Verify MySQL Setup

### 2.1 Connect to MySQL

```bash
docker exec -it mysql-source mysql -uroot -prootpass
```

### 2.2 Check Database and Tables

```sql
-- Show databases
SHOW DATABASES;

-- Use testdb
USE testdb;

-- Show tables
SHOW TABLES;

-- Verify sample data
SELECT * FROM orders;
SELECT * FROM customers;
```

### 2.3 Verify Binlog Configuration

```sql
-- Check binlog is enabled
SHOW VARIABLES LIKE 'log_bin';
-- Should show: ON

-- Check binlog format
SHOW VARIABLES LIKE 'binlog_format';
-- Should show: ROW

-- Check GTID mode
SHOW VARIABLES LIKE 'gtid_mode';
-- Should show: ON

-- Check current binlog position
SHOW MASTER STATUS;
```

### 2.4 Exit MySQL

```sql
EXIT;
```

---

## Step 3: Register Debezium Connector

### 3.1 Check Debezium Connect is Ready

```bash
curl -s http://localhost:8083/ | jq
```

Expected response:
```json
{
  "version": "3.0.0.Final",
  "commit": "...",
  "kafka_cluster_id": "..."
}
```

### 3.2 List Available Connector Plugins

```bash
curl -s http://localhost:8083/connector-plugins | jq '.[].class'
```

Should include: `io.debezium.connector.mysql.MySqlConnector`

### 3.3 Create MySQL Connector

```bash
curl -X POST -H "Content-Type: application/json" \
  http://localhost:8083/connectors/ \
  -d '{
    "name": "mysql-connector",
    "config": {
      "connector.class": "io.debezium.connector.mysql.MySqlConnector",
      "tasks.max": "1",
      "database.hostname": "mysql-source",
      "database.port": "3306",
      "database.user": "root",
      "database.password": "rootpass",
      "database.server.id": "184054",
      "database.include.list": "testdb",
      "table.include.list": "testdb.orders,testdb.customers",
      "topic.prefix": "mysql",
      "schema.history.internal.kafka.bootstrap.servers": "kafka:9092",
      "schema.history.internal.kafka.topic": "schemahistory.testdb",
      "include.schema.changes": "true",
      "snapshot.mode": "initial",
      "transforms": "unwrap",
      "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
      "transforms.unwrap.drop.tombstones": "false",
      "transforms.unwrap.delete.handling.mode": "rewrite"
    }
  }'
```

### 3.4 Verify Connector Status

```bash
curl -s http://localhost:8083/connectors/mysql-connector/status | jq
```

Expected response:
```json
{
  "name": "mysql-connector",
  "connector": {
    "state": "RUNNING",
    "worker_id": "..."
  },
  "tasks": [
    {
      "id": 0,
      "state": "RUNNING",
      "worker_id": "..."
    }
  ]
}
```

---

## Step 4: Verify Kafka Topics

### 4.1 List Kafka Topics

```bash
docker exec kafka kafka-topics --list --bootstrap-server localhost:9092
```

Expected topics:
```
mysql.testdb.orders
mysql.testdb.customers
schemahistory.testdb
debezium_configs
debezium_offsets
debezium_statuses
```

### 4.2 View Messages in Orders Topic

```bash
docker exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic mysql.testdb.orders \
  --from-beginning \
  --max-messages 3
```

You should see JSON messages with order data.

---

## Step 5: Setup StarRocks

### 5.1 Connect to StarRocks

```bash
docker exec -it starrocks mysql -uroot -h127.0.0.1 -P9030
```

### 5.2 Create Database

```sql
CREATE DATABASE IF NOT EXISTS testdb;
USE testdb;
```

### 5.3 Create Orders Table

```sql
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
```

### 5.4 Create Customers Table

```sql
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
```

### 5.5 Verify Tables Created

```sql
SHOW TABLES;
```

---

## Step 6: Create Routine Load Jobs

### 6.1 Create Routine Load for Orders

```sql
CREATE ROUTINE LOAD testdb.load_orders ON orders
COLUMNS(order_id, customer_name, product, amount, order_date, status)
PROPERTIES
(
    "desired_concurrent_number" = "1",
    "format" = "json",
    "jsonpaths" = "[\"$.payload.order_id\",\"$.payload.customer_name\",\"$.payload.product\",\"$.payload.amount\",\"$.payload.order_date\",\"$.payload.status\"]",
    "strip_outer_array" = "false"
)
FROM KAFKA
(
    "kafka_broker_list" = "kafka:9092",
    "kafka_topic" = "mysql.testdb.orders",
    "property.group.id" = "starrocks_orders_group",
    "property.kafka_default_offsets" = "OFFSET_BEGINNING"
);
```

### 6.2 Create Routine Load for Customers

```sql
CREATE ROUTINE LOAD testdb.load_customers ON customers
COLUMNS(customer_id, name, email, created_at)
PROPERTIES
(
    "desired_concurrent_number" = "1",
    "format" = "json",
    "jsonpaths" = "[\"$.payload.customer_id\",\"$.payload.name\",\"$.payload.email\",\"$.payload.created_at\"]",
    "strip_outer_array" = "false"
)
FROM KAFKA
(
    "kafka_broker_list" = "kafka:9092",
    "kafka_topic" = "mysql.testdb.customers",
    "property.group.id" = "starrocks_customers_group",
    "property.kafka_default_offsets" = "OFFSET_BEGINNING"
);
```

### 6.3 Verify Routine Load Jobs

```sql
SHOW ROUTINE LOAD\G
```

Both jobs should show `State: RUNNING`

### 6.4 Exit StarRocks

```sql
EXIT;
```

---

## Step 7: Verify CDC Pipeline

### 7.1 Wait for Initial Sync

Wait 10-15 seconds for the initial data to sync.

### 7.2 Check Data in StarRocks

```bash
docker exec -it starrocks mysql -uroot -h127.0.0.1 -P9030 -e "
USE testdb;
SELECT 'Orders:' AS table_name;
SELECT * FROM orders;
SELECT 'Customers:' AS table_name;
SELECT * FROM customers;
"
```

You should see the initial data from MySQL.

---

## Step 8: Test Real-time CDC

### 8.1 Insert New Data in MySQL

```bash
docker exec mysql-source mysql -uroot -prootpass testdb -e "
INSERT INTO orders (customer_name, product, amount, status)
VALUES ('New Customer', 'New Product', 199.99, 'pending');
"
```

### 8.2 Update Existing Data

```bash
docker exec mysql-source mysql -uroot -prootpass testdb -e "
UPDATE orders SET status='shipped' WHERE order_id=1;
"
```

### 8.3 Verify Changes in StarRocks

Wait 5-10 seconds, then check:

```bash
docker exec -it starrocks mysql -uroot -h127.0.0.1 -P9030 -e "
USE testdb;
SELECT * FROM orders ORDER BY order_id;
"
```

You should see:
- The new order with `customer_name = 'New Customer'`
- Order ID 1 with `status = 'shipped'`

---

## Step 9: Monitor the Pipeline

### 9.1 Check Debezium Connector Status

```bash
curl -s http://localhost:8083/connectors/mysql-connector/status | jq
```

### 9.2 Check Routine Load Status

```bash
docker exec -it starrocks mysql -uroot -h127.0.0.1 -P9030 -e "
SHOW ROUTINE LOAD FOR testdb.load_orders\G
"
```

### 9.3 Access Web UIs

| UI | URL |
|----|-----|
| Kafka UI | http://localhost:8080 |
| Debezium UI | http://localhost:8084 |
| StarRocks | http://localhost:8030 |

---

## Step 10: Cleanup (Optional)

### 10.1 Stop All Containers

```bash
docker-compose down
```

### 10.2 Remove All Data (Fresh Start)

```bash
docker-compose down -v
```

---

## Quick Reference Commands

### MySQL
```bash
# Connect
docker exec -it mysql-source mysql -uroot -prootpass testdb

# Execute query
docker exec mysql-source mysql -uroot -prootpass testdb -e "SELECT * FROM orders;"
```

### Debezium
```bash
# Connector status
curl -s localhost:8083/connectors/mysql-connector/status | jq

# Restart connector
curl -X POST localhost:8083/connectors/mysql-connector/restart

# Delete connector
curl -X DELETE localhost:8083/connectors/mysql-connector
```

### Kafka
```bash
# List topics
docker exec kafka kafka-topics --list --bootstrap-server localhost:9092

# Consume messages
docker exec kafka kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic mysql.testdb.orders --from-beginning --max-messages 5
```

### StarRocks
```bash
# Connect
docker exec -it starrocks mysql -uroot -h127.0.0.1 -P9030

# Execute query
docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e "SELECT * FROM testdb.orders;"

# Check Routine Load
docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e "SHOW ROUTINE LOAD\G"
```

---

## Troubleshooting

### Debezium Connector Failed
```bash
# Check logs
docker logs debezium-connect --tail 100

# Restart connector
curl -X POST localhost:8083/connectors/mysql-connector/restart
```

### Routine Load Paused
```bash
# Check status
docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e \
  "SHOW ROUTINE LOAD FOR testdb.load_orders\G"

# Resume
docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e \
  "RESUME ROUTINE LOAD FOR testdb.load_orders;"
```

### Data Not Syncing
1. Check Kafka has messages: `kafka-console-consumer`
2. Check Routine Load is RUNNING: `SHOW ROUTINE LOAD`
3. Check jsonpaths match the Kafka message format
