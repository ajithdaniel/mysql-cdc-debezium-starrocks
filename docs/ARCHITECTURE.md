# Architecture Overview

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            CDC Pipeline Architecture                         │
└─────────────────────────────────────────────────────────────────────────────┘

    ┌──────────────┐
    │   MySQL 8.4  │
    │   (Source)   │
    │              │
    │ ┌──────────┐ │
    │ │  Binlog  │ │◄─── ROW format, GTID enabled
    │ └────┬─────┘ │
    └──────┼───────┘
           │
           │ Reads binlog
           ▼
    ┌──────────────┐
    │   Debezium   │
    │   Connect    │
    │     3.0      │
    │              │
    │ ┌──────────┐ │
    │ │  MySQL   │ │◄─── Connector plugin
    │ │Connector │ │
    │ └────┬─────┘ │
    └──────┼───────┘
           │
           │ Publishes CDC events
           ▼
    ┌──────────────┐     ┌──────────────┐
    │    Kafka     │◄────│  Zookeeper   │
    │    7.7.1     │     │    7.7.1     │
    │              │     │              │
    │ Topics:      │     │ Coordination │
    │ • orders     │     └──────────────┘
    │ • customers  │
    │ • schemas    │
    └──────┬───────┘
           │
           │ Consumes via Routine Load
           ▼
    ┌──────────────┐
    │  StarRocks   │
    │   (OLAP)     │
    │              │
    │ ┌──────────┐ │
    │ │ Primary  │ │◄─── Handles INSERT/UPDATE/DELETE
    │ │Key Tables│ │
    │ └──────────┘ │
    └──────────────┘
```

## Data Flow

### 1. Source (MySQL)

MySQL is configured with binary logging enabled:

```ini
[mysqld]
server-id = 1
log_bin = mysql-bin
binlog_format = ROW          # Captures actual row changes
binlog_row_image = FULL      # Include all columns
gtid_mode = ON               # Global Transaction IDs
enforce_gtid_consistency = ON
```

**Why these settings?**
- `ROW` format captures actual data changes (not SQL statements)
- `FULL` image includes all columns for complete change records
- `GTID` enables reliable replication tracking

### 2. CDC Capture (Debezium)

Debezium connects to MySQL as a replica and reads the binlog:

```
MySQL Binlog Event → Debezium → Kafka Message
```

**Key configurations:**
- `snapshot.mode: initial` - Takes initial snapshot, then streams changes
- `ExtractNewRecordState` transform - Flattens the CDC envelope

**Message format (with transform):**
```json
{
  "schema": {...},
  "payload": {
    "order_id": 1,
    "customer_name": "John Doe",
    "product": "Laptop",
    "amount": 1299.99,
    "status": "pending",
    "__deleted": false
  }
}
```

### 3. Message Queue (Kafka)

Kafka topics are auto-created by Debezium:

| Topic | Content |
|-------|---------|
| `mysql.testdb.orders` | Order table changes |
| `mysql.testdb.customers` | Customer table changes |
| `schemahistory.testdb` | DDL changes |
| `debezium_*` | Connector state |

**Retention:** Default 7 days (configurable)

### 4. Target (StarRocks)

StarRocks uses **Routine Load** to consume from Kafka:

```
Kafka Topic → Routine Load Job → Primary Key Table
```

**Primary Key tables** support:
- INSERT: New rows added
- UPDATE: Existing rows modified (same PK)
- DELETE: Rows marked as deleted (handled via `__deleted` field)

## Component Details

### MySQL Source Database

```
┌─────────────────────────────────┐
│         MySQL 8.4               │
├─────────────────────────────────┤
│ Database: testdb                │
│                                 │
│ Tables:                         │
│ ├── orders (order_id PK)        │
│ │   ├── customer_name           │
│ │   ├── product                 │
│ │   ├── amount                  │
│ │   ├── order_date              │
│ │   └── status                  │
│ │                               │
│ └── customers (customer_id PK)  │
│     ├── name                    │
│     ├── email                   │
│     └── created_at              │
│                                 │
│ Binlog: mysql-bin.000001        │
└─────────────────────────────────┘
```

### Debezium Connector

```
┌─────────────────────────────────┐
│      Debezium Connect 3.0       │
├─────────────────────────────────┤
│                                 │
│ Connector: mysql-connector      │
│ ├── Type: MySQL                 │
│ ├── Tasks: 1                    │
│ └── State: RUNNING              │
│                                 │
│ Transforms:                     │
│ └── ExtractNewRecordState       │
│     └── Flattens envelope       │
│                                 │
│ Storage:                        │
│ ├── Offsets: Kafka topic        │
│ └── Schema: Kafka topic         │
│                                 │
└─────────────────────────────────┘
```

### StarRocks Target

```
┌─────────────────────────────────┐
│      StarRocks (All-in-One)     │
├─────────────────────────────────┤
│                                 │
│ FE (Frontend):                  │
│ ├── Query parsing               │
│ ├── Query planning              │
│ └── Metadata management         │
│                                 │
│ BE (Backend):                   │
│ ├── Data storage                │
│ ├── Query execution             │
│ └── Routine Load execution      │
│                                 │
│ Routine Load Jobs:              │
│ ├── load_orders                 │
│ │   └── Topic: mysql.testdb.orders
│ └── load_customers              │
│     └── Topic: mysql.testdb.customers
│                                 │
└─────────────────────────────────┘
```

## Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Network: cdc-network               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │mysql-source │    │  zookeeper  │    │    kafka    │     │
│  │   :3306     │    │   :2181     │    │ :9092,:29092│     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│         │                  │                  │             │
│         │                  │                  │             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │  debezium   │    │  kafka-ui   │    │debezium-ui  │     │
│  │   :8083     │    │   :8080     │    │   :8084     │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│         │                                                   │
│         │                                                   │
│  ┌─────────────┐                                           │
│  │  starrocks  │                                           │
│  │:8030,:9030  │                                           │
│  └─────────────┘                                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘

External Ports:
├── 3307  → MySQL
├── 2181  → Zookeeper
├── 9092  → Kafka (internal)
├── 29092 → Kafka (external)
├── 8080  → Kafka UI
├── 8083  → Debezium REST API
├── 8084  → Debezium UI
├── 8030  → StarRocks HTTP
└── 9030  → StarRocks MySQL Protocol
```

## Latency Breakdown

Typical end-to-end latency for a single row change:

| Stage | Latency | Notes |
|-------|---------|-------|
| MySQL binlog write | ~1ms | Transaction commit |
| Debezium capture | ~10-50ms | Binlog polling interval |
| Kafka produce | ~5-10ms | Network + disk |
| Routine Load consume | ~1-10s | Batch interval |
| **Total** | **~1-15s** | Depends on configuration |

## Fault Tolerance

### Debezium
- Stores offsets in Kafka
- Automatic restart and resume
- Exactly-once semantics with transactions

### Kafka
- Configurable replication (set to 1 for dev)
- Log compaction for CDC topics
- Consumer group management

### StarRocks
- Routine Load checkpointing
- Automatic retry on failures
- Pause/Resume capability

## Scaling Considerations

### Horizontal Scaling

| Component | Scale Strategy |
|-----------|---------------|
| MySQL | Read replicas (Debezium reads from primary) |
| Kafka | Add brokers, increase partitions |
| Debezium | Multiple tasks per connector |
| StarRocks | Add BE nodes, increase buckets |

### Vertical Scaling

| Component | Resource | Impact |
|-----------|----------|--------|
| Kafka | Memory | Larger page cache |
| Debezium | CPU | Faster serialization |
| StarRocks | Memory/CPU | Query performance |
