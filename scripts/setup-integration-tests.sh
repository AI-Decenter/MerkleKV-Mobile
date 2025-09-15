#!/bin/bash

# MerkleKV Mobile Integration Test Environment Setup
# This script sets up the Docker-based test environment for integration testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🚀 Setting up MerkleKV Mobile Integration Test Environment"
echo "=========================================================="

# Check Docker availability
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed or not available"
    echo "Please install Docker and try again"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed or not available"
    echo "Please install Docker Compose and try again"
    exit 1
fi

# Navigate to project root
cd "$PROJECT_ROOT"

echo "📍 Working directory: $(pwd)"

# Check if docker-compose.test.yml exists
if [ ! -f "docker-compose.test.yml" ]; then
    echo "❌ docker-compose.test.yml not found"
    echo "Please ensure you're running this script from the project root"
    exit 1
fi

# Create necessary test directories
echo "📁 Creating test directories..."
mkdir -p test/mosquitto-tls
mkdir -p test/hivemq-config
mkdir -p test/hivemq-tls

# Check if TLS certificates exist, generate if needed
if [ ! -f "test/mosquitto-tls/ca.crt" ] || [ ! -f "test/mosquitto-tls/server.crt" ]; then
    echo "🔐 Generating TLS certificates for testing..."
    cd test/mosquitto-tls
    
    # Generate CA certificate
    openssl genrsa -out ca.key 2048
    openssl req -new -x509 -days 365 -key ca.key -out ca.crt \
        -subj "/C=US/ST=CA/L=Test/O=MerkleKV/OU=Testing/CN=Test-CA"
    
    # Generate server certificate
    openssl genrsa -out server.key 2048
    openssl req -new -key server.key -out server.csr \
        -subj "/C=US/ST=CA/L=Test/O=MerkleKV/OU=Testing/CN=localhost"
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
        -CAcreateserial -out server.crt -days 365
    rm server.csr
    
    # Generate client certificate
    openssl genrsa -out client.key 2048
    openssl req -new -key client.key -out client.csr \
        -subj "/C=US/ST=CA/L=Test/O=MerkleKV/OU=Testing/CN=client"
    openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key \
        -CAcreateserial -out client.crt -days 365
    rm client.csr
    
    # Set proper permissions
    chmod 600 *.key
    chmod 644 *.crt
    
    cd "$PROJECT_ROOT"
    echo "✅ TLS certificates generated"
else
    echo "✅ TLS certificates already exist"
fi

