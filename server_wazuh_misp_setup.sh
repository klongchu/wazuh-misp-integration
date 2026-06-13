#!/bin/bash
# Boundary map for refactoring:
# - Shared/reusable logic: backup, prompt, managed config block updates, validation helpers
# - Server-specific logic: MISP/custom-misp, ossec.conf, rules, lists, Telegram, active response, Windows artifact generation, Sysmon rule handling.
set -e

# ======================================================
# Wazuh + MISP IOC Detection Full Setup
# For Wazuh Manager Ubuntu
# ======================================================
#
# Refactor map for later core + wrapper split:
# - Core Logic: shared path setup, backup helpers, prompt helpers, managed config block updates,
#   env persistence, existing-file checks, and final validation/restart flow.
# - Server Role Logic: Wazuh manager package install, MISP integration, rules, lists, Telegram,
#   Linux active response, Windows artifact generation, and Sysmon rule handling.
#
# ===== Core Logic: shared paths and helper functions =====

OSSEC_DIR="/var/ossec"
OSSEC_CONF="$OSSEC_DIR/etc/ossec.conf"
RULE_DIR="$OSSEC_DIR/etc/rules"
DECODER_DIR="$OSSEC_DIR/etc/decoders"
INTEGRATION_DIR="$OSSEC_DIR/integrations"
LIST_DIR="$OSSEC_DIR/etc/lists"
AR_DIR="$OSSEC_DIR/active-response/bin"

BACKUP_DIR="/root/wazuh-misp-backup-$(date +%F-%H%M%S)"
MISP_RULE_FILE="$RULE_DIR/misp.xml"
CDB_RULE_FILE="$RULE_DIR/misp_cdb_rules.xml"
SYSMON_RULES_FILE="$OSSEC_DIR/ruleset/rules/0595-win-sysmon_rules.xml"
TELEGRAM_WRAPPER_FILE="$INTEGRATION_DIR/custom-telegram"
TELEGRAM_PY_FILE="$INTEGRATION_DIR/custom-telegram.py"
MISP_CONFIG_FILE="$INTEGRATION_DIR/custom-misp.conf"
LINUX_AR_FILE="$AR_DIR/block-misp-ioc.sh"
WINDOWS_AR_DIR="/root/wazuh-windows-active-response"
WINDOWS_AR_BAT="$WINDOWS_AR_DIR/action-script.bat"
WINDOWS_AR_PS1="$WINDOWS_AR_DIR/block-malicious.ps1"
WINDOWS_FIM_FILE="$WINDOWS_AR_DIR/windows-fim-ossec.conf"
ENV_FILE="${ENV_FILE:-./wazuh-misp.env}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_CUSTOM_MISP="$SCRIPT_DIR/custom-misp"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/wazuh_misp_common.sh"


echo "=============================================="
echo " Wazuh + MISP Full IOC Detection Installer"
echo "=============================================="
echo ""

if [ -f "$ENV_FILE" ]; then
  echo "[INFO] Load config from $ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a

  RECONFIGURE_ENV="${RECONFIGURE_ENV:-}"
  if [ -z "$RECONFIGURE_ENV" ]; then
    prompt_tty RECONFIGURE_ENV "ต้องการแก้ไขค่า config/env หรือไม่? [y/N]: "
  fi

  if [[ "$RECONFIGURE_ENV" =~ ^[Yy]$ ]]; then
    unset SET_HOSTNAME MISP_URL MISP_API_KEY TELEGRAM_TOKEN TELEGRAM_CHAT_ID ENABLE_ACTIVE_RESPONSE ACTIVE_RESPONSE_TIMEOUT IGNORE_WARNINGLIST
  fi
fi

if [ -z "$SET_HOSTNAME" ]; then
  prompt_tty SET_HOSTNAME "ตั้ง hostname เป็น wazuh-server อัตโนมัติไหม? [y/N]: "
