#!/bin/bash
# server/backup-receiver.sh - Backup receiver script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

STORAGE_DIR="/var/backups"
BACKUP_PORT="2222"
FIREWALL_MANAGER="/usr/local/bin/firewall-manager"

# Check arguments
if [ $# -lt 1 ]; then
    log_error "Usage: $0 {signal|verify}"
    exit 1
fi

case $1 in
    signal)
        # Read signal
        read SIGNAL_MSG
        IFS='|' read -r COMMAND BACKUP_NAME CHECKSUM <<< "$SIGNAL_MSG"
        
        if [ "$COMMAND" != "BACKUP_REQUEST" ]; then
            log_error "Invalid signal received"
            exit 1
        fi
        
        log_info "Received backup request for $BACKUP_NAME"
        
        # Open port for limited time
        sudo "$FIREWALL_MANAGER" open "$BACKUP_PORT" 300
        log_info "Opened port $BACKUP_PORT for 5 minutes"
        
        # Save backup information
        echo "$BACKUP_NAME|$CHECKSUM|$(date +%s)" > "$STORAGE_DIR/incoming/$BACKUP_NAME.info"
        ;;
        
    verify)
        # Verify after receiving
        if [ $# -lt 2 ]; then
            log_error "Usage: $0 verify <backup_name>"
            exit 1
        fi
        
        BACKUP_NAME="$2"
        
        # Check checksum
        if [ -f "$STORAGE_DIR/incoming/$BACKUP_NAME.tar.gz" ] && \
           [ -f "$STORAGE_DIR/incoming/$BACKUP_NAME.sha256" ]; then
            EXPECTED=$(cat "$STORAGE_DIR/incoming/$BACKUP_NAME.sha256")
            ACTUAL=$(sha256sum "$STORAGE_DIR/incoming/$BACKUP_NAME.tar.gz" | awk '{print $1}')
            
            if [ "$EXPECTED" = "$ACTUAL" ]; then
                log_info "Backup integrity verified: $BACKUP_NAME"
                # Move to archive
                mv "$STORAGE_DIR/incoming/$BACKUP_NAME.tar.gz" "$STORAGE_DIR/archive/"
                rm -f "$STORAGE_DIR/incoming/$BACKUP_NAME.sha256"
                rm -f "$STORAGE_DIR/incoming/$BACKUP_NAME.info"
            else
                log_error "Integrity check failed for $BACKUP_NAME"
                exit 1
            fi
        fi
        ;;
        
    *)
        log_error "Unknown command: $1"
        exit 1
        ;;
esac