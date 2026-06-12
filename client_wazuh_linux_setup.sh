#!/bin/bash

# Wazuh Agent + Active Response Setup for Linux Clients
#
# Refactor map for later core + wrapper split:
# - Core Logic: privilege/dependency checks, interactive prompts, config backup, ossec.conf updates,
#   XML validation, and service verification.
# - Linux Role Logic: apt-based agent install, Linux agent identity settings, iptables active response,
#   and Linux-specific service/log handling.
#
# ===== Core Logic: shared validation and prompt flow =====

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/wazuh_misp_common.sh"

# Requires root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root"
    exit 1
fi

command -v curl >/dev/null 2>&1 || { echo >&2 "[ERROR] curl is required but not installed. Aborting."; exit 1; }
command -v apt >/dev/null 2>&1 || { echo >&2 "[ERROR] apt is required but not installed. Aborting."; exit 1; }

if ! command -v iptables >/dev/null 2>&1; then
    echo "[INFO] iptables not found. Installing..."
    apt update || { echo "[ERROR] apt update failed"; exit 1; }
    apt install iptables -y || { echo "[ERROR] iptables install failed"; exit 1; }
fi

if ! command -v xmllint >/dev/null 2>&1; then
    echo "[INFO] xmllint not found. Installing..."
    apt update || { echo "[ERROR] apt update failed"; exit 1; }
    apt install libxml2-utils -y || { echo "[ERROR] xmllint install failed"; exit 1; }
fi

iptables -L >/dev/null 2>&1 || { echo "[ERROR] iptables is installed but not usable"; exit 1; }

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
echo "[1/6] Installing Wazuh Agent"
curl -fLO https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.14.0-1_amd64.deb || { echo "[ERROR] Wazuh agent download failed"; exit 1; }
apt install ./wazuh-agent_4.14.0-1_amd64.deb -y || { echo "[ERROR] Wazuh agent install failed"; exit 1; }

# 2. Configure Wazuh Agent
echo "[2/6] Configuring Wazuh Agent"
WAZUH_AGENT_CONF="/var/ossec/etc/ossec.conf"
[ -f "$WAZUH_AGENT_CONF" ] || { echo "[ERROR] Wazuh agent config not found: $WAZUH_AGENT_CONF"; exit 1; }
cp "$WAZUH_AGENT_CONF" "${WAZUH_AGENT_CONF}.bak_$(date +%Y%m%d_%H%M%S)" || { echo "[ERROR] Failed to backup Wazuh agent config"; exit 1; }

# Update manager IP
sed -i "s|<address>.*</address>|<address>$WAZUH_MANAGER</address>|" "$WAZUH_AGENT_CONF" || { echo "[ERROR] Failed to update Wazuh manager address"; exit 1; }

# Set agent name and group
if ! grep -q "<client_buffer>" "$WAZUH_AGENT_CONF"; then
    sed -i "s|</ossec_config>|  <client_buffer>\n    <disabled>no</disabled>\n    <remoted_output>no</remoted_output>\n  </client_buffer>\n</ossec_config>|" "$WAZUH_AGENT_CONF" || { echo "[ERROR] Failed to add client_buffer block"; exit 1; }
fi

if ! grep -q "<agent_name>" "$WAZUH_AGENT_CONF"; then
    sed -i "s|</client_buffer>|  </client_buffer>\n  <agent_name>$AGENT_NAME</agent_name>|" "$WAZUH_AGENT_CONF" || { echo "[ERROR] Failed to add agent_name"; exit 1; }
else
    sed -i "s|<agent_name>.*</agent_name>|<agent_name>$AGENT_NAME</agent_name>|" "$WAZUH_AGENT_CONF" || { echo "[ERROR] Failed to update agent_name"; exit 1; }
fi

if ! grep -q "<agent_group>" "$WAZUH_AGENT_CONF"; then
    sed -i "s|</agent_name>|  </agent_name>\n  <agent_group>$AGENT_GROUP</agent_group>|" "$WAZUH_AGENT_CONF" || { echo "[ERROR] Failed to add agent_group"; exit 1; }
else
    sed -i "s|<agent_group>.*</agent_group>|<agent_group>$AGENT_GROUP</agent_group>|" "$WAZUH_AGENT_CONF" || { echo "[ERROR] Failed to update agent_group"; exit 1; }
fi

# 3. Install Active Response (if enabled)
if [[ "$INSTALL_ACTIVE_RESPONSE" =~ ^[Yy]$ ]]; then
    echo "[3/6] Installing Active Response files"
    AR_BIN_PATH="/var/ossec/active-response/bin"
    mkdir -p "$AR_BIN_PATH"

    # Create block-malicious.sh
    cat > "$AR_BIN_PATH/block-malicious.sh" << 'EOF'
#!/bin/bash

command -v iptables >/dev/null 2>&1 || { echo "[ERROR] iptables missing"; exit 1; }
iptables -L >/dev/null 2>&1 || { echo "[ERROR] iptables is installed but not usable"; exit 1; }

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
        sed -i "s|</ossec_config>|  <active-response>\n    <command>block-malicious</command>\n    <location>local</location>\n    <level>10</level>\n    <timeout>600</timeout>\n  </active-response>\n</ossec_config>|" "$WAZUH_AGENT_CONF" || { echo "[ERROR] Active Response config update failed"; exit 1; }
    else
        echo "[INFO] Active Response config already exists in ossec.conf"
    fi

    xmllint --noout "$WAZUH_AGENT_CONF" || { echo "[ERROR] Wazuh agent config XML validation failed"; exit 1; }
else
    echo "[3/6] Skipping Active Response installation"
fi

# 4. Restart Wazuh Agent
echo "[4/6] Restarting Wazuh Agent"
systemctl daemon-reload || { echo "[ERROR] systemctl daemon-reload failed"; exit 1; }
systemctl enable wazuh-agent || { echo "[ERROR] systemctl enable wazuh-agent failed"; exit 1; }
systemctl restart wazuh-agent || { echo "[ERROR] systemctl restart wazuh-agent failed"; exit 1; }

# 5. Verify services
echo "[5/6] Verifying services"
systemctl is-active --quiet wazuh-agent || { echo "[ERROR] wazuh-agent is not active"; systemctl status wazuh-agent --no-pager; exit 1; }
systemctl status wazuh-agent --no-pager || { echo "[ERROR] Failed to get wazuh-agent status"; exit 1; }

# 6. Check Active Response log
if [ "$INSTALL_ACTIVE_RESPONSE" = "Y" ] || [ "$INSTALL_ACTIVE_RESPONSE" = "y" ]; then
    echo "[6/6] Checking Active Response log"
    AR_LOG_FILE="/var/ossec/logs/active-responses.log"
    if [ -f "$AR_LOG_FILE" ]; then
        echo "Active Response log: $AR_LOG_FILE"
    else
        echo "[WARNING] Active Response log not found at $AR_LOG_FILE"
    fi
fi

echo ""
echo "DONE"
echo "Wazuh Agent config: $WAZUH_AGENT_CONF"
if [ "$INSTALL_ACTIVE_RESPONSE" = "Y" ] || [ "$INSTALL_ACTIVE_RESPONSE" = "y" ]; then
    echo "Active Response script: $AR_BIN_PATH/block-malicious.sh"
    echo "Active Response log: $AR_LOG_FILE"
fi
echo ""
echo "Installation complete. Please check the Wazuh Agent status and logs."
