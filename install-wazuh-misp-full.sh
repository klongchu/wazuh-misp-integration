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
MISP_RULE_FILE="$RULE_DIR/misp.xml"
TELEGRAM_WRAPPER_FILE="$INTEGRATION_DIR/custom-telegram"
TELEGRAM_PY_FILE="$INTEGRATION_DIR/custom-telegram.py"
LINUX_AR_FILE="$AR_DIR/block-misp-ioc.sh"
WINDOWS_AR_DIR="/root/wazuh-windows-active-response"
WINDOWS_AR_BAT="$WINDOWS_AR_DIR/action-script.bat"
WINDOWS_AR_PS1="$WINDOWS_AR_DIR/block-malicious.ps1"

backup_file_if_exists() {
  local file="$1"
  if [ -f "$file" ]; then
    local safe_name
    safe_name=$(echo "$file" | sed 's#/#_#g')
    cp "$file" "$BACKUP_DIR/${safe_name}.bak"
  fi
}

prompt_tty() {
  local var_name="$1"
  local prompt_text="$2"
  local value=""
  if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    read -r -p "$prompt_text" value </dev/tty >/dev/tty 2>/dev/tty
  else
    read -r -p "$prompt_text" value
  fi
  printf -v "$var_name" '%s' "$value"
}

upsert_managed_block() {
  local file="$1"
  local marker="$2"
  local content="$3"

  python3 - "$file" "$marker" "$content" <<'PY'
import sys
from pathlib import Path

file_path = Path(sys.argv[1])
marker = sys.argv[2]
content = sys.argv[3]
start = f"<!-- {marker}:BEGIN -->"
end = f"<!-- {marker}:END -->"
block = f"{start}\n{content}\n{end}"
text = file_path.read_text(encoding="utf-8")

if start in text and end in text:
    s = text.index(start)
    e = text.index(end, s) + len(end)
    text = text[:s] + block + text[e:]
elif content in text:
    pass
elif "</ossec_config>" in text:
    text = text.replace("</ossec_config>", block + "\n</ossec_config>", 1)
else:
    raise SystemExit("Missing </ossec_config> in ossec.conf")

file_path.write_text(text, encoding="utf-8")
PY
}

echo "=============================================="
echo " Wazuh + MISP Full IOC Detection Installer"
echo "=============================================="
echo ""

prompt_tty PREP_DONE "เตรียมเครื่องตาม Lab HTML แล้วหรือยัง? [y/N]: "
prompt_tty SET_HOSTNAME "ตั้ง hostname เป็น wazuh-server อัตโนมัติไหม? [y/N]: "
prompt_tty MISP_URL "MISP URL เช่น https://misp.domain.local: "
prompt_tty MISP_API_KEY "MISP API/Auth Key: "
prompt_tty TELEGRAM_TOKEN "Telegram Bot Token: "
prompt_tty TELEGRAM_CHAT_ID "Telegram Chat ID: "
prompt_tty ENABLE_ACTIVE_RESPONSE "Enable Active Response? [yes/no] (default: yes): "
prompt_tty ACTIVE_RESPONSE_TIMEOUT "Active Response Timeout (default: 600): "

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

EXISTING_FILES=(
  "$INTEGRATION_DIR/custom-misp"
  "$MISP_RULE_FILE"
  "$TELEGRAM_WRAPPER_FILE"
  "$TELEGRAM_PY_FILE"
  "$LINUX_AR_FILE"
  "$WINDOWS_AR_BAT"
  "$WINDOWS_AR_PS1"
)

FOUND_EXISTING=0
for file in "${EXISTING_FILES[@]}"; do
  if [ -f "$file" ]; then
    FOUND_EXISTING=1
    echo "[INFO] พบไฟล์เดิม: $file"
  fi
done

if [ "$FOUND_EXISTING" -eq 1 ]; then
  read -p "พบการติดตั้ง Wazuh MISP Integration เดิมหรือไฟล์ซ้ำในระบบ ต้องการติดตั้งทับหรือไม่? [y/N]: " OVERWRITE_INSTALL
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

for file in "${EXISTING_FILES[@]}"; do
  backup_file_if_exists "$file"
done

echo "[1/12] Install packages"
apt update
apt install -y curl wget python3 python3-pip jq net-tools

echo "[2/12] Download custom-misp"
cd "$INTEGRATION_DIR"

if [ -f custom-misp ]; then
  cp custom-misp "$BACKUP_DIR/custom-misp.bak"
fi

wget -O custom-misp https://raw.githubusercontent.com/klongchu/wazuh-misp-integration/refs/heads/main/custom-misp
chmod 750 custom-misp
chown root:wazuh custom-misp

echo "[3/12] Configure custom-misp"
sed -i "s|^MISP_BASE_URL *=.*|MISP_BASE_URL = \"${MISP_URL}/attributes/restSearch/\"|g" custom-misp || true
sed -i "s|^MISP_API_KEY *=.*|MISP_API_KEY = \"${MISP_API_KEY}\"|g" custom-misp || true

echo "[4/12] Create MISP rules"
cat > "$MISP_RULE_FILE" <<'EOF'
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

chown root:wazuh "$MISP_RULE_FILE"
chmod 660 "$MISP_RULE_FILE"

echo "[5/12] Create local IOC CDB lists"
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

