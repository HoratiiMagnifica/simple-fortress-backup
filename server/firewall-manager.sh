#!/bin/bash
# server/firewall-manager.sh - Firewall management

set -euo pipefail

COMMAND="$1"
PORT="$2"
DURATION="${3:-60}"  # duration in seconds

LOG_FILE="/var/log/fortressbackup/firewall.log"

log_fw() {
    echo "[$(date)] $*" >> "$LOG_FILE"
}

case $COMMAND in
    open)
        # Open port
        ufw allow "$PORT"/tcp comment "FortressBackup temp rule"
        log_fw "Opened port $PORT for $DURATION seconds"
        
        # Close port after specified time
        (
            sleep "$DURATION"
            ufw delete allow "$PORT"/tcp
            log_fw "Closed port $PORT after $DURATION seconds"
        ) &
        ;;
        
    close)
        # Close port immediately
        ufw delete allow "$PORT"/tcp 2>/dev/null || true
        log_fw "Closed port $PORT immediately"
        ;;
        
    *)
        echo "Usage: $0 {open|close} <port> [duration]"
        exit 1
        ;;
esac