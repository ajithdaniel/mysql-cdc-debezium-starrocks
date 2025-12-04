# Troubleshooting Guide

## Common Issues

### 1. Debezium Connector Not Starting

**Symptoms:**
- Connector status shows `FAILED`
- No data in Kafka topics

**Diagnosis:**
```bash
# Check connector status
curl -s localhost:8083/connectors/mysql-connector/status | jq

# Check Debezium logs
docker logs debezium-connect --tail 200
```

**Common Causes:**

| Error | Cause | Solution |
|-------|-------|----------|
| `Access denied` | Wrong credentials | Check `database.user/password` in connector config |
| `Unknown database` | Database doesn't exist | Create database or update `database.include.list` |
| `binlog not enabled` | MySQL misconfigured | Enable binlog in `my.cnf` |
| `GTID mode not enabled` | GTID required | Set `gtid_mode=ON` in MySQL |

**Fix:**
```bash
# Restart connector
curl -X POST localhost:8083/connectors/mysql-connector/restart

# Or delete and recreate
curl -X DELETE localhost:8083/connectors/mysql-connector
curl -X POST -H "Content-Type: application/json" \
  localhost:8083/connectors/ -d @debezium-connector.json
```

---

### 2. StarRocks Routine Load Paused

**Symptoms:**
- Data stops syncing
- Routine Load state is `PAUSED`

**Diagnosis:**
```bash
docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e \
  "SHOW ROUTINE LOAD FOR testdb.load_orders\G"
```

**Common Causes:**

| State | Cause | Solution |
|-------|-------|----------|
| `PAUSED` | Too many errors | Fix data issues, then resume |
| `CANCELLED` | Manual cancellation | Recreate the job |
| `NEED_SCHEDULE` | No Kafka data | Check Kafka topic has messages |

**Fix:**
```bash
# Resume paused job
docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e \
  "RESUME ROUTINE LOAD FOR testdb.load_orders;"

# Check error details
docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e \
  "SHOW ROUTINE LOAD TASK WHERE JobName='load_orders'\G"
```

---

### 3. Data Mismatch Between MySQL and StarRocks

**Symptoms:**
- Row counts differ
- Missing or duplicate data

**Diagnosis:**
```bash
# Compare counts
echo "MySQL:" && docker exec mysql-source mysql -uroot -prootpass -N testdb \
  -e "SELECT COUNT(*) FROM orders;"
echo "StarRocks:" && docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -N \
  -e "SELECT COUNT(*) FROM testdb.orders;"
```

**Common Causes:**

1. **Routine Load not consuming all messages**
   - Check `Progress` in `SHOW ROUTINE LOAD`

2. **JSON parsing errors**
   - Check `jsonpaths` matches Debezium output

3. **Primary Key conflicts**
   - StarRocks deduplicates by PK

**Fix:**
```bash
# Check Kafka topic lag
docker exec kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --group starrocks_orders_group \
  --describe

# Reset Routine Load to beginning
docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e "
  STOP ROUTINE LOAD FOR testdb.load_orders;
  -- Recreate with OFFSET_BEGINNING
"
```

---

### 4. Kafka Connection Issues

**Symptoms:**
- Debezium can't publish
- StarRocks can't consume

**Diagnosis:**
```bash
# Test Kafka connectivity
docker exec kafka kafka-topics --list --bootstrap-server localhost:9092

# Check Kafka logs
docker logs kafka --tail 100
```

**Common Causes:**

| Error | Cause | Solution |
|-------|-------|----------|
| `Connection refused` | Kafka not ready | Wait for startup |
| `Unknown topic` | Topic doesn't exist | Check auto-create or create manually |
| `Network unreachable` | Docker network issue | Check container network |

**Fix:**
```bash
# Create topic manually
docker exec kafka kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic mysql.testdb.orders \
  --partitions 1

# Restart Kafka
docker-compose restart kafka
```

---

### 5. MySQL Binlog Issues

**Symptoms:**
- Debezium snapshot works but no changes captured
- `binlog position` errors

**Diagnosis:**
```bash
# Check binlog status
docker exec mysql-source mysql -uroot -prootpass -e "SHOW MASTER STATUS;"

# Check binlog files
docker exec mysql-source mysql -uroot -prootpass -e "SHOW BINARY LOGS;"
```

**Common Causes:**

1. **Binlog expired**
   - Increase `binlog_expire_logs_seconds`

2. **Server ID conflict**
   - Each replica needs unique `server-id`

**Fix:**
```bash
# Force new snapshot
curl -X DELETE localhost:8083/connectors/mysql-connector
# Update connector with snapshot.mode: always
curl -X POST -H "Content-Type: application/json" \
  localhost:8083/connectors/ -d '{
    ...
    "snapshot.mode": "always"
  }'
```

---

### 6. High Latency

**Symptoms:**
- Changes take too long to appear in StarRocks
- Backlog building up

**Diagnosis:**
```bash
# Check Routine Load stats
docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e \
  "SHOW ROUTINE LOAD\G" | grep -E "Progress|Statistic"

# Check Kafka consumer lag
docker exec kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --all-groups --describe
```

**Optimization:**

```sql
-- Increase Routine Load concurrency
ALTER ROUTINE LOAD FOR testdb.load_orders
PROPERTIES ("desired_concurrent_number" = "3");

-- Increase batch size
ALTER ROUTINE LOAD FOR testdb.load_orders
PROPERTIES ("max_batch_rows" = "500000");
```

---

### 7. Out of Memory

**Symptoms:**
- Containers crashing
- `OOMKilled` in docker logs

**Diagnosis:**
```bash
docker stats --no-stream
```

**Fix:**
```yaml
# docker-compose.yml - Add memory limits
services:
  kafka:
    deploy:
      resources:
        limits:
          memory: 2G
  starrocks:
    deploy:
      resources:
        limits:
          memory: 4G
```

---

## Diagnostic Commands

```bash
# Full system status
docker-compose ps
curl -s localhost:8083/connectors/mysql-connector/status | jq
docker exec -i starrocks mysql -uroot -h127.0.0.1 -P9030 -e "SHOW ROUTINE LOAD\G"

# Kafka inspection
docker exec kafka kafka-topics --list --bootstrap-server localhost:9092
docker exec kafka kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic mysql.testdb.orders --from-beginning --max-messages 5

# Logs
docker logs mysql-source --tail 50
docker logs debezium-connect --tail 50
docker logs kafka --tail 50
docker logs starrocks --tail 50
```

## Reset Everything

```bash
# Nuclear option - fresh start
docker-compose down -v
docker-compose up -d
sleep 60
./register-debezium.sh
./create-starrocks-tables.sh
./create-routine-load.sh
```
