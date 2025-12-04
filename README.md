# MySQL CDC Pipeline with Debezium and StarRocks

A complete Change Data Capture (CDC) pipeline that streams data changes from MySQL to StarRocks using Debezium and Kafka.

```
┌─────────────┐    ┌───────────┐    ┌─────────┐    ┌────────────────┐    ┌────────────┐
│   MySQL     │───▶│  Debezium │───▶│  Kafka  │───▶│  Routine Load  │───▶│  StarRocks │
│  (Source)   │    │ (CDC)     │    │         │    │                │    │  (Target)  │
└─────────────┘    └───────────┘    └─────────┘    └────────────────┘    └────────────┘
```

## Features

- **Real-time CDC**: Capture MySQL binlog changes in real-time
- **Exactly-once semantics**: Reliable data delivery with Kafka
- **Primary Key tables**: Support for INSERT, UPDATE, and DELETE operations
- **Web UIs**: Kafka UI, Debezium UI for monitoring
- **Benchmarking**: Built-in performance testing tools
- **Continuous ingestion**: Data generator for testing

## Prerequisites

- Docker & Docker Compose
- 8GB+ RAM recommended
- Ports available: 3307, 2181, 9092, 8080, 8083, 8084, 8030, 9030

## Quick Start

### Option A: Standard Setup (Pre-built Debezium Image)

```bash
git clone https://github.com/ajithdaniel/mysql-cdc-debezium-starrocks.git
cd mysql-cdc-debezium-starrocks

# Start all services
docker-compose up -d

# Wait for services to be healthy (~60 seconds)
docker-compose ps
```

### Option B: Custom JAR Setup (Latest Debezium JARs)

Use this option to run with the latest Debezium connector JARs from Maven Central:

```bash
# Download latest Debezium JARs (default: 3.0.2.Final)
./debezium/download-connectors.sh

# Or specify a version
DEBEZIUM_VERSION=3.0.2.Final ./debezium/download-connectors.sh

# Start with custom JARs
docker-compose -f docker-compose.custom-jars.yml up -d
```

### 2. Register Debezium Connector

```bash
./register-debezium.sh
```

Or manually:

```bash
curl -X POST -H "Content-Type: application/json" \
  http://localhost:8083/connectors/ \
  -d @debezium-connector.json
```

### 3. Create StarRocks Tables

```bash
./create-starrocks-tables.sh
```

### 4. Create Routine Load Jobs

```bash
./create-routine-load.sh
```

### 5. Verify the Pipeline

```bash
# Insert test data
docker exec mysql-source mysql -uroot -prootpass testdb -e \
  "INSERT INTO orders (customer_name, product, amount, status) VALUES ('Test User', 'Test Product', 99.99, 'pending');"

# Check StarRocks (wait a few seconds for CDC)
docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e \
  "SELECT * FROM testdb.orders ORDER BY order_id DESC LIMIT 5;"
```

## Architecture

### Components

| Component | Version | Port | Description |
|-----------|---------|------|-------------|
| MySQL | 8.4 | 3307 | Source database with binlog enabled |
| Zookeeper | 7.7.1 | 2181 | Kafka coordination |
| Kafka | 7.7.1 | 9092, 29092 | Message broker |
| Debezium | 3.0 | 8083 | CDC connector |
| StarRocks | Latest | 8030, 9030 | OLAP target database |
| Kafka UI | Latest | 8080 | Kafka monitoring |
| Debezium UI | 2.5 | 8084 | Connector management |

### Data Flow

1. **MySQL** writes to binlog (ROW format with GTID)
2. **Debezium** reads binlog and publishes to Kafka topics
3. **Kafka** stores CDC events in topics (`mysql.testdb.orders`, etc.)
4. **StarRocks Routine Load** consumes from Kafka
5. **StarRocks** applies changes to Primary Key tables

## Project Structure

```
.
├── docker-compose.yml              # Standard setup (pre-built Debezium)
├── docker-compose.custom-jars.yml  # Custom JAR setup (latest Debezium)
├── debezium-connector.json         # Debezium MySQL connector config
├── debezium/
│   ├── download-connectors.sh      # Download latest Debezium JARs
│   └── plugins/                    # Downloaded connector JARs
├── mysql/
│   ├── my.cnf                      # MySQL binlog configuration
│   └── init/
│       └── 01-init.sql             # Initial schema and data
├── setup.sh                        # Initial setup script
├── register-debezium.sh            # Register Debezium connector
├── create-starrocks-tables.sh      # Create StarRocks schema
├── create-routine-load.sh          # Create Kafka consumers
├── test-pipeline.sh                # Test CDC pipeline
├── benchmark.sh                    # Performance benchmarking
├── continuous-ingest.sh            # Continuous data generator
├── monitor.sh                      # Monitor pipeline status
└── cleanup.sh                      # Stop and cleanup
```

