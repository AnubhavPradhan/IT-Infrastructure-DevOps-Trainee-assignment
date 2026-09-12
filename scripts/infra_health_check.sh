#!/usr/bin/env bash

# infra_health_check.sh

set -uo pipefail

LOG_FILE="/var/log/infra_health.log"
DISK_THRESHOLD=85
APP_CONTAINER="flask-app"

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

# Create the log file if it does not exist
if [ ! -f "${LOG_FILE}" ]; then
    touch "${LOG_FILE}" 2>/dev/null || {
        echo "ERROR: Cannot write to ${LOG_FILE}. Run as root or fix permissions." >&2
        exit 1
    }
fi

# Log health-check output to both terminal and log file
exec > >(tee -a "${LOG_FILE}") 2>&1

echo
echo "=== Infra Health Check @ ${TIMESTAMP} ==="

# --- CPU usage (%) ---
CPU_USAGE=$(top -bn1 | awk '/Cpu\(s\)/ {print $2 + $4}')
echo "CPU Usage: ${CPU_USAGE}%"

# --- RAM usage (%) ---
RAM_USAGE=$(free | awk '/Mem:/ {printf "%.1f", $3/$2 * 100}')
echo "RAM Usage: ${RAM_USAGE}%"

# --- Root disk usage (%) ---
DISK_USAGE=$(df --output=pcent / | tail -1 | tr -dc '0-9')
echo "Root Disk Usage: ${DISK_USAGE}%"

# --- Docker daemon status ---
if systemctl is-active --quiet docker; then
    echo "Docker Daemon: running"
    DOCKER_RUNNING=true
else
    echo "Docker Daemon: NOT running"
    DOCKER_RUNNING=false
    echo "[WARNING] Docker daemon is not running."
fi

# --- Application container status ---
if [ "${DOCKER_RUNNING}" = true ]; then

    CONTAINER_STATE=$(docker inspect -f '{{.State.Status}}' \
        "${APP_CONTAINER}" 2>/dev/null || echo "not_found")

    echo "App Container (${APP_CONTAINER}): ${CONTAINER_STATE}"

    if [ "${CONTAINER_STATE}" != "running" ]; then
        echo "[WARNING] App container '${APP_CONTAINER}' is not running (state: ${CONTAINER_STATE})."
    fi
fi

# --- Disk threshold check ---
if [ "${DISK_USAGE}" -gt "${DISK_THRESHOLD}" ]; then
    echo "[WARNING] Root disk usage at ${DISK_USAGE}% (threshold: ${DISK_THRESHOLD}%)."
fi

echo "=== Check complete ==="
