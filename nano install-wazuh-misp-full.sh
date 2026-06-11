#!/bin/bash
set -e

# ======================================================
# Wazuh + MISP IOC Detection Full Setup
# For Wazuh Manager Ubuntu
# ======================================================

OSSEC_DIR="/var/ossec"
OSSEC_CONF="$OSSEC_DIR/etc/ossec.conf"
RULE_DIR="$OSSEC_DIR/etc/rules"
DECODER_DIR="$OSSEC_DIR/etc/decoders"
INTEGRATION_DIR="$OSSEC_DIR/integrations"
LIST_DIR="$OSSEC_DIR/etc/lists"
AR_DIR="$OSSEC_DIR/active-response/bin"

BACKUP_DIR="/root/wazuh-misp-backup-$(date +%F-%H%M%S)"

echo "=============================================="
echo " Wazuh + MISP Full IOC Detection Installer"
echo "=============================================="
echo ""

read -p "เตรียมเครื่องตาม Lab HTML แล้วหรือยัง? [y/N]: " PREP_DONE
read -p "ตั้ง hostname เป็น wazuh-server อัตโนมัติไหม? [y/N]: " SET_HOSTNAME
read -p "MISP URL เช่น https://misp.domain.local: " MISP_URL
read -p "MISP API/Auth Key: " MISP_API_KEY
read -p "Telegram Bot Token: " TELEGRAM_TOKEN
read -p "Telegram Chat ID: " TELEGRAM_CHAT_ID
read -p "Enable Active Response? [yes/no] (default: yes): " ENABLE_ACTIVE_RESPONSE
read -p "Active Response Timeout (default: 600): " ACTIVE_RESPONSE_TIMEOUT

echo ""

MISP_URL="${MISP_URL%/}"
ENABLE_ACTIVE_RESPONSE="${ENABLE_ACTIVE_RESPONSE:-yes}"
ACTIVE_RESPONSE_TIMEOUT="${ACTIVE_RESPONSE_TIMEOUT:-600}"

if [ -z "$MISP_URL" ] || [ -z "$MISP_API_KEY" ] || [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
  echo "[ERROR] MISP URL, API Key, Telegram Token, Telegram Chat ID ห้ามว่าง"
  exit 1
fi

if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] กรุณารันด้วย sudo หรือ root"
  exit 1
fi

if [[ ! "$PREP_DONE" =~ ^[Yy]$ ]]; then
  echo "[INFO] Run lab prep steps"
  systemd-machine-id-setup || true
  dbus-uuidgen --ensure || true
  systemctl restart systemd-networkd || true
fi

if [[ "$SET_HOSTNAME" =~ ^[Yy]$ ]]; then
  hostnamectl set-hostname wazuh-server
  if grep -q '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
    sed -i 's/^127\.0\.1\.1[[:space:]].*/127.0.1.1 wazuh-server/' /etc/hosts
  else
    echo '127.0.1.1 wazuh-server' >> /etc/hosts
  fi
fi

if [ -f "$INTEGRATION_DIR/custom-misp" ] || [ -f "$RULE_DIR/misp.xml" ]; then
  read -p "พบการติดตั้ง Wazuh MISP Integration แล้ว ต้องการติดตั้งทับหรือไม่? [y/N]: " OVERWRITE_INSTALL
  if [[ ! "$OVERWRITE_INSTALL" =~ ^[Yy]$ ]]; then
    echo "[INFO] ยกเลิกการติดตั้ง"
    exit 0
  fi
fi

if [ ! -d "$OSSEC_DIR" ]; then
  echo "[ERROR] ไม่พบ $OSSEC_DIR กรุณาติดตั้ง Wazuh Manager ก่อน"
  exit 1
fi

mkdir -p "$BACKUP_DIR"
cp "$OSSEC_CONF" "$BACKUP_DIR/ossec.conf.bak"

echo "[1/10] Install packages"
apt update
apt install -y curl wget python3 python3-pip jq net-tools

echo "[2/10] Download custom-misp"
cd "$INTEGRATION_DIR"

if [ -f custom-misp ]; then
  cp custom-misp "$BACKUP_DIR/custom-misp.bak"
fi

wget -O custom-misp https://raw.githubusercontent.com/cti-misp/MISP/refs/heads/main/integrations/custom-misp
chmod 750 custom-misp
chown root:wazuh custom-misp

