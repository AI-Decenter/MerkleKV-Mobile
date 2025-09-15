#!/usr/bin/env bash
# MQTT Broker Health Check Script
# Validates broker availability and basic MQTT functionality (pub/sub, QoS1).
# Usage:
#   ./mqtt_health_check.sh [HOST] [PORT] [TIMEOUT_SECONDS]
# Env overrides (take precedence over args):
#   MQTT_BROKER_HOST, MQTT_BROKER_PORT, MQTT_HEALTH_TIMEOUT

set -euo pipefail

# ----------------------------
# Configuration (env > args > defaults)
# ----------------------------
BROKER_HOST="${MQTT_BROKER_HOST:-${1:-localhost}}"
BROKER_PORT="${MQTT_BROKER_PORT:-${2:-1883}}"
TIMEOUT_SECONDS="${MQTT_HEALTH_TIMEOUT:-${3:-30}}"
RETRY_INTERVAL=2
MQTT_TIMEOUT=15  # Timeout for individual MQTT operations

# ----------------------------
# Pretty logging
# ----------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()     { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ----------------------------
# Prerequisites
# ----------------------------
check_prerequisites() {
  log_info "Checking prerequisites..."
  if ! command -v mosquitto_pub >/dev/null 2>&1 || ! command -v mosquitto_sub >/dev/null 2>&1; then
    log_err "mosquitto-clients are required (mosquitto_pub/mosquitto_sub not found)."
    log_info "Install on Debian/Ubuntu: sudo apt-get install -y mosquitto-clients"
    log_info "Install on RHEL/CentOS:   sudo yum install -y mosquitto"
    log_info "Install on macOS (brew):  brew install mosquitto"
    return 1
  fi

  if ! command -v timeout >/dev/null 2>&1; then
    log_err "'timeout' command is required (from coreutils)."
    return 1
  fi

  # nc is optional; we'll fall back to /dev/tcp if missing
  if ! command -v nc >/dev/null 2>&1; then
    log_warn "netcat (nc) not found; will use /dev/tcp fallback for port checks."
  fi

  log_ok "Prerequisites check passed."
}

# ----------------------------
# Wait for TCP port
# ----------------------------
wait_for_port() {
  log_info "Waiting for ${BROKER_HOST}:${BROKER_PORT} to accept TCP connections (up to ${TIMEOUT_SECONDS}s)..."
  local elapsed=0
  while [ "$elapsed" -lt "$TIMEOUT_SECONDS" ]; do
    if command -v nc >/dev/null 2>&1; then
      if nc -z "$BROKER_HOST" "$BROKER_PORT" 2>/dev/null; then
        log_ok "Port ${BROKER_PORT} is open."
        return 0
      fi
    else
      # /dev/tcp fallback
      if timeout 3 bash -c ">/dev/tcp/${BROKER_HOST}/${BROKER_PORT}" 2>/dev/null; then
        log_ok "Port ${BROKER_PORT} is open."
        return 0
      fi
    fi

    log_info "Port not open yet... (${elapsed}/${TIMEOUT_SECONDS}s)"
    sleep "$RETRY_INTERVAL"
    elapsed=$((elapsed + RETRY_INTERVAL))
  done

  log_err "Port ${BROKER_PORT} did not open within ${TIMEOUT_SECONDS}s."
  # Best-effort debug hints (ignore errors if tools absent)
  command -v netstat >/dev/null 2>&1 && netstat -ln 2>/dev/null | grep -E ":${BROKER_PORT}\b" || true
  command -v ss >/dev/null 2>&1 && ss -lnt 2>/dev/null | grep -E ":${BROKER_PORT}\b" || true
  return 1
}

