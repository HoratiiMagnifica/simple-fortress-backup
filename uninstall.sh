#!/bin/bash
# scripts/uninstall.sh - Complete FortressBackup uninstaller

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}"
echo "╔════════════════════════════════════════╗"
echo "║     FortressBackup Uninstall           ║"
echo "║     Complete removal                   ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}WARNING! This will remove:${NC}"
echo "  • All backups (/backups)"
echo "  • backupuser account"
echo "  • Scripts and configuration"
echo "  • Cron jobs"
echo "  • Logs"
echo "  • Web interface and its service"
echo "  • SSH keys"
echo ""

echo -e "${YELLOW}Continue? (y/N):${NC}"
read CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Starting removal..."
echo ""

# Remove web interface
echo "Removing web interface..."

if systemctl list-unit-files | grep -q fortress-backup-web.service; then
    sudo systemctl stop fortress-backup-web 2>/dev/null || true
    sudo systemctl disable fortress-backup-web 2>/dev/null || true
    sudo rm -f /etc/systemd/system/fortress-backup-web.service
    sudo systemctl daemon-reload
    echo "  fortress-backup-web service removed"
fi

if [ -d /opt/fortressbackup-web ]; then
    sudo rm -rf /opt/fortressbackup-web
    echo "  /opt/fortressbackup-web directory removed"
fi

WEB_PORT=$(grep -oP 'WEB_PORT=\K\d+' /etc/systemd/system/fortress-backup-web.service 2>/dev/null || echo "5000")
sudo iptables -D INPUT -p tcp --dport $WEB_PORT -j ACCEPT 2>/dev/null || true
if command -v ufw &> /dev/null; then
    sudo ufw delete allow $WEB_PORT/tcp 2>/dev/null || true
fi
echo "  Port $WEB_PORT closed"

# Remove server components
echo ""
echo "Removing server components..."

if id backupuser &>/dev/null; then
    sudo pkill -u backupuser 2>/dev/null || true
    sudo userdel -r backupuser 2>/dev/null || true
    echo "  backupuser removed"
fi

if [ -d /backups ]; then
    sudo rm -rf /backups
    echo "  /backups directory removed"
fi

# Remove client components
echo ""
echo "Removing client components..."

sudo rm -f /usr/local/bin/fortress-backup
sudo rm -f /usr/local/bin/backup-receiver
sudo rm -f /usr/local/bin/firewall-manager
echo "  Scripts removed"

sudo rm -f /etc/fortressbackup-client.conf
sudo rm -f /etc/fortressbackup-server.conf
sudo rm -f /etc/sudoers.d/fortressbackup
echo "  Configuration removed"

# Remove SSH keys
echo ""
echo "Removing SSH keys..."

sudo rm -f /root/.ssh/id_ed25519_fortress*
sudo rm -f /root/.ssh/id_rsa_fortressbackup*

if [ -d /home/backupuser/.ssh ]; then
    sudo rm -rf /home/backupuser/.ssh
fi
echo "  SSH keys removed"

# Remove cron jobs
echo ""
echo "Removing cron jobs..."

if sudo crontab -l 2>/dev/null | grep -q fortress-backup; then
    sudo crontab -l 2>/dev/null | grep -v fortress-backup | sudo crontab - 2>/dev/null || true
    echo "  Root cron jobs removed"
fi

if crontab -l 2>/dev/null | grep -q fortress-backup; then
    crontab -l 2>/dev/null | grep -v fortress-backup | crontab - 2>/dev/null || true
    echo "  User cron jobs removed"
fi

# Remove logs
echo ""
echo "Removing logs..."

sudo rm -f /var/log/fortressbackup.log
sudo rm -f /var/log/fortressbackup.log.* 2>/dev/null || true
echo "  Logs removed"

# Close firewall ports
echo ""
echo -e "${YELLOW}Close firewall ports? (y/N):${NC}"
read CLOSE_PORTS

if [ "$CLOSE_PORTS" = "y" ] || [ "$CLOSE_PORTS" = "Y" ]; then
    echo "Closing ports..."
    
    sudo iptables -D INPUT -p tcp --dport 2222 -j ACCEPT 2>/dev/null || true
    sudo iptables -D INPUT -p tcp --dport 5000 -j ACCEPT 2>/dev/null || true
    sudo iptables -D INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null || true
    
    if command -v ufw &> /dev/null; then
        sudo ufw delete allow 2222/tcp 2>/dev/null || true
        sudo ufw delete allow 5000/tcp 2>/dev/null || true
        sudo ufw delete allow 8080/tcp 2>/dev/null || true
        echo "  UFW rules removed"
    fi
    
    if command -v netfilter-persistent &> /dev/null; then
        sudo netfilter-persistent save
    elif command -v iptables-save &> /dev/null; then
        sudo mkdir -p /etc/iptables
        sudo iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    
    echo "  Ports closed"
fi

# Additional cleanup
echo ""
echo "Performing additional cleanup..."

sudo rm -rf /tmp/backup_*.tar.gz 2>/dev/null || true
sudo rm -rf /tmp/backup_* 2>/dev/null || true
sudo rm -rf /opt/venv-fortress* 2>/dev/null || true
echo "  Temporary files removed"

echo -e "${GREEN}"
echo "════════════════════════════════════════════════════════════"
echo "FortressBackup has been completely removed"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Removed:"
echo "  • Web interface and systemd service"
echo "  • All backups and backupuser account"
echo "  • Scripts and configuration"
echo "  • SSH keys"
echo "  • Cron jobs"
echo "  • Logs"
echo "  • Open ports"
echo ""
echo "For complete cleanup, also check:"
echo "  • /etc/ssh/sshd_config (if you added port 2222)"
echo "  • Hosting control panel firewall rules"
echo -e "${NC}"