echo "[3/10] Configure custom-misp"
sed -i "s|^MISP_BASE_URL *=.*|MISP_BASE_URL = \"${MISP_URL}/attributes/restSearch/\"|g" custom-misp || true
sed -i "s|^MISP_API_KEY *=.*|MISP_API_KEY = \"${MISP_API_KEY}\"|g" custom-misp || true

echo "[4/10] Create MISP rules"
cat > "$RULE_DIR/misp.xml" <<'EOF'
<group name="misp,threat_intel,ioc,">

  <rule id="100800" level="10">
    <decoded_as>json</decoded_as>
    <field name="integration">misp</field>
    <description>MISP IOC Match Detected</description>
    <mitre>
      <id>T1071</id>
    </mitre>
  </rule>

  <rule id="100801" level="12">
    <if_sid>100800</if_sid>
    <field name="misp.type">ip-src|ip-dst</field>
    <description>MISP IOC IP Detected: $(misp.value)</description>
    <group>misp_ip,network,</group>
  </rule>

  <rule id="100802" level="12">
    <if_sid>100800</if_sid>
    <field name="misp.type">domain|hostname</field>
    <description>MISP IOC Domain Detected: $(misp.value)</description>
    <group>misp_domain,dns,</group>
  </rule>

  <rule id="100803" level="12">
    <if_sid>100800</if_sid>
    <field name="misp.type">url</field>
    <description>MISP IOC URL Detected: $(misp.value)</description>
    <group>misp_url,web,</group>
  </rule>

  <rule id="100804" level="14">
    <if_sid>100800</if_sid>
    <field name="misp.type">md5|sha1|sha256</field>
    <description>MISP IOC File Hash Detected: $(misp.value)</description>
    <group>misp_hash,malware,</group>
    <mitre>
      <id>T1204</id>
    </mitre>
  </rule>

  <rule id="100805" level="15">
    <if_sid>100800</if_sid>
    <field name="misp.category">Payload delivery|Artifacts dropped|Network activity</field>
    <description>High Severity MISP IOC Alert: $(misp.value)</description>
    <group>misp_high,incident,</group>
  </rule>

</group>
EOF

chown root:wazuh "$RULE_DIR/misp.xml"
chmod 660 "$RULE_DIR/misp.xml"

echo "[5/10] Create local IOC CDB lists"
mkdir -p "$LIST_DIR"

touch "$LIST_DIR/malware-hashes"
touch "$LIST_DIR/misp-ip"
touch "$LIST_DIR/misp-domain"
touch "$LIST_DIR/misp-url"

chown wazuh:wazuh "$LIST_DIR"/malware-hashes "$LIST_DIR"/misp-ip "$LIST_DIR"/misp-domain "$LIST_DIR"/misp-url
chmod 660 "$LIST_DIR"/malware-hashes "$LIST_DIR"/misp-ip "$LIST_DIR"/misp-domain "$LIST_DIR"/misp-url

if ! grep -q "etc/lists/malware-hashes" "$OSSEC_CONF"; then
  sed -i '/<ruleset>/a\    <list>etc/lists/malware-hashes</list>\n    <list>etc/lists/misp-ip</list>\n    <list>etc/lists/misp-domain</list>\n    <list>etc/lists/misp-url</list>' "$OSSEC_CONF"
fi

echo "[6/10] Add MISP integration to ossec.conf"
if ! grep -q "<name>custom-misp</name>" "$OSSEC_CONF"; then
  sed -i '/<\/ossec_config>/i\
  <integration>\
    <name>custom-misp</name>\
    <group>sysmon_event_1,sysmon_event_3,sysmon_event_6,sysmon_event_7,sysmon_event_22,web,syscheck,</group>
    <alert_format>json</alert_format>\
  </integration>' "$OSSEC_CONF"
fi

