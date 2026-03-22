#!/bin/bash
# server/install.sh - FortressBackup server installer

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}"
echo "╔════════════════════════════════════════╗"
echo "║     FortressBackup Server Setup        ║"
echo "║     Simple setup in 2 minutes          ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

# Check and install required packages
echo "Checking required packages..."

install_package() {
    if ! command -v "$1" &> /dev/null; then
        echo "Installing $1..."
        apt-get update -qq
        apt-get install -y -qq "$1"
    fi
}

install_package rsync
install_package openssh-server
install_package iptables
install_package iptables-persistent
install_package sudo

# Prompt for IP address
echo -e "${YELLOW}Enter this server's IP address (visible to clients):${NC}"
read SERVER_IP

# Prompt for SSH port
echo -e "${YELLOW}SSH port (Enter for 22):${NC}"
read SSH_PORT
SSH_PORT=${SSH_PORT:-22}

# Prompt for backup port
echo -e "${YELLOW}Backup transfer port (Enter for 2222):${NC}"
read BACKUP_PORT
BACKUP_PORT=${BACKUP_PORT:-2222}

echo ""
echo "Starting installation..."

# Create backup user
sudo useradd -m -s /bin/bash backupuser 2>/dev/null || true
echo "User backupuser created"

# Add user to sudo group
sudo usermod -aG sudo backupuser
echo "User added to sudo group"

# Create directories
sudo mkdir -p /backups/{incoming,archive}
sudo chown -R backupuser:backupuser /backups
sudo chmod 755 /backups
echo "Directories created at /backups"

# Configure SSH
sudo mkdir -p /home/backupuser/.ssh
sudo touch /home/backupuser/.ssh/authorized_keys
sudo chmod 700 /home/backupuser/.ssh
sudo chmod 600 /home/backupuser/.ssh/authorized_keys
sudo chown -R backupuser:backupuser /home/backupuser/.ssh
echo "SSH directory configured"

# Configure additional SSH port if needed
if [ "$SSH_PORT" != "22" ]; then
    if ! grep -q "Port $SSH_PORT" /etc/ssh/sshd_config; then
        echo "Port $SSH_PORT" | sudo tee -a /etc/ssh/sshd_config
        sudo systemctl restart sshd
        echo "SSH port $SSH_PORT added"
    fi
fi

# Configure sudo rights for backupuser
sudo tee /etc/sudoers.d/backupuser > /dev/null << EOF
# FortressBackup privileges - no password required
backupuser ALL=(ALL) NOPASSWD: ALL
EOF
sudo chmod 440 /etc/sudoers.d/backupuser
echo "SUDO privileges configured"

# Create log file
sudo touch /var/log/fortressbackup.log
sudo chmod 666 /var/log/fortressbackup.log

# Create backup receiver script
sudo tee /usr/local/bin/backup-receiver > /dev/null << EOF
#!/bin/bash
# FortressBackup - Backup receiver

ACTION=\$1
BACKUP_NAME=\$2
CHECKSUM=\$3
BACKUP_PORT=$BACKUP_PORT
LOG_FILE="/var/log/fortressbackup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