# ----------------------------
# Basic MQTT pub/sub test (QoS 1)
# ----------------------------
test_mqtt_connection() {
  log_info "Testing MQTT publish/subscribe (QoS 1)..."
  local test_topic="health/check/$$/$(date +%s)"
  local test_message="health_check_$(date +%s)"
  local tmp_file="/tmp/mqtt_health_${$}.out"

  : > "$tmp_file"

  # Start subscriber with a timeout; capture exactly 1 message
  log_info "Starting subscriber on topic: ${test_topic}"
  timeout "${MQTT_TIMEOUT}s" mosquitto_sub \
    -h "$BROKER_HOST" -p "$BROKER_PORT" \
    -t "$test_topic" -q 1 -C 1 >"$tmp_file" 2>&1 &
  local sub_pid=$!

  # Give subscriber a moment to connect
  sleep 2

  if ! kill -0 "$sub_pid" 2>/dev/null; then
    log_err "Subscriber failed to start or connect."
    [ -f "$tmp_file" ] && { log_info "Subscriber output:"; sed -e 's/^/  /' "$tmp_file" || true; }
    rm -f "$tmp_file"
    return 1
  fi

  # Publish the test message
  log_info "Publishing test message..."
  if ! timeout "${MQTT_TIMEOUT}s" mosquitto_pub \
      -h "$BROKER_HOST" -p "$BROKER_PORT" \
      -t "$test_topic" -m "$test_message" -q 1; then
    log_err "Failed to publish MQTT message."
    kill "$sub_pid" 2>/dev/null || true
    rm -f "$tmp_file"
    return 1
  fi

  # Wait briefly for delivery (subscriber has its own timeout too)
  local waited=0
  while kill -0 "$sub_pid" 2>/dev/null && [ "$waited" -lt "$MQTT_TIMEOUT" ]; do
    if [ -s "$tmp_file" ]; then
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done

  # Ensure subscriber is done and collect output
  kill "$sub_pid" 2>/dev/null || true
  wait "$sub_pid" 2>/dev/null || true

  if [ -s "$tmp_file" ]; then
    # mosquitto_sub writes only the payload by default
    local received
    # shellcheck disable=SC2002
    received="$(cat "$tmp_file" | tr -d '\r\n')"
    rm -f "$tmp_file"
    if [ "$received" = "$test_message" ]; then
      log_ok "Publish/Subscribe test passed (message matched)."
      return 0
    else
      log_err "Message mismatch. Expected: '$test_message' Got: '$received'"
      return 1
    fi
  else
    log_err "Subscriber did not receive a message within timeout."
    [ -f "$tmp_file" ] && { log_info "Subscriber output:"; sed -e 's/^/  /' "$tmp_file" || true; rm -f "$tmp_file"; }
    return 1
  fi
}

# ----------------------------
# Optional: additional QoS1 delivery check (topic-only)
# ----------------------------
test_qos1_topic_delivery() {
  log_info "Testing QoS 1 delivery on a fresh topic..."
  local test_topic="health/qos1/$(date +%s)/$$"
  local received_file="/tmp/mqtt_qos1_${$}.out"
  rm -f "$received_file"

  timeout 10s mosquitto_sub -h "$BROKER_HOST" -p "$BROKER_PORT" \
    -t "$test_topic" -q 1 -C 1 >"$received_file" 2>/dev/null &
  local sub_pid=$!

  sleep 2

  if ! mosquitto_pub -h "$BROKER_HOST" -p "$BROKER_PORT" \
      -t "$test_topic" -m "qos1_probe_$(date +%s)" -q 1 2>/dev/null; then
    log_warn "QoS1 probe publish failed."
    kill "$sub_pid" 2>/dev/null || true
    rm -f "$received_file"
    return 1
  fi

  local tries=0
  while [ $tries -lt 10 ] && kill -0 "$sub_pid" 2>/dev/null; do
    [ -s "$received_file" ] && break
    sleep 0.5
    tries=$((tries + 1))
  done

  kill "$sub_pid" 2>/dev/null || true
  wait "$sub_pid" 2>/dev/null || true

  if [ -s "$received_file" ]; then
    log_ok "QoS1 topic delivery appears OK."
    rm -f "$received_file"
    return 0
  else
    log_warn "QoS1 topic delivery not confirmed."
    rm -f "$received_file"
    return 1
  fi
}

# ----------------------------
# Main
# ----------------------------
main() {
  log_info "Starting MQTT broker health check..."
  log_info "Target: ${BROKER_HOST}:${BROKER_PORT}"
  log_info "Timeout: ${TIMEOUT_SECONDS}s"

  check_prerequisites
  wait_for_port
  test_mqtt_connection

  # Optional: do not fail CI if this extra probe fails
  if ! test_qos1_topic_delivery; then
    log_warn "QoS1 topic probe failed (non-fatal)."
  fi

  log_ok "All required MQTT health checks passed. ✅"
}

main "$@"