echo "[7/10] Add Telegram custom integration"
cat > "$INTEGRATION_DIR/custom-telegram" <<'EOF'
#!/bin/bash
WPYTHON_BIN="framework/python/bin/python3"
SCRIPT_PATH_NAME="$0"
DIR_NAME="$(cd $(dirname ${SCRIPT_PATH_NAME}); pwd -P)"
SCRIPT_NAME="$(basename ${SCRIPT_PATH_NAME})"
case ${DIR_NAME} in
    */active-response/bin | */wodles*)
        if [ -z "${WAZUH_PATH}" ]; then
            WAZUH_PATH="$(cd ${DIR_NAME}/../..; pwd)"
        fi
        PYTHON_SCRIPT="${DIR_NAME}/${SCRIPT_NAME}.py"
    ;;
    */bin)
        if [ -z "${WAZUH_PATH}" ]; then
            WAZUH_PATH="$(cd ${DIR_NAME}/..; pwd)"
        fi
        PYTHON_SCRIPT="${WAZUH_PATH}/framework/scripts/${SCRIPT_NAME}.py"
    ;;
     */integrations)
        if [ -z "${WAZUH_PATH}" ]; then
            WAZUH_PATH="$(cd ${DIR_NAME}/..; pwd)"
        fi
        PYTHON_SCRIPT="${DIR_NAME}/${SCRIPT_NAME}.py"
    ;;
esac
${WAZUH_PATH}/${WPYTHON_BIN} ${PYTHON_SCRIPT} "$@"
EOF

cat > "$INTEGRATION_DIR/custom-telegram.py" <<EOF
#!/var/ossec/framework/python/bin/python3
import sys, json, requests

TELEGRAM_TOKEN = "${TELEGRAM_TOKEN}"
TELEGRAM_CHAT_ID = "${TELEGRAM_CHAT_ID}"

def send(text):
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    requests.post(url, json={
        "chat_id": TELEGRAM_CHAT_ID,
        "text": text,
        "parse_mode": "HTML"
    }, timeout=10)

alert_file = sys.argv[1]
with open(alert_file, "r", encoding="utf-8") as f:
    alert = json.load(f)

rule = alert.get("rule", {})
agent = alert.get("agent", {})
data = alert.get("data", {})

msg = f"""
🚨 <b>Wazuh MISP IOC Alert</b>

<b>Level:</b> {rule.get("level")}
<b>Rule:</b> {rule.get("id")} - {rule.get("description")}
<b>Agent:</b> {agent.get("name", "-")} / {agent.get("ip", "-")}

<b>IOC:</b> {data.get("misp", {}).get("value", "-")}
<b>Type:</b> {data.get("misp", {}).get("type", "-")}
<b>Category:</b> {data.get("misp", {}).get("category", "-")}

<b>Full Log:</b>
{alert.get("full_log", "-")[:1500]}
"""
send(msg)
EOF

chmod 750 "$INTEGRATION_DIR/custom-telegram" "$INTEGRATION_DIR/custom-telegram.py"
chown root:wazuh "$INTEGRATION_DIR/custom-telegram" "$INTEGRATION_DIR/custom-telegram.py"

if ! grep -q "<name>custom-telegram</name>" "$OSSEC_CONF"; then
  sed -i '/<\/ossec_config>/i\
  <integration>\
    <name>custom-telegram</name>\
    <rule_id>100800,100801,100802,100803,100804,100805</rule_id>\
    <alert_format>json</alert_format>\
  </integration>' "$OSSEC_CONF"
fi

echo "[8/10] Create Linux Active Response script"
cat > "$AR_DIR/block-misp-ioc.sh" <<'EOF'
#!/bin/bash
ACTION=$1
USER=$2
IP=$3
ALERT_ID=$4
RULE_ID=$5

LOG_FILE="/var/ossec/logs/active-responses.log"

read INPUT_JSON
IOC=$(echo "$INPUT_JSON" | grep -oP '"value"\s*:\s*"\K[^"]+' | head -1)

echo "$(date) MISP Active Response IOC=$IOC ACTION=$ACTION" >> "$LOG_FILE"

