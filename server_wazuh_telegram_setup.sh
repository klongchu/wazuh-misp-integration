#!/bin/bash
set -e

echo "==============================================="
echo " Wazuh Telegram Alert Integration Setup"
echo "==============================================="

read -p "Telegram Bot Token: " TELEGRAM_TOKEN
read -p "Telegram Chat ID: " TELEGRAM_CHAT_ID

if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
  echo "[ERROR] TELEGRAM_TOKEN / TELEGRAM_CHAT_ID ห้ามว่าง"
  exit 1
fi

if [ ! -d "/var/ossec" ]; then
  echo "[ERROR] ไม่พบ /var/ossec กรุณารันบน Wazuh Manager"
  exit 1
fi

INTEGRATION_DIR="/var/ossec/integrations"
OSSEC_CONF="/var/ossec/etc/ossec.conf"

CUSTOM_TELEGRAM="$INTEGRATION_DIR/custom-telegram"
CUSTOM_TELEGRAM_PY="$INTEGRATION_DIR/custom-telegram.py"

write_telegram_script() {
cat > "$CUSTOM_TELEGRAM_PY" <<EOF
#!/var/ossec/framework/python/bin/python3
import sys
import json
import requests

BOT_TOKEN = "${TELEGRAM_TOKEN}"
CHAT_ID = "${TELEGRAM_CHAT_ID}"

def value(data, path, default="-"):
    current = data
    for key in path.split("."):
        if isinstance(current, dict) and key in current:
            current = current[key]
        else:
            return default
    return current if current not in [None, ""] else default

try:
    alert_file = sys.argv[1]

    with open(alert_file, "r", encoding="utf-8") as f:
        alert = json.load(f)

    rule_id = value(alert, "rule.id")
    level = value(alert, "rule.level")
    description = value(alert, "rule.description")
    agent_name = value(alert, "agent.name")
    agent_ip = value(alert, "agent.ip")
    location = value(alert, "location")

    misp_category = value(alert, "misp.category")
    misp_value = value(alert, "misp.value")
    misp_event_id = value(alert, "misp.event_id")
    misp_type = value(alert, "misp.type")

    message = f"""🚨 Wazuh MISP Alert

Rule ID: {rule_id}
Level: {level}
Description: {description}

Agent: {agent_name}
IP: {agent_ip}
Location: {location}

MISP Category: {misp_category}
MISP Type: {misp_type}
IOC: {misp_value}
MISP Event ID: {misp_event_id}
"""

    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"

    payload = {
        "chat_id": CHAT_ID,
        "text": message
    }

    requests.post(url, json=payload, timeout=10)

except Exception as e:
    print(f"Telegram integration error: {e}")
EOF
}

echo "[1/5] Install dependencies"
apt-get update -qq
apt-get install -y curl python3-requests >/dev/null

echo "[2/5] Create custom-telegram wrapper"

if [ -f "$CUSTOM_TELEGRAM" ]; then
  echo "[SKIP] $CUSTOM_TELEGRAM already exists"
else
cat > "$CUSTOM_TELEGRAM" <<'EOF'
#!/bin/sh
exec /var/ossec/framework/python/bin/python3 /var/ossec/integrations/custom-telegram.py "$@"
EOF
sed -i 's/\r$//' "$CUSTOM_TELEGRAM"

  chown root:wazuh "$CUSTOM_TELEGRAM"
  chmod 750 "$CUSTOM_TELEGRAM"
  echo "[OK] Created $CUSTOM_TELEGRAM"
fi

echo "[3/5] Create custom-telegram.py"

if [ -f "$CUSTOM_TELEGRAM_PY" ]; then
  echo "[FOUND] $CUSTOM_TELEGRAM_PY already exists"
  read -p "Overwrite custom-telegram.py? [y/N]: " OVERWRITE

  if [[ "$OVERWRITE" =~ ^[Yy]$ ]]; then
    cp "$CUSTOM_TELEGRAM_PY" "$CUSTOM_TELEGRAM_PY.bak.$(date +%Y%m%d_%H%M%S)"
    write_telegram_script
    echo "[OK] Overwritten $CUSTOM_TELEGRAM_PY"
  else
    echo "[SKIP] custom-telegram.py unchanged"
  fi
else
  write_telegram_script
  echo "[OK] Created $CUSTOM_TELEGRAM_PY"
fi

chown root:wazuh "$CUSTOM_TELEGRAM_PY"
chmod 750 "$CUSTOM_TELEGRAM_PY"

echo "[4/5] Configure ossec.conf"

cp "$OSSEC_CONF" "$OSSEC_CONF.bak.$(date +%Y%m%d_%H%M%S)"

if grep -Eq "<name>custom-telegram(\.py)?</name>" "$OSSEC_CONF"; then
  perl -0pi -e 's/\n\s*<integration>\s*\n\s*<name>custom-telegram(?:\.py)?<\/name>\s*\n\s*<rule_id>100622<\/rule_id>\s*\n\s*<alert_format>json<\/alert_format>\s*\n\s*<\/integration>//g' "$OSSEC_CONF"
  echo "[OK] Removed old custom-telegram integration from ossec.conf"
fi

sed -i '/<\/global>/a\
\
  <integration>\
    <name>custom-telegram</name>\
    <rule_id>100622</rule_id>\
    <alert_format>json</alert_format>\
  </integration>' "$OSSEC_CONF"

echo "[OK] Added custom-telegram integration"

echo "[4.5/5] Sending test Telegram message..."
if python3 "$CUSTOM_TELEGRAM_PY" <(echo '{"rule": {"id": "000", "level": "0", "description": "Test message from Wazuh Telegram setup script"}}') > /dev/null 2>&1; then
    echo "[OK] Test message sent successfully."
else
    echo "[WARN] Failed to send test message. Check Telegram Bot Token, Chat ID, and script permissions."
fi

echo "[5/5] Restart Wazuh Manager"

systemctl restart wazuh-manager

echo ""
echo "==============================================="
echo " DONE"
echo "==============================================="
echo "Send only Rule ID: 100622"
echo "Check:"
echo "tail -f /var/ossec/logs/ossec.log"
echo "==============================================="
