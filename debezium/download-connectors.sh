#!/bin/bash

# Download Latest Debezium Connector JARs
# This script downloads the latest Debezium MySQL connector and dependencies

set -e

# Configuration
DEBEZIUM_VERSION="${DEBEZIUM_VERSION:-3.0.2.Final}"
PLUGINS_DIR="$(dirname "$0")/plugins"
MYSQL_CONNECTOR_DIR="$PLUGINS_DIR/debezium-connector-mysql"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Debezium Connector Downloader${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Version: $DEBEZIUM_VERSION"
echo "Target:  $MYSQL_CONNECTOR_DIR"
echo ""

# Create directory
mkdir -p "$MYSQL_CONNECTOR_DIR"

# Download from Maven Central
MAVEN_BASE="https://repo1.maven.org/maven2/io/debezium"

echo "Downloading Debezium MySQL Connector $DEBEZIUM_VERSION..."

# Main connector JAR
curl -fSL -o "$MYSQL_CONNECTOR_DIR/debezium-connector-mysql-${DEBEZIUM_VERSION}.jar" \
  "${MAVEN_BASE}/debezium-connector-mysql/${DEBEZIUM_VERSION}/debezium-connector-mysql-${DEBEZIUM_VERSION}.jar"

# Core dependencies
echo "Downloading dependencies..."

curl -fSL -o "$MYSQL_CONNECTOR_DIR/debezium-core-${DEBEZIUM_VERSION}.jar" \
  "${MAVEN_BASE}/debezium-core/${DEBEZIUM_VERSION}/debezium-core-${DEBEZIUM_VERSION}.jar"

curl -fSL -o "$MYSQL_CONNECTOR_DIR/debezium-connector-binlog-${DEBEZIUM_VERSION}.jar" \
  "${MAVEN_BASE}/debezium-connector-binlog/${DEBEZIUM_VERSION}/debezium-connector-binlog-${DEBEZIUM_VERSION}.jar"

curl -fSL -o "$MYSQL_CONNECTOR_DIR/debezium-ddl-parser-${DEBEZIUM_VERSION}.jar" \
  "${MAVEN_BASE}/debezium-ddl-parser/${DEBEZIUM_VERSION}/debezium-ddl-parser-${DEBEZIUM_VERSION}.jar"

curl -fSL -o "$MYSQL_CONNECTOR_DIR/debezium-storage-kafka-${DEBEZIUM_VERSION}.jar" \
  "${MAVEN_BASE}/debezium-storage-kafka/${DEBEZIUM_VERSION}/debezium-storage-kafka-${DEBEZIUM_VERSION}.jar"

curl -fSL -o "$MYSQL_CONNECTOR_DIR/debezium-storage-file-${DEBEZIUM_VERSION}.jar" \
  "${MAVEN_BASE}/debezium-storage-file/${DEBEZIUM_VERSION}/debezium-storage-file-${DEBEZIUM_VERSION}.jar"

# MySQL dependencies
echo "Downloading MySQL dependencies..."

# mysql-binlog-connector-java
BINLOG_VERSION="0.29.2"
curl -fSL -o "$MYSQL_CONNECTOR_DIR/mysql-binlog-connector-java-${BINLOG_VERSION}.jar" \
  "https://repo1.maven.org/maven2/com/zendesk/mysql-binlog-connector-java/${BINLOG_VERSION}/mysql-binlog-connector-java-${BINLOG_VERSION}.jar"

# MySQL Connector/J
MYSQL_J_VERSION="8.3.0"
curl -fSL -o "$MYSQL_CONNECTOR_DIR/mysql-connector-j-${MYSQL_J_VERSION}.jar" \
  "https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${MYSQL_J_VERSION}/mysql-connector-j-${MYSQL_J_VERSION}.jar"

# Additional common dependencies
echo "Downloading additional dependencies..."

# ANTLR4 Runtime (for DDL parsing)
ANTLR_VERSION="4.13.1"
curl -fSL -o "$MYSQL_CONNECTOR_DIR/antlr4-runtime-${ANTLR_VERSION}.jar" \
  "https://repo1.maven.org/maven2/org/antlr/antlr4-runtime/${ANTLR_VERSION}/antlr4-runtime-${ANTLR_VERSION}.jar"

# Guava
GUAVA_VERSION="33.0.0-jre"
curl -fSL -o "$MYSQL_CONNECTOR_DIR/guava-${GUAVA_VERSION}.jar" \
  "https://repo1.maven.org/maven2/com/google/guava/guava/${GUAVA_VERSION}/guava-${GUAVA_VERSION}.jar"

# failsafe
FAILSAFE_VERSION="3.3.2"
curl -fSL -o "$MYSQL_CONNECTOR_DIR/failsafe-${FAILSAFE_VERSION}.jar" \
  "https://repo1.maven.org/maven2/dev/failsafe/failsafe/${FAILSAFE_VERSION}/failsafe-${FAILSAFE_VERSION}.jar"

echo ""
echo -e "${GREEN}Download complete!${NC}"
echo ""
echo "Downloaded JARs:"
ls -la "$MYSQL_CONNECTOR_DIR"
echo ""
echo "Total size: $(du -sh "$MYSQL_CONNECTOR_DIR" | cut -f1)"
echo ""
echo -e "${GREEN}To use these JARs, mount the plugins directory to Kafka Connect:${NC}"
echo "  volumes:"
echo "    - ./debezium/plugins:/kafka/connect"
