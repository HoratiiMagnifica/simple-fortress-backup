#!/bin/bash
# client/backup.sh - Legacy backup script (deprecated, kept for compatibility)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

CONFIG_FILE="/etc/fortressbackup/client.yml"
LOG_FILE="/var/log/fortressbackup.log"

# Load configuration
BACKUP_SERVER=$(grep backup_server "$CONFIG_FILE" | awk '{print $2}')
BACKUP_PORT=$(grep backup_port "$CONFIG_FILE" | awk '{print $2}')
RETENTION_DAYS=$(grep retention_days "$CONFIG_FILE" | awk '{print $2}')
SOURCES=$(grep -A 100 sources "$CONFIG_FILE" | grep -E "^\s*-" | sed 's/^\s*- //')

# Generate unique backup ID
BACKUP_ID=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="backup_$BACKUP_ID"

log_info "Starting backup $BACKUP_ID"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Collect files for backup
log_info "Collecting files..."
for source in $SOURCES; do
    if [ -e "$source" ]; then
        rsync -av "$source" "$TEMP_DIR/" || {
            log_error "Failed to backup $source"
            exit 1
        }
    else
        log_warn "Source $source does not exist, skipping"
    fi
done

# Create archive
log_info "Creating archive..."
tar -czf "$TEMP_DIR/$BACKUP_NAME.tar.gz" -C "$TEMP_DIR" .

# Calculate checksum
CHECKSUM=$(sha256sum "$TEMP_DIR/$BACKUP_NAME.tar.gz" | awk '{print $1}')
echo "$CHECKSUM" > "$TEMP_DIR/$BACKUP_NAME.sha256"

# Send signal to backup server
log_info "Signaling backup server..."
SIGNAL_MSG="BACKUP_REQUEST|$BACKUP_NAME|$CHECKSUM"
echo "$SIGNAL_MSG" | ssh -i /root/.ssh/id_rsa_fortressbackup \
    -p "$BACKUP_PORT" \
    "$BACKUP_SERVER" \
    "/usr/local/bin/backup-receiver signal" || {
    log_error "Failed to signal backup server"
    exit 1
}

# Wait for port to open (max 30 seconds)
log_info "Waiting for backup server to open port..."
TIMEOUT=30
while [ $TIMEOUT -gt 0 ]; do
    if nc -z "$BACKUP_SERVER" 2222 2>/dev/null; then
        break
    fi
    sleep 1
    TIMEOUT=$((TIMEOUT - 1))
done

if [ $TIMEOUT -eq 0 ]; then
    log_error "Timeout waiting for backup server"
    exit 1
fi

# Send backup
log_info "Sending backup..."
rsync -avz -e "ssh -i /root/.ssh/id_rsa_fortressbackup -p 2222" \
    "$TEMP_DIR/$BACKUP_NAME.tar.gz" \
    "$BACKUP_SERVER:/var/backups/incoming/" || {
    log_error "Failed to send backup"
    exit 1
}

rsync -avz -e "ssh -i /root/.ssh/id_rsa_fortressbackup -p 2222" \
    "$TEMP_DIR/$BACKUP_NAME.sha256" \
    "$BACKUP_SERVER:/var/backups/incoming/" || {
    log_error "Failed to send checksum"
    exit 1
}

log_info "Backup completed successfully"