fi
if [ -z "$MISP_URL" ]; then
  prompt_tty MISP_URL "MISP URL เช่น https://misp.domain.local: "
fi
if [ -z "$MISP_API_KEY" ]; then
  prompt_tty MISP_API_KEY "MISP API/Auth Key: "
fi
if [ -z "$TELEGRAM_TOKEN" ]; then
  prompt_tty TELEGRAM_TOKEN "Telegram Bot Token: "
fi
if [ -z "$TELEGRAM_CHAT_ID" ]; then
  prompt_tty TELEGRAM_CHAT_ID "Telegram Chat ID: "
fi
if [ -z "$ENABLE_ACTIVE_RESPONSE" ]; then
  prompt_tty ENABLE_ACTIVE_RESPONSE "Enable Active Response? [yes/no] (default: yes): "
fi
if [ -z "$ACTIVE_RESPONSE_TIMEOUT" ]; then
  prompt_tty ACTIVE_RESPONSE_TIMEOUT "Active Response Timeout (default: 600): "
fi
if [ -z "$IGNORE_WARNINGLIST" ]; then
  prompt_tty IGNORE_WARNINGLIST "Ignore MISP warninglist hits? [Y/n] (default: yes): "
fi

echo ""

MISP_URL="${MISP_URL%/}"
ENABLE_ACTIVE_RESPONSE="${ENABLE_ACTIVE_RESPONSE:-yes}"
ACTIVE_RESPONSE_TIMEOUT="${ACTIVE_RESPONSE_TIMEOUT:-600}"
IGNORE_WARNINGLIST="${IGNORE_WARNINGLIST:-yes}"
SET_HOSTNAME="${SET_HOSTNAME:-N}"

# Convert to boolean string for custom-misp.conf
IGNORE_WARNINGLIST_BOOL="false"
if [[ "$IGNORE_WARNINGLIST" =~ ^[Yy]([Ee][Ss])?$|^1$|^true$|^on$ ]]; then
  IGNORE_WARNINGLIST_BOOL="true"
fi

if [ -z "$MISP_URL" ] || [ -z "$MISP_API_KEY" ] || [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
  echo "[ERROR] MISP URL, API Key, Telegram Token, Telegram Chat ID ห้ามว่าง"
  exit 1
fi

cat > "$ENV_FILE" <<EOF
SET_HOSTNAME="$SET_HOSTNAME"
MISP_URL="$MISP_URL"
MISP_API_KEY="$MISP_API_KEY"
TELEGRAM_TOKEN="$TELEGRAM_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
ENABLE_ACTIVE_RESPONSE="$ENABLE_ACTIVE_RESPONSE"
ACTIVE_RESPONSE_TIMEOUT="$ACTIVE_RESPONSE_TIMEOUT"
IGNORE_WARNINGLIST="$IGNORE_WARNINGLIST_BOOL"
EOF
chmod 600 "$ENV_FILE"
echo "[INFO] Save config to $ENV_FILE"

if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] กรุณารันด้วย sudo หรือ root"
  exit 1
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
  "$MISP_CONFIG_FILE"
  "$MISP_RULE_FILE"
  "$CDB_RULE_FILE"
  "$TELEGRAM_WRAPPER_FILE"
  "$TELEGRAM_PY_FILE"
  "$LINUX_AR_FILE"
  "$WINDOWS_AR_BAT"
  "$WINDOWS_AR_PS1"
  "$ENV_FILE"
)

DELETE_ON_UPDATE_FILES=()
FOUND_EXISTING=0
for file in "${EXISTING_FILES[@]}"; do
  if [ -f "$file" ]; then
    FOUND_EXISTING=1
    echo "[INFO] พบไฟล์เดิม: $file"
    prompt_tty UPDATE_FILE "ต้องการอัปเดต $file หรือไม่? [y/N]: "
    UPDATE_FILE="${UPDATE_FILE:-N}"
    if [[ "$UPDATE_FILE" =~ ^[Yy]$ ]]; then
      DELETE_ON_UPDATE_FILES+=("$file")
    else
      echo "[INFO] ยกเลิกการติดตั้ง"
      exit 0
    fi
  fi