if [[ "$IOC" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  if [ "$ACTION" = "add" ]; then
    iptables -I INPUT -s "$IOC" -j DROP || true
    iptables -I OUTPUT -d "$IOC" -j DROP || true
    echo "$(date) Blocked IP $IOC" >> "$LOG_FILE"
  elif [ "$ACTION" = "delete" ]; then
    iptables -D INPUT -s "$IOC" -j DROP || true
    iptables -D OUTPUT -d "$IOC" -j DROP || true
    echo "$(date) Unblocked IP $IOC" >> "$LOG_FILE"
  fi
fi

exit 0
EOF

chmod 750 "$AR_DIR/block-misp-ioc.sh"
chown root:wazuh "$AR_DIR/block-misp-ioc.sh"

if [ "$ENABLE_ACTIVE_RESPONSE" = "yes" ]; then
  if ! grep -q "<name>block-misp-ioc</name>" "$OSSEC_CONF"; then
    sed -i '/<\/ossec_config>/i\
  <command>\
    <name>block-misp-ioc</name>\
    <executable>block-misp-ioc.sh</executable>\
    <timeout_allowed>yes</timeout_allowed>\
  </command>\
\
  <active-response>\
    <command>block-misp-ioc</command>\
    <location>local</location>\
    <rules_id>100801</rules_id>\
    <timeout>'"$ACTIVE_RESPONSE_TIMEOUT"'</timeout>\
  </active-response>' "$OSSEC_CONF"
  fi
fi

echo "[9/10] Create Windows Active Response files"
mkdir -p /root/wazuh-windows-active-response

cat > /root/wazuh-windows-active-response/action-script.bat <<'EOF'
@echo off
powershell.exe -ExecutionPolicy Bypass -File "C:\Program Files (x86)\ossec-agent\active-response\bin\block-malicious.ps1"
EOF

cat > /root/wazuh-windows-active-response/block-malicious.ps1 <<'EOF'
$inputJson = [Console]::In.ReadToEnd()
$log = "C:\Program Files (x86)\ossec-agent\active-response\active-response.log"

try {
    $json = $inputJson | ConvertFrom-Json
    $ioc = $json.parameters.alert.data.misp.value
} catch {
    Add-Content $log "$(Get-Date) Cannot parse IOC"
    exit 0
}

if ($ioc -match '^\d{1,3}(\.\d{1,3}){3}$') {
    New-NetFirewallRule -DisplayName "Wazuh MISP Block $ioc" `
      -Direction Outbound `
      -RemoteAddress $ioc `
      -Action Block `
      -Profile Any `
      -ErrorAction SilentlyContinue

    Add-Content $log "$(Get-Date) Blocked MISP IOC IP: $ioc"
}
EOF

echo "[10/10] Verify/Create Sysmon Event ID 22 rule"
LOCAL_RULES="$RULE_DIR/local_rules.xml"

if grep -R "sysmon_event_22" /var/ossec/ruleset/rules/ "$RULE_DIR" >/dev/null 2>&1; then
  echo "[OK] Sysmon Event ID 22 rule already exists"
else
  echo "[INFO] Missing sysmon_event_22 rule. Adding Rule ID 61650 to local_rules.xml"

  if [ ! -f "$LOCAL_RULES" ]; then
cat > "$LOCAL_RULES" <<'EOF'
<group name="local,syslog,sshd,">
</group>
EOF
  fi

  cp "$LOCAL_RULES" "$BACKUP_DIR/local_rules.xml.bak"

  if grep -q 'id="61650"' "$LOCAL_RULES"; then
    echo "[SKIP] Rule ID 61650 already exists in local_rules.xml"
  else
    sed -i '/<\/group>/i\
  <rule id="61650" level="8" overwrite="yes">\
    <if_sid>61600</if_sid>\
    <field name="win.system.eventID">^22$</field>\
    <description>Sysmon - Event ID 22: DNSEvent (DNS query)</description>\
    <options>no_full_log</options>\
    <group>sysmon_event_22,</group>\
  </rule>' "$LOCAL_RULES"

    chown root:wazuh "$LOCAL_RULES"
    chmod 640 "$LOCAL_RULES"
    echo "[OK] Added Rule ID 61650"
  fi
fi

echo "[11/11] Validate and restart Wazuh"
"$OSSEC_DIR/bin/wazuh-analysisd" -t || {
  echo "[ERROR] Wazuh config test failed"
  echo "Backup อยู่ที่ $BACKUP_DIR"
  exit 1
}

systemctl restart wazuh-manager

echo "=============================================="
echo "DONE"
echo "Backup: $BACKUP_DIR"
echo ""
echo "Rules: $RULE_DIR/misp.xml"
echo "MISP Integration: $INTEGRATION_DIR/custom-misp"
echo "Telegram Integration: $INTEGRATION_DIR/custom-telegram.py"
echo "Linux Active Response: $AR_DIR/block-misp-ioc.sh"
echo "Windows AR files: /root/wazuh-windows-active-response/"
echo ""
echo "ตรวจสอบ:"
echo "systemctl status wazuh-manager"
echo "tail -f /var/ossec/logs/ossec.log"
echo "tail -f /var/ossec/logs/alerts/alerts.json"
echo "=============================================="