#!/bin/bash
# scripts/backup-list.sh - List all backup jobs

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CONFIG_FILE="/etc/fortressbackup-client.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Client not installed. First run: make client${NC}"
    exit 1
fi

echo -e "${GREEN}"
echo "════════════════════════════════════════════════════════════"
echo "  Backup Jobs"
echo "════════════════════════════════════════════════════════════"
echo -e "${NC}"

echo -e "${YELLOW}Configuration: $CONFIG_FILE${NC}"
echo ""

# Display backups
i=1
while true; do
    SOURCES_VAR="BACKUP_${i}_SOURCES"
    TIME_VAR="BACKUP_${i}_TIME"
    SCHEDULE_VAR="BACKUP_${i}_SCHEDULE"
    ENABLED_VAR="BACKUP_${i}_ENABLED"
    
    SOURCES=$(grep "^$SOURCES_VAR=" "$CONFIG_FILE" | cut -d= -f2- | sed 's/"//g')
    if [ -z "$SOURCES" ]; then
        break
    fi
    
    TIME=$(grep "^$TIME_VAR=" "$CONFIG_FILE" | cut -d= -f2 | sed 's/"//g')
    SCHEDULE=$(grep "^$SCHEDULE_VAR=" "$CONFIG_FILE" | cut -d= -f2 | sed 's/"//g')
    ENABLED=$(grep "^$ENABLED_VAR=" "$CONFIG_FILE" | cut -d= -f2 | sed 's/"//g')
    
    case $SCHEDULE in
        daily)   SCHEDULE_TEXT="Daily" ;;
        weekly)  SCHEDULE_TEXT="Weekly (Sunday)" ;;
        monthly) SCHEDULE_TEXT="Monthly (1st day)" ;;
        *)       SCHEDULE_TEXT=$SCHEDULE ;;
    esac
    
    if [ "$ENABLED" = "true" ]; then
        STATUS="${GREEN}Enabled${NC}"
    else
        STATUS="${RED}Disabled${NC}"
    fi
    
    echo -e "${YELLOW}──────────────────────────────────────────────────${NC}"
    echo -e "Backup #$i"
    echo -e "  Sources: ${GREEN}$SOURCES${NC}"
    echo -e "  Time: $TIME"
    echo -e "  Schedule: $SCHEDULE_TEXT"
    echo -e "  Status: $STATUS"
    echo ""
    echo -e "  Manual run:"
    echo -e "    sudo /usr/local/bin/fortress-backup --backup-id $i"
    echo ""
    
    i=$((i + 1))
done

if [ $i -eq 1 ]; then
    echo -e "${YELLOW}No backups configured${NC}"
    echo ""
    echo "Add a backup:"
    echo "  make backup-add"
    echo "  or via web interface"
fi

echo ""
echo -e "${YELLOW}Cron schedule:${NC}"
crontab -l 2>/dev/null | grep fortress-backup || echo "  (no jobs)"
echo ""

echo -e "${YELLOW}Detailed cron entries:${NC}"
crontab -l 2>/dev/null | grep fortress-backup | while read line; do
    echo "  $line"
done

echo -e "${NC}"