done

if [ ! -d "$OSSEC_DIR" ]; then
  echo "[ERROR] ไม่พบ $OSSEC_DIR กรุณาติดตั้ง Wazuh Manager ก่อน"
  exit 1
fi

mkdir -p "$BACKUP_DIR"
cp "$OSSEC_CONF" "$BACKUP_DIR/ossec.conf.bak"

for file in "${EXISTING_FILES[@]}"; do
  backup_file_if_exists "$file"
done

for file in "${DELETE_ON_UPDATE_FILES[@]}"; do
  rm -f "$file"
done
if [ ${#DELETE_ON_UPDATE_FILES[@]} -gt 0 ]; then
  echo "[INFO] ลบไฟล์เดิมแล้ว พร้อมสร้างใหม่"
fi

echo "[1/12] Install packages"
apt update
apt install -y curl wget python3 python3-pip python3-venv python3-full jq net-tools cron

echo "[2/12] Install export_misp_to_wazuh.py"
if [ -f "$SCRIPT_DIR/export_misp_to_wazuh.py" ]; then
  cp "$SCRIPT_DIR/export_misp_to_wazuh.py" "$INTEGRATION_DIR/export_misp_to_wazuh.py"
else
  wget -O "$INTEGRATION_DIR/export_misp_to_wazuh.py" https://raw.githubusercontent.com/klongchu/wazuh-misp-integration/main/export_misp_to_wazuh.py
fi
chmod 750 "$INTEGRATION_DIR/export_misp_to_wazuh.py"
chown root:wazuh "$INTEGRATION_DIR/export_misp_to_wazuh.py"

export_misp_venv="$INTEGRATION_DIR/export-misp-venv"
python3 -m venv "$INTEGRATION_DIR/export-misp-venv"
"$INTEGRATION_DIR/export-misp-venv/bin/pip" install --no-input requests

cat > /etc/cron.d/wazuh-misp-cdb-export <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
*/30 * * * * root MISP_BASE_URL="$MISP_URL" MISP_API_KEY="$MISP_API_KEY" "/var/ossec/integrations/export-misp-venv/bin/python" /var/ossec/integrations/export_misp_to_wazuh.py --output-dir /var/ossec/etc/lists --config /var/ossec/integrations/custom-misp.conf >> /var/ossec/logs/integrations.log 2>&1
EOF
chmod 644 /etc/cron.d/wazuh-misp-cdb-export
systemctl enable --now cron || true

rm -f /var/ossec/etc/lists/malware-hashes /var/ossec/etc/lists/misp-ip /var/ossec/etc/lists/misp-domain /var/ossec/etc/lists/misp-url

for list_file in malware-hashes misp-ip misp-domain misp-url; do
  touch "$LIST_DIR/$list_file"
  chown wazuh:wazuh "$LIST_DIR/$list_file"
  chmod 660 "$LIST_DIR/$list_file"
done

if ! grep -q "etc/lists/malware-hashes" "$OSSEC_CONF"; then
  sed -i '/<ruleset>/a\    <list>etc/lists/malware-hashes</list>\n    <list>etc/lists/misp-ip</list>\n    <list>etc/lists/misp-domain</list>\n    <list>etc/lists/misp-url</list>' "$OSSEC_CONF"
fi

export MISP_BASE_URL="$MISP_URL"
export MISP_API_KEY="$MISP_API_KEY"
"$INTEGRATION_DIR/export-misp-venv/bin/python" "$INTEGRATION_DIR/export_misp_to_wazuh.py" --output-dir "$LIST_DIR" --config "$MISP_CONFIG_FILE" || true

cat > "$CDB_RULE_FILE" <<'EOF'
<group name="misp,cdb,ioc,">

  <rule id="100900" level="12">
    <if_group>sysmon_event_22</if_group>
    <list field="win.eventdata.queryName" lookup="match_key">etc/lists/misp-domain</list>
    <description>MISP CDB Domain IOC matched: $(win.eventdata.queryName)</description>
    <group>misp_domain,cdb_ioc,dns,</group>
  </rule>

  <rule id="100901" level="12">
    <field name="win.system.eventID">^3$</field>
    <list field="win.eventdata.destinationIp" lookup="match_key">etc/lists/misp-ip</list>
    <description>MISP CDB IP IOC matched: $(win.eventdata.destinationIp)</description>
    <group>misp_ip,cdb_ioc,network,</group>
  </rule>

</group>
EOF
chown root:wazuh "$CDB_RULE_FILE"
chmod 660 "$CDB_RULE_FILE"


echo "[2/12] Install custom-misp"
cd "$INTEGRATION_DIR"

if [ -f custom-misp ]; then
  cp custom-misp "$BACKUP_DIR/custom-misp.bak"
fi

if [ -f "$LOCAL_CUSTOM_MISP" ]; then
  echo "[INFO] ใช้ custom-misp จาก $LOCAL_CUSTOM_MISP"
  cp "$LOCAL_CUSTOM_MISP" custom-misp
else
  echo "[WARN] ไม่พบ $LOCAL_CUSTOM_MISP ใช้ fallback download"
  wget -O custom-misp https://raw.githubusercontent.com/klongchu/wazuh-misp-integration/refs/heads/main/custom-misp
fi

chmod 750 custom-misp
chown root:wazuh custom-misp

echo "[3/12] Configure custom-misp"
sed -i "s|^MISP_BASE_URL *=.*|MISP_BASE_URL = \"${MISP_URL}/attributes/restSearch/\"|g" custom-misp || true
sed -i "s|^MISP_API_KEY *=.*|MISP_API_KEY = \"${MISP_API_KEY}\"|g" custom-misp || true

cat > "$MISP_CONFIG_FILE" <<EOF
# custom-misp runtime configuration
MISP_BASE_URL=$MISP_URL
MISP_API_KEY=$MISP_API_KEY
IGNORE_WARNINGLIST=$IGNORE_WARNINGLIST_BOOL
EOF
chmod 640 "$MISP_CONFIG_FILE"
chown root:wazuh "$MISP_CONFIG_FILE"

echo "[4/12] Create MISP rules"
cat > "$MISP_RULE_FILE" <<'EOF'
<group name="misp,threat_intel,ioc,">

  <rule id="100620" level="3">
    <decoded_as>json</decoded_as>
    <field name="integration">misp</field>
    <match>MISP - Error connecting to API</match>
    <description>MISP - Error connecting to API</description>
    <options>no_full_log</options>
    <group>misp_error,</group>
  </rule>

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

  <rule id="100806" level="12">
    <if_sid>100800</if_sid>
    <description>MISP - IoC found in Threat Intel - Category: $(misp.category), Attribute: $(misp.value)</description>
    <options>no_full_log</options>
    <group>misp_alert,</group>
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
    <client_buffer_size>300000</client_buffer_size>

    <directories check_all="yes" realtime="yes" report_changes="yes">/usr/bin</directories>
    <directories check_all="yes" realtime="yes" report_changes="yes">/usr/sbin</directories>
    <directories check_all="yes" realtime="yes" report_changes="yes">/var/www</directories>

    <ignore>/etc/mtab</ignore>
    <ignore>/etc/hosts.deny</ignore>
    <ignore>/etc/mail/statistics</ignore>
    <ignore>/etc/random-seed</ignore>
    <ignore>/etc/.java</ignore>
    <ignore>/home</ignore>
  </syscheck>'

echo "[7/12] Add MISP integration to ossec.conf"
upsert_managed_block "$OSSEC_CONF" "WAZUH_MISP_INTEGRATION" '  <integration>
    <name>custom-misp</name>
    <group>sysmon_event_1,sysmon_event_3,sysmon_event_6,sysmon_event_7,sysmon_event_15,sysmon_event_22,syscheck</group>
    <alert_format>json</alert_format>
  </integration>'

echo "[8/12] Add Telegram custom integration"
cat > "$TELEGRAM_WRAPPER_FILE" <<EOF
#!/var/ossec/framework/python/bin/python3
import sys
import os
import json
import html
import requests

BOT_TOKEN = os.getenv("TELEGRAM_TOKEN", "${TELEGRAM_TOKEN}").strip()
CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "${TELEGRAM_CHAT_ID}").strip()

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
chmod 750 "$TELEGRAM_WRAPPER_FILE"
chown root:wazuh "$TELEGRAM_WRAPPER_FILE"
rm -f "$TELEGRAM_PY_FILE"

upsert_managed_block "$OSSEC_CONF" "WAZUH_TELEGRAM_INTEGRATION" '  <integration>
    <name>custom-telegram</name>
    <level>12</level>
    <alert_format>json</alert_format>
  </integration>'

echo "[INFO] Telegram Integration: $TELEGRAM_WRAPPER_FILE"

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

cat > "$WINDOWS_FIM_FILE" <<'EOF'
<syscheck>
  <disabled>no</disabled>
  <frequency>43200</frequency>
  <scan_on_start>yes</scan_on_start>
  <alert_new_files>yes</alert_new_files>

  <directories check_all="yes" realtime="yes" report_changes="yes">C:\Windows\System32\drivers\etc</directories>
  <directories check_all="yes" realtime="yes" report_changes="yes">C:\Windows\System32\WindowsPowerShell\v1.0\Modules</directories>
  <directories check_all="yes" realtime="yes" report_changes="yes">C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup</directories>
  <directories check_all="yes" realtime="yes" report_changes="yes">C:\Users\Public</directories>
  <directories check_all="yes" realtime="yes" report_changes="yes">C:\Users\*\Downloads</directories>

  <ignore>C:\Windows\Temp</ignore>
  <ignore>C:\Windows\Prefetch</ignore>
  <ignore>C:\Windows\WinSxS</ignore>
  <ignore>C:\Windows\SoftwareDistribution</ignore>
</syscheck>
EOF

cat <<EOF
[INFO] Windows FIM config saved: $WINDOWS_FIM_FILE
[INFO] Apply file to Windows agent ossec.conf under <ossec_config>
EOF

echo "[11/12] Patch Sysmon - Event 3 and Sysmon - Event 22 levels"
backup_file_if_exists "$SYSMON_RULES_FILE"
python3 - <<'PY' "$SYSMON_RULES_FILE"
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
patterns = [
    (r'(<rule id="61603" level=")0(">)', r'\g<1>4\g<2>'),
    (r'(<rule id="61650" level=")0(">)', r'\g<1>4\g<2>'),
]
updated = text
for pattern, replacement in patterns:
    updated = re.sub(pattern, replacement, updated)
path.write_text(updated, encoding='utf-8')
PY

if ! grep -q '<rule id="61603" level="4">' "$SYSMON_RULES_FILE"; then
  echo "[ERROR] Failed to patch Sysmon - Event 3 level"
  exit 1
fi
if ! grep -q '<rule id="61650" level="4">' "$SYSMON_RULES_FILE"; then
  echo "[ERROR] Failed to patch Sysmon - Event 22 level"
  exit 1
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
echo "Telegram Integration: $TELEGRAM_WRAPPER_FILE"
echo "Linux Active Response: $LINUX_AR_FILE"
echo "Windows AR files: $WINDOWS_AR_DIR/"
echo ""
echo "ตรวจสอบ:"
echo "systemctl status wazuh-manager"
echo "tail -f /var/ossec/logs/ossec.log"
echo "tail -f /var/ossec/logs/alerts/alerts.json"
echo "=============================================="