# Copy TLS certificates to HiveMQ directory
echo "📋 Copying TLS certificates for HiveMQ..."
cp test/mosquitto-tls/* test/hivemq-tls/

# Create HiveMQ keystore and truststore (simplified for testing)
if [ ! -f "test/hivemq-tls/keystore.jks" ]; then
    echo "🔑 Creating Java keystores for HiveMQ..."
    
    # Create PKCS12 keystore first
    openssl pkcs12 -export -in test/hivemq-tls/server.crt -inkey test/hivemq-tls/server.key \
        -out test/hivemq-tls/server.p12 -name "server" -passout pass:password123
    
    # Convert to JKS keystore
    keytool -importkeystore -srckeystore test/hivemq-tls/server.p12 -srcstoretype PKCS12 \
        -destkeystore test/hivemq-tls/keystore.jks -deststoretype JKS \
        -srcstorepass password123 -deststorepass password123 -noprompt 2>/dev/null || {
        echo "⚠️  Could not create JKS keystore (keytool not available). HiveMQ TLS may not work."
        # Create empty keystore file to prevent Docker errors
        touch test/hivemq-tls/keystore.jks
    }
    
    # Create truststore
    keytool -import -alias ca -file test/hivemq-tls/ca.crt \
        -keystore test/hivemq-tls/truststore.jks -storepass password123 -noprompt 2>/dev/null || {
        echo "⚠️  Could not create truststore (keytool not available). HiveMQ TLS may not work."
        # Create empty truststore file to prevent Docker errors
        touch test/hivemq-tls/truststore.jks
    }
    
    echo "✅ Java keystores created"
fi

# Check if password file exists
if [ ! -f "test/mosquitto-passwd" ]; then
    echo "🔐 Creating password file for authentication testing..."
    cat > test/mosquitto-passwd << EOF
admin:password123
tenant_a_user1:password123
tenant_a_user2:password123
tenant_b_user1:password123
tenant_b_user2:password123
readonly_user:password123
device_001:password123
device_002:password123
EOF
    echo "✅ Password file created"
fi

# Stop any existing containers
echo "🛑 Stopping any existing test containers..."
docker-compose -f docker-compose.test.yml down -v --remove-orphans 2>/dev/null || true

# Start the test environment
echo "🏁 Starting integration test environment..."
docker-compose -f docker-compose.test.yml up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to become healthy..."
max_wait=120
wait_time=0

while [ $wait_time -lt $max_wait ]; do
    mosquitto_health=$(docker-compose -f docker-compose.test.yml ps mosquitto --format json 2>/dev/null | \
                      grep -o '"Health":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    
    if [ "$mosquitto_health" = "healthy" ]; then
        echo "✅ Mosquitto is healthy"
        break
    elif [ "$mosquitto_health" = "unhealthy" ]; then
        echo "❌ Mosquitto is unhealthy. Check logs:"
        docker-compose -f docker-compose.test.yml logs mosquitto
        exit 1
    else
        echo "⏳ Waiting for Mosquitto to be healthy... (${wait_time}s/${max_wait}s)"
        sleep 5
        wait_time=$((wait_time + 5))
    fi
done

if [ $wait_time -ge $max_wait ]; then
    echo "❌ Timeout waiting for services to become healthy"
    echo "Container status:"
    docker-compose -f docker-compose.test.yml ps
    echo "Mosquitto logs:"
    docker-compose -f docker-compose.test.yml logs mosquitto
    exit 1
fi

# Test broker connectivity
echo "🔍 Testing broker connectivity..."

# Test Mosquitto
if mosquitto_sub -h localhost -p 1883 -t '$SYS/broker/uptime' -C 1 --timeout 5 >/dev/null 2>&1; then
    echo "✅ Mosquitto (port 1883) is reachable"
else
    echo "❌ Mosquitto (port 1883) is not reachable"
fi

# Test Mosquitto TLS
if mosquitto_sub -h localhost -p 8883 -t '$SYS/broker/uptime' -C 1 --timeout 5 \
    --cafile test/mosquitto-tls/ca.crt --insecure >/dev/null 2>&1; then
    echo "✅ Mosquitto TLS (port 8883) is reachable"
else
    echo "⚠️  Mosquitto TLS (port 8883) may not be reachable (certificates might need adjustment)"
fi

# Test HiveMQ
if mosquitto_sub -h localhost -p 1884 -t '$SYS/broker/uptime' -C 1 --timeout 5 >/dev/null 2>&1; then
    echo "✅ HiveMQ (port 1884) is reachable"
else
    echo "⚠️  HiveMQ (port 1884) may not be reachable yet (still starting up)"
fi

echo ""
echo "🎉 Integration test environment is ready!"
echo ""
echo "Available brokers:"
echo "  • Mosquitto:     localhost:1883 (MQTT)"
echo "  • Mosquitto TLS: localhost:8883 (MQTT over TLS)"
echo "  • HiveMQ:        localhost:1884 (MQTT)"
echo "  • HiveMQ TLS:    localhost:8884 (MQTT over TLS)"
echo ""
echo "To run integration tests:"
echo "  cd packages/merkle_kv_core"
echo "  dart test test/integration/ --reporter=expanded"
echo ""
echo "To stop the environment:"
echo "  docker-compose -f docker-compose.test.yml down"
echo ""
echo "To view logs:"
echo "  docker-compose -f docker-compose.test.yml logs -f"