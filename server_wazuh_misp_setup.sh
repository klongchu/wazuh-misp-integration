#!/bin/bash
set -e

echo "================================================="
echo " Wazuh 4.14.x + MISP Server Setup"
echo "================================================="

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

INTEGRATION_DIR="/var/ossec/integrations"
RULE_DIR="/var/ossec/etc/rules"
OSSEC_CONF="/var/ossec/etc/ossec.conf"

CUSTOM_MISP="$INTEGRATION_DIR/custom-misp"
CUSTOM_MISP_PY="$INTEGRATION_DIR/custom-misp.py"
MISP_RULE="$RULE_DIR/custom_misp_rules.xml"

echo "[1/7] Install dependencies"
apt-get update -qq
apt-get install -y curl python3-requests >/dev/null

echo "[2/7] Create custom-misp wrapper"

if [ -f "$CUSTOM_MISP" ]; then
  echo "[SKIP] $CUSTOM_MISP already exists"
else
cat > "$CUSTOM_MISP" <<'EOF'
#!/bin/sh

WPYTHON_BIN="framework/python/bin/python3"
SCRIPT_PATH="$0"
DIR_NAME="$(cd "$(dirname "$SCRIPT_PATH")"; pwd -P)"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"

case "$SCRIPT_NAME" in
  custom-misp)
    exec "$DIR_NAME/$WPYTHON_BIN" "$DIR_NAME/custom-misp.py" "$@"
    ;;
esac
EOF

  chown root:wazuh "$CUSTOM_MISP"
  chmod 750 "$CUSTOM_MISP"
  echo "[OK] Created $CUSTOM_MISP"
fi

echo "[3/7] Install custom-misp.py"

if [ -f "$CUSTOM_MISP_PY" ]; then
  echo "[FOUND] $CUSTOM_MISP_PY already exists"
  read -p "Overwrite custom-misp.py? [y/N]: " OVERWRITE_PY

  if [[ "$OVERWRITE_PY" =~ ^[Yy]$ ]]; then
    cp "$CUSTOM_MISP_PY" "$CUSTOM_MISP_PY.bak.$(date +%Y%m%d_%H%M%S)"
    curl -L -o "$CUSTOM_MISP_PY" https://pastebin.com/raw/khkh3nUr
    echo "[OK] Overwritten custom-misp.py"
  else
    echo "[SKIP] custom-misp.py unchanged"
  fi
else
  curl -L -o "$CUSTOM_MISP_PY" https://pastebin.com/raw/khkh3nUr
  echo "[OK] Downloaded custom-misp.py"
fi

echo "[4/7] Configure MISP URL/API Key in custom-misp.py"

if grep -q "misp_base_url" "$CUSTOM_MISP_PY"; then
  sed -i "s|misp_base_url = .*|misp_base_url = \"${MISP_URL}/attributes/restSearch/\"|g" "$CUSTOM_MISP_PY"
fi

if grep -q "misp_api_auth_key" "$CUSTOM_MISP_PY"; then
  sed -i "s|misp_api_auth_key = .*|misp_api_auth_key = \"${MISP_KEY}\"|g" "$CUSTOM_MISP_PY"
fi

chown root:wazuh "$CUSTOM_MISP_PY"
chmod 750 "$CUSTOM_MISP_PY"

echo "[5/7] Install MISP rules"

mkdir -p "$RULE_DIR"

if [ -f "$MISP_RULE" ]; then
  echo "[SKIP] $MISP_RULE already exists"
else
cat > "$MISP_RULE" <<'EOF'
<group name="misp,">

  <rule id="100620" level="10">
    <field name="integration">misp</field>
    <match>misp</match>
    <description>MISP Events</description>
    <options>no_full_log</options>
  </rule>

  <rule id="100621" level="5">
    <if_sid>100620</if_sid>
    <field name="misp.error">\.+</field>
    <description>MISP - Error connecting to API</description>
    <options>no_full_log</options>
    <group>misp_error,</group>
  </rule>

  <rule id="100622" level="12">
    <field name="misp.category">\.+</field>
    <description>MISP - IoC found in Threat Intel - Category: $(misp.category), Attribute: $(misp.value)</description>
    <options>no_full_log</options>
    <group>misp_alert,</group>
  </rule>

</group>
EOF

  chown root:wazuh "$MISP_RULE"
  chmod 640 "$MISP_RULE"
  echo "[OK] Created $MISP_RULE"
fi

echo "[6/7] Configure ossec.conf integration"

cp "$OSSEC_CONF" "$OSSEC_CONF.bak.$(date +%Y%m%d_%H%M%S)"

if grep -q "<name>custom-misp</name>" "$OSSEC_CONF"; then
  echo "[SKIP] custom-misp integration already exists in ossec.conf"
else
  sed -i '/<\/ossec_config>/i\
  <integration>\
    <name>custom-misp</name>\
    <group>sysmon_event1,sysmon_event3,sysmon_event6,sysmon_event7,sysmon_event_15,sysmon_event_22,syscheck</group>\
    <alert_format>json</alert_format>\
  </integration>' "$OSSEC_CONF"

  echo "[OK] Added custom-misp integration to ossec.conf"
fi

echo "[7/7] Restart Wazuh Manager"

systemctl restart wazuh-manager

echo ""
echo "================================================="
echo " DONE"
echo "================================================="
echo "Files:"
echo "- $CUSTOM_MISP"
echo "- $CUSTOM_MISP_PY"
echo "- $MISP_RULE"
echo ""
echo "Check:"
echo "systemctl status wazuh-manager"
echo "tail -f /var/ossec/logs/ossec.log"
echo "================================================="