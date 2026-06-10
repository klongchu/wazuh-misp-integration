#!/bin/bash
set -e

echo "=== Wazuh Server MISP Setup ==="

read -p "MISP URL เช่น https://misp.domain.local: " MISP_URL
read -s -p "MISP API/Auth Key: " MISP_KEY
echo ""

MISP_URL="${MISP_URL%/}"

if [ -z "$MISP_URL" ] || [ -z "$MISP_KEY" ]; then
  echo "[ERROR] MISP URL/API Key ห้ามว่าง"
  exit 1
fi

if [ ! -d /var/ossec ]; then
  echo "[ERROR] ไม่พบ /var/ossec กรุณารันบน Wazuh Manager"
  exit 1
fi

apt-get update -qq
apt-get install -y curl python3-requests >/dev/null

cd /var/ossec/integrations

echo "[1/5] Download custom-misp.py"
curl -L -o custom-misp.py https://pastebin.com/raw/khkh3nUr

echo "[2/5] Set MISP URL/Auth Key"
sed -i "s|misp_base_url = .*|misp_base_url = \"${MISP_URL}/attributes/restSearch/\"|g" custom-misp.py
sed -i "s|misp_api_auth_key = .*|misp_api_auth_key = \"${MISP_KEY}\"|g" custom-misp.py

echo "[3/5] Permission"
chown root:wazuh custom-misp.py
chmod 750 custom-misp.py

echo "[4/5] Configure ossec.conf"
cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.bak.$(date +%Y%m%d_%H%M%S)

if ! grep -q "custom-misp" /var/ossec/etc/ossec.conf; then
  sed -i '/<\/ossec_config>/i\
  <integration>\
    <name>custom-misp</name>\
    <group>sysmon_event1,sysmon_event3,sysmon_event6,sysmon_event7,sysmon_event_15,sysmon_event_22,syscheck</group>\
    <alert_format>json</alert_format>\
  </integration>' /var/ossec/etc/ossec.conf
fi

echo "[5/5] Restart Wazuh Manager"
systemctl restart wazuh-manager

echo "DONE"
echo "ตรวจสอบ:"
echo "systemctl status wazuh-manager"
echo "tail -f /var/ossec/logs/ossec.log"