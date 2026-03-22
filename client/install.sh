#!/bin/bash
# client/install.sh - FortressBackup client installer

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}"
echo "╔════════════════════════════════════════╗"
echo "║     FortressBackup Client Setup        ║"
echo "║     Simple setup in 2 minutes          ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

# Prompt for configuration
echo -e "${YELLOW}Backup server IP address:${NC}"
read SERVER_IP

echo -e "${YELLOW}Backup server SSH port (Enter for 22):${NC}"
read SSH_PORT
SSH_PORT=${SSH_PORT:-22}

echo -e "${YELLOW}Backup transfer port (Enter for 2222):${NC}"
read BACKUP_PORT
BACKUP_PORT=${BACKUP_PORT:-2222}

echo -e "${YELLOW}What to backup? (e.g., /etc /home /var/www):${NC}"
read SOURCES

echo -e "${YELLOW}Backup time (HH:MM, Enter for 02:00):${NC}"
read BACKUP_TIME
BACKUP_TIME=${BACKUP_TIME:-02:00}

echo ""
echo "Starting installation..."

# Generate SSH key if not exists
if [ ! -f /root/.ssh/id_ed25519_fortress ]; then
    sudo ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519_fortress -N "" -C "fortressbackup"
fi

# Display public key for copying
echo -e "${YELLOW}"
echo "════════════════════════════════════════════════════════════"
echo "Copy this key and add it to the backup server:"
echo "════════════════════════════════════════════════════════════"
sudo cat /root/.ssh/id_ed25519_fortress.pub
echo "════════════════════════════════════════════════════════════"
echo -e "${NC}"

echo -e "${YELLOW}"
echo "1. Log in to the backup server ($SERVER_IP)"
echo "2. Run this command:"
echo "   echo 'PASTE_KEY_HERE' | sudo tee -a /home/backupuser/.ssh/authorized_keys"
echo ""
echo "Press Enter after adding the key..."
read

# Test SSH connection
echo "Testing connection..."
if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes -p "$SSH_PORT" -i /root/.ssh/id_ed25519_fortress backupuser@"$SERVER_IP" "echo OK" 2>/dev/null; then
    echo -e "${GREEN}Connection successful${NC}"
else
    echo -e "${RED}Connection failed. Please verify the key on the backup server.${NC}"
    exit 1
fi

# Create log file
sudo touch /var/log/fortressbackup.log
sudo chmod 666 /var/log/fortressbackup.log

# Create backup script
sudo tee /usr/local/bin/fortress-backup > /dev/null << 'EOF'
#!/bin/bash
# FortressBackup - Automated backup script

CONFIG="/etc/fortressbackup-client.conf"
if [ ! -f "$CONFIG" ]; then
    echo "Configuration not found"
    exit 1
fi

source "$CONFIG"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

do_backup() {
    local sources=$1
    local backup_id=$2
    
    LOG_FILE="/var/log/fortressbackup.log"
    BACKUP_ID=$(date +%Y%m%d_%H%M%S)_${backup_id}
    TEMP_DIR=$(mktemp -d)
    
    log "========================================="
    log "Starting backup $backup_id: $BACKUP_ID"
    log "Sources: $sources"
    log "========================================="
    
    # Copy files
    for source in $sources; do
        source=$(echo "$source" | sed 's/"//g')
        if [ -e "$source" ]; then
            mkdir -p "$TEMP_DIR$(dirname "$source")"
            cp -r "$source" "$TEMP_DIR$source" 2>/dev/null
            log "  Copied: $source"
        else
            log "  Warning: $source not found, skipping"
        fi
    done
    
    # Check if any files were copied
    if [ -z "$(ls -A $TEMP_DIR)" ]; then
        log "No files to backup. Sources not found."
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Create archive
    cd "$TEMP_DIR"
    ARCHIVE_FILE="/tmp/backup_$BACKUP_ID.tar.gz"
    tar -czf "$ARCHIVE_FILE" . 2>/dev/null
    log "Archive created: $ARCHIVE_FILE ($(du -h $ARCHIVE_FILE | cut -f1))"
    
    # Generate checksum
    CHECKSUM=$(sha256sum "$ARCHIVE_FILE" | awk '{print $1}')
    log "Checksum: $CHECKSUM"
    
    # Send signal to backup server
    log "Sending signal to $SERVER_IP..."
    ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_ed25519_fortress -p "$SSH_PORT" backupuser@"$SERVER_IP" \
        "/usr/local/bin/backup-receiver signal backup_$BACKUP_ID $CHECKSUM" > /dev/null 2>&1 &
    
    # Wait for port to open
    sleep 3
    
    # Send backup file
    log "Sending backup to server..."
    if scp -o StrictHostKeyChecking=no -i /root/.ssh/id_ed25519_fortress -P "$SSH_PORT" \
        "$ARCHIVE_FILE" \
        backupuser@"$SERVER_IP":/backups/incoming/ 2>&1 | tee -a "$LOG_FILE"; then
        
        # Send checksum
        echo "$CHECKSUM" | ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_ed25519_fortress -p "$SSH_PORT" backupuser@"$SERVER_IP" \
            "cat > /backups/incoming/backup_$BACKUP_ID.sha256" 2>&1 | tee -a "$LOG_FILE"
        
        log "Backup $BACKUP_ID sent successfully"
        
        sleep 2
        
        # Request verification
        log "Requesting verification..."
        ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_ed25519_fortress -p "$SSH_PORT" backupuser@"$SERVER_IP" \
            "/usr/local/bin/backup-receiver verify backup_$BACKUP_ID" 2>&1 | tee -a "$LOG_FILE"
        
        log "Backup $backup_id completed"
    else
        log "ERROR: Failed to send archive"
        rm -rf "$TEMP_DIR" "$ARCHIVE_FILE"
        return 1
    fi
    
    # Cleanup
    rm -rf "$TEMP_DIR" "$ARCHIVE_FILE"
    log "Temporary files removed"
    return 0
}