## Web UIs

| Service | URL | Description |
|---------|-----|-------------|
| Kafka UI | http://localhost:8080 | Monitor topics, messages, consumers |
| Debezium UI | http://localhost:8084 | Manage CDC connectors |
| StarRocks | http://localhost:8030 | StarRocks web console |

## Configuration

### MySQL Binlog Settings

```ini
# mysql/my.cnf
[mysqld]
server-id = 1
log_bin = mysql-bin
binlog_format = ROW
binlog_row_image = FULL
gtid_mode = ON
enforce_gtid_consistency = ON
```

### Debezium Connector

Key settings in `debezium-connector.json`:

```json
{
  "connector.class": "io.debezium.connector.mysql.MySqlConnector",
  "snapshot.mode": "initial",
  "transforms": "unwrap",
  "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
}
```

### StarRocks Routine Load

```sql
CREATE ROUTINE LOAD testdb.load_orders ON orders
PROPERTIES (
    "format" = "json",
    "jsonpaths" = "[\"$.payload.order_id\", ...]"
)
FROM KAFKA (
    "kafka_broker_list" = "kafka:9092",
    "kafka_topic" = "mysql.testdb.orders"
);
```

## Scripts

### Continuous Data Ingestion

```bash
# Default: 10 inserts/s, 5 updates/s, 1 delete/s
./continuous-ingest.sh

# High throughput
./continuous-ingest.sh -i 50 -u 20 -d 5

# Run for 60 seconds
./continuous-ingest.sh -t 60

# Batch mode
./continuous-ingest.sh -b -s 500
```

### Benchmarking

```bash
# Run all benchmarks
./benchmark.sh

# Specific tests
./benchmark.sh --insert 1000
./benchmark.sh --latency
./benchmark.sh --concurrent
```

### Monitoring

```bash
# Check pipeline status
./monitor.sh

# Check Debezium connector
curl -s localhost:8083/connectors/mysql-connector/status | jq

# Check Routine Load
docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e "SHOW ROUTINE LOAD\G"
```

## Troubleshooting

### Debezium Connector Failed

```bash
# Check connector status
curl -s localhost:8083/connectors/mysql-connector/status | jq

# Restart connector
curl -X POST localhost:8083/connectors/mysql-connector/restart

# Check logs
docker logs debezium-connect --tail 100
```

### StarRocks Routine Load Paused

```bash
# Check status
docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e \
  "SHOW ROUTINE LOAD FOR testdb.load_orders\G"

# Resume if paused
docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e \
  "RESUME ROUTINE LOAD FOR testdb.load_orders;"
```

### Data Not Syncing

1. Check Kafka topics have data:
   ```bash
   docker exec kafka kafka-console-consumer \
     --bootstrap-server localhost:9092 \
     --topic mysql.testdb.orders \
     --from-beginning --max-messages 5
   ```

2. Check StarRocks can connect to Kafka:
   ```bash
   docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e \
     "SHOW ROUTINE LOAD TASK WHERE JobName='load_orders'\G"
   ```

### Reset Pipeline

```bash
# Stop and remove all data
./cleanup.sh  # Choose 'y' to remove volumes

# Start fresh
docker-compose up -d
./register-debezium.sh
./create-starrocks-tables.sh
./create-routine-load.sh
```

## Performance Tuning

### Kafka

```yaml
# docker-compose.yml
environment:
  KAFKA_NUM_PARTITIONS: 4
  KAFKA_DEFAULT_REPLICATION_FACTOR: 1
```

### StarRocks Routine Load

```sql
CREATE ROUTINE LOAD ...
PROPERTIES (
    "desired_concurrent_number" = "3",
    "max_batch_rows" = "500000",
    "max_batch_interval" = "20"
)
```

### Debezium

```json
{
  "max.batch.size": "2048",
  "max.queue.size": "8192"
}
```

## Known Limitations

1. **DECIMAL columns**: Debezium encodes DECIMAL as base64. Add `"decimal.handling.mode": "string"` to connector config for string representation.

2. **Schema changes**: DDL changes require connector restart and may need manual intervention.

3. **Delete handling**: Deletes are captured but StarRocks Primary Key tables handle them as soft deletes internally.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

## References

- [Debezium Documentation](https://debezium.io/documentation/)
- [StarRocks Routine Load](https://docs.starrocks.io/docs/loading/RoutineLoad/)
- [Kafka Connect](https://kafka.apache.org/documentation/#connect)
