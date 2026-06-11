#!/bin/bash

# Wazuh Agent + Active Response Setup for Linux Clients

# Requires root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root"
    exit 1
fi

echo "=============================================="
echo " Wazuh Agent + Active Response Setup"
echo "=============================================="
echo ""

read -p "Wazuh Manager IP/FQDN: " WAZUH_MANAGER
read -p "Agent Name [Enter = Hostname]: " AGENT_NAME
read -p "Agent Group [Enter = linux,misp]: " AGENT_GROUP
read -p "Install Active Response for IP blocking? [Y/n]: " INSTALL_ACTIVE_RESPONSE

if [ -z "$AGENT_NAME" ]; then
    AGENT_NAME=$(hostname)
fi

if [ -z "$AGENT_GROUP" ]; then
    AGENT_GROUP="linux,misp"
fi

if [ -z "$INSTALL_ACTIVE_RESPONSE" ]; then
    INSTALL_ACTIVE_RESPONSE="Y"
fi

if [ -z "$WAZUH_MANAGER" ]; then
    echo "[ERROR] Wazuh Manager cannot be empty"
    exit 1
fi

# 1. Install Wazuh Agent
echo "[1/5] Installing Wazuh Agent"
curl -sO https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.14.0-1_amd64.deb
apt install ./wazuh-agent_4.14.0-1_amd64.deb -y

# 2. Configure Wazuh Agent
echo "[2/5] Configuring Wazuh Agent"
WAZUH_AGENT_CONF="/var/ossec/etc/ossec.conf"
cp "$WAZUH_AGENT_CONF" "${WAZUH_AGENT_CONF}.bak_$(date +%Y%m%d_%H%M%S)"

# Update manager IP
sed -i "s|<address>.*</address>|<address>$WAZUH_MANAGER</address>|" "$WAZUH_AGENT_CONF"

# Set agent name and group
if ! grep -q "<client_buffer>" "$WAZUH_AGENT_CONF"; then
    sed -i "s|</ossec_config>|  <client_buffer>\n    <disabled>no</disabled>\n    <remoted_output>no</remoted_output>\n  </client_buffer>\n</ossec_config>|" "$WAZUH_AGENT_CONF"
fi

if ! grep -q "<agent_name>" "$WAZUH_AGENT_CONF"; then
    sed -i "s|</client_buffer>|  </client_buffer>\n  <agent_name>$AGENT_NAME</agent_name>|" "$WAZUH_AGENT_CONF"
else
    sed -i "s|<agent_name>.*</agent_name>|<agent_name>$AGENT_NAME</agent_name>|" "$WAZUH_AGENT_CONF"
fi

if ! grep -q "<agent_group>" "$WAZUH_AGENT_CONF"; then
    sed -i "s|</agent_name>|  </agent_name>\n  <agent_group>$AGENT_GROUP</agent_group>|" "$WAZUH_AGENT_CONF"
else
    sed -i "s|<agent_group>.*</agent_group>|<agent_group>$AGENT_GROUP</agent_group>|" "$WAZUH_AGENT_CONF"
fi

# 3. Install Active Response (if enabled)
if [[ "$INSTALL_ACTIVE_RESPONSE" =~ ^[Yy]$ ]]; then
    echo "[3/5] Installing Active Response files"
    AR_BIN_PATH="/var/ossec/active-response/bin"
    mkdir -p "$AR_BIN_PATH"

    # Create block-malicious.sh
    cat > "$AR_BIN_PATH/block-malicious.sh" << 'EOF'
#!/bin/bash

# Wazuh Active Response script for IP blocking on Linux

ACTION="$1"
USER="$2"
IP="$3"
AGENT_ID="$4"

LOG_FILE="/var/ossec/logs/active-responses.log"

write_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

if [ -z "$IP" ]; then
    write_log "[ERROR] IP address not provided. Exiting."
    exit 1
fi

RULE_NAME="wazuh-misp-block-$IP"

case "$ACTION" in
    add)
        if ! iptables -C INPUT -s "$IP" -j DROP 2>/dev/null; then
            iptables -A INPUT -s "$IP" -j DROP -m comment --comment "$RULE_NAME"
            iptables -A OUTPUT -d "$IP" -j DROP -m comment --comment "$RULE_NAME"
            write_log "Blocked IP: $IP (Agent: $AGENT_ID)"
        else
            write_log "IP $IP already blocked (Agent: $AGENT_ID)"
        fi
        ;;
    delete)
        if iptables -C INPUT -s "$IP" -j DROP 2>/dev/null; then
            iptables -D INPUT -s "$IP" -j DROP -m comment --comment "$RULE_NAME"
            iptables -D OUTPUT -d "$IP" -j DROP -m comment --comment "$RULE_NAME"
            write_log "Unblocked IP: $IP (Agent: $AGENT_ID)"
        else
            write_log "IP $IP not blocked (Agent: $AGENT_ID)"
        fi
        ;;
    *)
        write_log "[ERROR] Invalid action: $ACTION. Exiting."
        exit 1
        ;;
esac

exit 0
EOF
    chmod +x "$AR_BIN_PATH/block-malicious.sh"

    # Add active response configuration to ossec.conf
    if ! grep -q "<active-response>" "$WAZUH_AGENT_CONF"; then
        sed -i "s|</ossec_config>|  <active-response>\n    <command>block-malicious</command>\n    <location>local</location>\n    <level>10</level>\n    <timeout>600</timeout>\n  </active-response>\n</ossec_config>|" "$WAZUH_AGENT_CONF"
    else
        echo "[INFO] Active Response config already exists in ossec.conf"
    fi
else
    echo "[3/5] Skipping Active Response installation"
fi

# 4. Restart Wazuh Agent
echo "[4/5] Restarting Wazuh Agent"
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl restart wazuh-agent

# 5. Verify services
echo "[5/5] Verifying services"
systemctl status wazuh-agent --no-pager

echo ""
echo "DONE"
echo "Wazuh Agent config: $WAZUH_AGENT_CONF"
if [[ "$INSTALL_ACTIVE_RESPONSE" =~ ^[Yy]$ ]]; then
    echo "Active Response script: $AR_BIN_PATH/block-malicious.sh"
    echo "Active Response log: $LOG_FILE"
fi
echo ""
echo "Installation complete. Please check the Wazuh Agent status."