echo "[6/12] Add Wazuh FIM config"
upsert_managed_block "$OSSEC_CONF" "WAZUH_FIM_CONFIGURATION" '  <syscheck>
    <disabled>no</disabled>
    <frequency>43200</frequency>
    <scan_on_start>yes</scan_on_start>
    <alert_new_files>yes</alert_new_files>

    <directories check_all="yes" realtime="yes" report_changes="yes">/etc</directories>
    <directories check_all="yes" realtime="yes" report_changes="yes">/usr/bin</directories>
    <directories check_all="yes" realtime="yes" report_changes="yes">/usr/sbin</directories>
    <directories check_all="yes" realtime="yes" report_changes="yes">/var/www</directories>
    <directories check_all="yes" realtime="yes" report_changes="yes">/home</directories>

    <ignore>/etc/mtab</ignore>
    <ignore>/etc/hosts.deny</ignore>
    <ignore>/etc/mail/statistics</ignore>
    <ignore>/etc/random-seed</ignore>
    <ignore>/etc/.java</ignore>
  </syscheck>'

echo "[7/12] Add MISP integration to ossec.conf"
upsert_managed_block "$OSSEC_CONF" "WAZUH_MISP_INTEGRATION" '  <integration>
    <name>custom-misp</name>
    <group>sysmon_event_1,sysmon_event_3,sysmon_event_6,sysmon_event_7,sysmon_event_22,web,syscheck,</group>
    <alert_format>json</alert_format>
  </integration>'

echo "[8/12] Add Telegram custom integration"
wget -O "$TELEGRAM_WRAPPER_FILE" https://raw.githubusercontent.com/klongchu/wazuh-misp-integration/refs/heads/main/custom-telegram
cat > "$TELEGRAM_PY_FILE" <<EOF
#!/var/ossec/framework/python/bin/python3
import sys
import json
import html
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

def get_misp(alert, key, default="-"):
    v = value(alert, f"misp.{key}", default)
    if v != default:
        return v

    v = value(alert, f"data.misp.{key}", default)
    if v != default:
        return v

    return default

def esc(text):
    return html.escape(str(text))

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

    misp_category = get_misp(alert, "category")
    misp_type = get_misp(alert, "type")
    misp_value = get_misp(alert, "value")
    misp_event_id = get_misp(alert, "event_id")

    message = f"""🚨 <b>Wazuh MISP Alert</b>

<b>Rule ID:</b> {esc(rule_id)}
<b>Level:</b> {esc(level)}
<b>Description:</b> {esc(description)}

<b>Agent:</b> {esc(agent_name)}
<b>IP:</b> {esc(agent_ip)}
<b>Location:</b> {esc(location)}

<b>MISP Category:</b> {esc(misp_category)}
<b>MISP Type:</b> {esc(misp_type)}
<b>IOC:</b> {esc(misp_value)}
<b>MISP Event ID:</b> {esc(misp_event_id)}
"""

    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"

    payload = {
        "chat_id": CHAT_ID,
        "text": message,
        "parse_mode": "HTML",
        "disable_web_page_preview": True
    }

    response = requests.post(url, json=payload, timeout=10)

    if response.status_code != 200:
        print(f"Telegram API Error: {response.status_code} {response.text}")

except Exception as e:
    print(f"Telegram integration error: {e}")
EOF
chmod 750 "$TELEGRAM_WRAPPER_FILE" "$TELEGRAM_PY_FILE"
chown root:wazuh "$TELEGRAM_WRAPPER_FILE" "$TELEGRAM_PY_FILE"

upsert_managed_block "$OSSEC_CONF" "WAZUH_TELEGRAM_INTEGRATION" '  <integration>
    <name>custom-telegram</name>
    <rule_id>100800,100801,100802,100803,100804,100805</rule_id>
    <alert_format>json</alert_format>
  </integration>'

echo "[9/12] Create Linux Active Response script"
cat > "$LINUX_AR_FILE" <<'EOF'
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

chmod 750 "$LINUX_AR_FILE"
chown root:wazuh "$LINUX_AR_FILE"

if [ "$ENABLE_ACTIVE_RESPONSE" = "yes" ]; then
  upsert_managed_block "$OSSEC_CONF" "WAZUH_MISP_ACTIVE_RESPONSE" "  <command>
    <name>block-misp-ioc</name>
    <executable>block-misp-ioc.sh</executable>
    <timeout_allowed>yes</timeout_allowed>
  </command>

  <active-response>
    <command>block-misp-ioc</command>
    <location>local</location>
    <rules_id>100801</rules_id>
    <timeout>${ACTIVE_RESPONSE_TIMEOUT}</timeout>
  </active-response>"
fi

echo "[10/12] Create Windows Active Response files"
mkdir -p "$WINDOWS_AR_DIR"

cat > "$WINDOWS_AR_BAT" <<'EOF'
@echo off
powershell.exe -ExecutionPolicy Bypass -File "C:\Program Files (x86)\ossec-agent\active-response\bin\block-malicious.ps1"
EOF

cat > "$WINDOWS_AR_PS1" <<'EOF'
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

echo "[11/12] Verify/Create Sysmon Event ID 22 rule"
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

echo "[12/12] Validate and restart Wazuh"
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
echo "Rules: $MISP_RULE_FILE"
echo "MISP Integration: $INTEGRATION_DIR/custom-misp"
echo "Telegram Integration: $TELEGRAM_PY_FILE"
echo "Linux Active Response: $LINUX_AR_FILE"
echo "Windows AR files: $WINDOWS_AR_DIR/"
echo ""
echo "ตรวจสอบ:"
echo "systemctl status wazuh-manager"
echo "tail -f /var/ossec/logs/ossec.log"
echo "tail -f /var/ossec/logs/alerts/alerts.json"
echo "=============================================="