# Run specific backup if --backup-id is provided
if [ "$1" = "--backup-id" ] && [ -n "$2" ]; then
    BACKUP_NUM=$2
    SOURCES_VAR="BACKUP_${BACKUP_NUM}_SOURCES"
    ENABLED_VAR="BACKUP_${BACKUP_NUM}_ENABLED"
    
    SOURCES=${!SOURCES_VAR}
    ENABLED=${!ENABLED_VAR}
    
    if [ "$ENABLED" = "true" ]; then
        do_backup "$SOURCES" "$BACKUP_NUM"
    else
        log "Backup $BACKUP_NUM is disabled, skipping"
    fi
else
    # Run all enabled backups
    log "Running all enabled backups"
    
    for i in {1..10}; do
        SOURCES_VAR="BACKUP_${i}_SOURCES"
        ENABLED_VAR="BACKUP_${i}_ENABLED"
        
        SOURCES=${!SOURCES_VAR}
        ENABLED=${!ENABLED_VAR}
        
        if [ -n "$SOURCES" ] && [ "$ENABLED" = "true" ]; then
            do_backup "$SOURCES" "$i"
            echo ""
        fi
    done
    
    # Legacy format support
    if [ -n "$SOURCES" ] && [ -z "$BACKUP_1_SOURCES" ]; then
        do_backup "$SOURCES" "1"
    fi
    
    log "All backups completed"
fi
EOF

sudo chmod +x /usr/local/bin/fortress-backup

# Save configuration
sudo tee /etc/fortressbackup-client.conf > /dev/null << EOF
SERVER_IP=$SERVER_IP
SSH_PORT=$SSH_PORT
BACKUP_PORT=$BACKUP_PORT
SOURCES="$SOURCES"
BACKUP_TIME=$BACKUP_TIME
EOF

# Configure cron
HOUR=$(echo $BACKUP_TIME | cut -d: -f1)
MINUTE=$(echo $BACKUP_TIME | cut -d: -f2)

# Remove old tasks
sudo crontab -l 2>/dev/null | grep -v fortress-backup | sudo crontab - 2>/dev/null || true

# Add new task
(echo "$MINUTE $HOUR * * * /usr/local/bin/fortress-backup >> /var/log/fortressbackup.log 2>&1") | sudo crontab -

if sudo crontab -l 2>/dev/null | grep -q "fortress-backup"; then
    echo -e "${GREEN}Cron job added: $MINUTE $HOUR * * *${NC}"
else
    echo -e "${RED}Failed to add cron job automatically${NC}"
    echo "Add manually:"
    echo "  sudo crontab -e"
    echo "  $MINUTE $HOUR * * * /usr/local/bin/fortress-backup >> /var/log/fortressbackup.log 2>&1"
fi

echo -e "${GREEN}"
echo "════════════════════════════════════════════════════════════"
echo "Installation completed"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Configuration: /etc/fortressbackup-client.conf"
echo "Logs: /var/log/fortressbackup.log"
echo "Backup schedule: $BACKUP_TIME daily"
echo ""
echo "Test backup:"
echo "  sudo /usr/local/bin/fortress-backup"
echo ""
echo "View logs:"
echo "  tail -f /var/log/fortressbackup.log"
echo ""
echo "Check cron:"
echo "  sudo crontab -l"
echo -e "${NC}"