case \$ACTION in
    signal)
        log "========================================="
        log "Received signal for \$BACKUP_NAME"
        log "Checksum: \$CHECKSUM"
        
        # Open port for 5 minutes
        iptables -A INPUT -p tcp --dport \$BACKUP_PORT -j ACCEPT 2>/dev/null
        log "Port \$BACKUP_PORT opened for 5 minutes"
        
        # Close after 5 minutes
        (sleep 300 && iptables -D INPUT -p tcp --dport \$BACKUP_PORT -j ACCEPT 2>/dev/null && log "Port \$BACKUP_PORT closed") &
        
        # Save information
        echo "\$BACKUP_NAME|\$CHECKSUM|\$(date)" > /backups/incoming/\$BACKUP_NAME.info
        log "Information saved to /backups/incoming/\$BACKUP_NAME.info"
        log "Ready to receive backup"
        ;;
        
    verify)
        log "Verifying integrity for \$BACKUP_NAME"
        
        if [ -f "/backups/incoming/\$BACKUP_NAME.tar.gz" ] && \
           [ -f "/backups/incoming/\$BACKUP_NAME.sha256" ]; then
            
            EXPECTED=\$(cat "/backups/incoming/\$BACKUP_NAME.sha256")
            ACTUAL=\$(sha256sum "/backups/incoming/\$BACKUP_NAME.tar.gz" | awk '{print \$1}')
            
            if [ "\$EXPECTED" = "\$ACTUAL" ]; then
                log "Integrity verified: \$ACTUAL"
                
                # Move to archive
                mv "/backups/incoming/\$BACKUP_NAME.tar.gz" "/backups/archive/"
                mv "/backups/incoming/\$BACKUP_NAME.sha256" "/backups/archive/"
                mv "/backups/incoming/\$BACKUP_NAME.info" "/backups/archive/"
                log "Backup moved to archive"
                log "Backup successfully received and verified"
            else
                log "ERROR: Checksum mismatch"
                log "  Expected: \$EXPECTED"
                log "  Received: \$ACTUAL"
                log "Backup will NOT be saved"
                exit 1
            fi
        else
            log "Backup files not found in /backups/incoming/"
            ls -la /backups/incoming/ 2>/dev/null >> "\$LOG_FILE"
            exit 1
        fi
        log "========================================="
        ;;
        
    *)
        log "Unknown command: \$ACTION"
        echo "Usage: \$0 {signal|verify} <backup_name> [checksum]"
        exit 1
        ;;
esac
EOF

sudo chmod +x /usr/local/bin/backup-receiver
echo "Backup receiver script installed"

# Configure iptables
echo "Configuring iptables..."

# Add rule for SSH port if not exists
if ! sudo iptables -C INPUT -p tcp --dport $SSH_PORT -j ACCEPT 2>/dev/null; then
    sudo iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
    echo "Rule for port $SSH_PORT added"
fi

# Save iptables rules
if command -v netfilter-persistent &> /dev/null; then
    sudo netfilter-persistent save
    echo "iptables rules saved (netfilter-persistent)"
elif command -v iptables-save &> /dev/null; then
    sudo mkdir -p /etc/iptables
    sudo iptables-save > /etc/iptables/rules.v4
    echo "iptables rules saved to /etc/iptables/rules.v4"
fi

# Save configuration
echo "SERVER_IP=$SERVER_IP" | sudo tee /etc/fortressbackup-server.conf > /dev/null
echo "SSH_PORT=$SSH_PORT" | sudo tee -a /etc/fortressbackup-server.conf > /dev/null
echo "BACKUP_PORT=$BACKUP_PORT" | sudo tee -a /etc/fortressbackup-server.conf > /dev/null
echo "Configuration saved"

# Verify setup
echo ""
echo "Checking configuration..."
if sudo -u backupuser iptables -L -n > /dev/null 2>&1; then
    echo -e "${GREEN}iptables accessible for backupuser${NC}"
else
    echo -e "${YELLOW}Warning: backupuser may not have iptables access${NC}"
    sudo chmod +x /usr/sbin/iptables
fi

echo -e "${GREEN}"
echo "════════════════════════════════════════════════════════════"
echo "Server installation completed"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Client connection details:"
echo "  IP address: $SERVER_IP"
echo "  SSH port: $SSH_PORT"
echo "  Backup port: $BACKUP_PORT"
echo ""
echo "Directories:"
echo "  Incoming: /backups/incoming/"
echo "  Archive: /backups/archive/"
echo "  Logs: /var/log/fortressbackup.log"
echo ""
echo "Add client SSH keys to:"
echo "  /home/backupuser/.ssh/authorized_keys"
echo ""
echo "Command to add a key:"
echo "  echo 'YOUR_KEY' | sudo tee -a /home/backupuser/.ssh/authorized_keys"
echo ""
echo "Test from client:"
echo "  ssh -p $SSH_PORT backupuser@$SERVER_IP"
echo "  sudo /usr/local/bin/fortress-backup"
echo -e "${NC}"