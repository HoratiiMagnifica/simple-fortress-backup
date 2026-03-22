#!/bin/bash
# web/installer.sh - Web interface installer

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}"
echo "╔════════════════════════════════════════╗"
echo "║   FortressBackup Web Interface         ║"
echo "║   Web interface installer              ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "Installing Python3..."
    apt-get update -qq
    apt-get install -y -qq python3 python3-pip python3-venv
fi

# Prompt for port
echo -e "${YELLOW}Web interface port (Enter for 5000):${NC}"
read WEB_PORT
WEB_PORT=${WEB_PORT:-5000}

# Prompt for password
echo -e "${YELLOW}Enter password for web interface:${NC}"
read -s WEB_PASSWORD
echo ""
echo -e "${YELLOW}Confirm password:${NC}"
read -s WEB_PASSWORD2
echo ""

if [ "$WEB_PASSWORD" != "$WEB_PASSWORD2" ]; then
    echo -e "${RED}Passwords do not match${NC}"
    exit 1
fi

if [ -z "$WEB_PASSWORD" ]; then
    echo -e "${RED}Password cannot be empty${NC}"
    exit 1
fi

# Create directory
sudo mkdir -p /opt/fortressbackup-web
sudo chown -R $USER:$USER /opt/fortressbackup-web

# Copy files
cp -r ./* /opt/fortressbackup-web/
cd /opt/fortressbackup-web

# Create virtual environment
python3 -m venv venv
source venv/bin/activate
pip install flask
deactivate

# Create password file
echo -n "$WEB_PASSWORD" | python3 -c "import sys, hashlib; print(hashlib.sha256(sys.stdin.read().encode()).hexdigest())" > password.hash
chmod 600 password.hash

# Open port in firewall
echo "Opening port $WEB_PORT..."
sudo iptables -I INPUT -p tcp --dport $WEB_PORT -j ACCEPT 2>/dev/null || true

# Save iptables rules
if command -v netfilter-persistent &> /dev/null; then
    sudo netfilter-persistent save
elif command -v iptables-save &> /dev/null; then
    sudo mkdir -p /etc/iptables
    sudo iptables-save > /etc/iptables/rules.v4
fi

# If ufw is used, also open
if command -v ufw &> /dev/null; then
    sudo ufw allow $WEB_PORT/tcp 2>/dev/null || true
fi

echo "Port $WEB_PORT opened"

# Create systemd service
sudo tee /etc/systemd/system/fortress-backup-web.service > /dev/null << EOF
[Unit]
Description=FortressBackup Web Interface
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/fortressbackup-web
Environment="WEB_PORT=$WEB_PORT"
ExecStart=/opt/fortressbackup-web/venv/bin/python3 /opt/fortressbackup-web/app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Start service
sudo systemctl daemon-reload
sudo systemctl enable fortress-backup-web
sudo systemctl restart fortress-backup-web

# Get IP
SERVER_IP=$(hostname -I | awk '{print $1}')

# Check availability
sleep 2
if curl -s -o /dev/null -w "%{http_code}" http://localhost:$WEB_PORT | grep -q "200\|302"; then
    echo -e "${GREEN}Web interface is accessible locally${NC}"
else
    echo -e "${YELLOW}Warning: Web interface not responding locally, check logs:${NC}"
    echo "   sudo journalctl -u fortress-backup-web -f"
fi

echo -e "${GREEN}"
echo "════════════════════════════════════════════════════════════"
echo "Web interface installed successfully"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Access: http://$SERVER_IP:$WEB_PORT"
echo "Password: [set during installation]"
echo ""
echo "Commands:"
echo "   sudo systemctl status fortress-backup-web  - status"
echo "   sudo systemctl restart fortress-backup-web - restart"
echo "   sudo systemctl stop fortress-backup-web    - stop"
echo ""
echo "Web interface logs:"
echo "   sudo journalctl -u fortress-backup-web -f"
echo -e "${NC}"