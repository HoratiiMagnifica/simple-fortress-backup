#!/bin/bash
# scripts/backup-add.sh - Add a new backup job

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}"
echo "════════════════════════════════════════════════════════════"
echo "  Add New Backup"
echo "════════════════════════════════════════════════════════════"
echo -e "${NC}"

# Verify client is installed
if [ ! -f /etc/fortressbackup-client.conf ]; then
    echo -e "${RED}Client not installed. First run: make client${NC}"
    exit 1
fi

# Prompt for backup configuration
echo -e "${YELLOW}What to backup? (full path, e.g., /var/www/site):${NC}"
read SOURCES

echo -e "${YELLOW}Backup time (HH:MM, e.g., 03:00):${NC}"
read BACKUP_TIME

echo -e "${YELLOW}Schedule (daily/weekly/monthly, Enter for daily):${NC}"
read SCHEDULE
SCHEDULE=${SCHEDULE:-daily}

if [ -z "$SOURCES" ] || [ -z "$BACKUP_TIME" ]; then
    echo -e "${RED}All fields are required${NC}"
    exit 1
fi

# Verify source directory exists
if [ ! -e "$SOURCES" ]; then
    echo -e "${RED}Directory does not exist: $SOURCES${NC}"
    exit 1
fi

# Read current configuration
CONFIG_FILE="/etc/fortressbackup-client.conf"

# Find next available ID
CURRENT_IDS=$(grep -E "^BACKUP_[0-9]+_SOURCES" "$CONFIG_FILE" | sed 's/BACKUP_\([0-9]*\)_SOURCES.*/\1/' | sort -n)
NEXT_ID=1
for id in $CURRENT_IDS; do
    if [ "$id" -ge "$NEXT_ID" ]; then
        NEXT_ID=$((id + 1))
    fi
done

echo ""
echo "Adding backup #$NEXT_ID..."
echo "  Sources: $SOURCES"
echo "  Time: $BACKUP_TIME"
echo "  Schedule: $SCHEDULE"
echo ""

# Add to configuration
echo "" | sudo tee -a "$CONFIG_FILE"
echo "BACKUP_${NEXT_ID}_ENABLED=true" | sudo tee -a "$CONFIG_FILE"
echo "BACKUP_${NEXT_ID}_SOURCES=\"$SOURCES\"" | sudo tee -a "$CONFIG_FILE"
echo "BACKUP_${NEXT_ID}_TIME=$BACKUP_TIME" | sudo tee -a "$CONFIG_FILE"
echo "BACKUP_${NEXT_ID}_SCHEDULE=$SCHEDULE" | sudo tee -a "$CONFIG_FILE"

# Update crontab
echo "Updating schedule..."

python3 << EOF
import os
import subprocess

CONFIG_FILE = "/etc/fortressbackup-client.conf"
BACKUP_SCRIPT = "/usr/local/bin/fortress-backup"
LOG_FILE = "/var/log/fortressbackup.log"

def update_crontab():
    backups = []
    config_dict = {}
    cron_lines = []
    
    with open(CONFIG_FILE, 'r') as f:
        for line in f:
            if '=' in line and not line.startswith('#'):
                key, value = line.split('=', 1)
                config_dict[key.strip()] = value.strip().strip('"')
    
    i = 1
    while f"BACKUP_{i}_SOURCES" in config_dict:
        enabled = config_dict.get(f"BACKUP_{i}_ENABLED", 'true')
        if enabled == 'true':
            time = config_dict.get(f"BACKUP_{i}_TIME", '02:00')
            minute, hour = time.split(':')
            schedule = config_dict.get(f"BACKUP_{i}_SCHEDULE", 'daily')
            
            if schedule == 'weekly':
                cron_line = f"{minute} {hour} * * 0"
            elif schedule == 'monthly':
                cron_line = f"{minute} {hour} 1 * *"
            else:
                cron_line = f"{minute} {hour} * * *"
            
            cron_lines.append(f"{cron_line} {BACKUP_SCRIPT} --backup-id {i} >> {LOG_FILE} 2>&1")
        i += 1
    
    try:
        current_cron = subprocess.run(['crontab', '-l'], capture_output=True, text=True).stdout
    except:
        current_cron = ""
    
    new_cron = '\n'.join([l for l in current_cron.split('\n') if 'fortress-backup' not in l and l.strip()])
    if cron_lines:
        new_cron = new_cron + '\n' + '\n'.join(cron_lines) if new_cron else '\n'.join(cron_lines)
    
    if new_cron and not new_cron.endswith('\n'):
        new_cron += '\n'
    
    temp_file = '/tmp/crontab_new'
    with open(temp_file, 'w') as f:
        f.write(new_cron)
    
    subprocess.run(['crontab', temp_file])
    os.unlink(temp_file)
    print("Cron updated")

update_crontab()
EOF

echo -e "${GREEN}"
echo "════════════════════════════════════════════════════════════"
echo "Backup #$NEXT_ID added successfully"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Current backups:"
grep -E "^BACKUP_[0-9]+_SOURCES" "$CONFIG_FILE" | sed 's/BACKUP_\([0-9]*\)_SOURCES=\(.*\)/  Backup \1: \2/'
echo ""
echo "Cron schedule:"
crontab -l 2>/dev/null | grep fortress-backup || echo "  (no jobs)"
echo ""
echo "Test backup:"
echo "  sudo /usr/local/bin/fortress-backup --backup-id $NEXT_ID"
echo -e "${NC}"