#!/bin/bash
set -e

TMP_DIR="${TMPDIR:-/tmp}/wazuh-issabel-setup.$$"
INTEGRATION_DIR="/var/ossec/integrations"
SCRIPT_PATH="$INTEGRATION_DIR/wazuh_issabel_alert_call.py"
ENV_FILE="${ENV_FILE:-/var/ossec/etc/wazuh-issabel-alert-call.env}"

mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

prompt_value() {
  local var_name="$1"
  local prompt_text="$2"
  local default_value="${3:-}"
  local secret="${4:-no}"
  local current_value="${!var_name:-$default_value}"
  local input_value=""

  if [ -n "$current_value" ]; then
    prompt_text="$prompt_text [$current_value]"
  fi

  if [ "$secret" = "yes" ]; then
    read -r -s -p "$prompt_text: " input_value
    echo ""
  else
    read -r -p "$prompt_text: " input_value
  fi

  if [ -z "$input_value" ]; then
    input_value="$current_value"
  fi

  printf -v "$var_name" '%s' "$input_value"
}

write_env_file() {
  install -d "$(dirname "$ENV_FILE")"
  cat > "$ENV_FILE" <<EOF
ALERT_LEVEL_THRESHOLD="$ALERT_LEVEL_THRESHOLD"
ALERT_REQUIRED_GROUPS="$ALERT_REQUIRED_GROUPS"
ALERT_CALL_COOLDOWN="$ALERT_CALL_COOLDOWN"
TARGET_NUMBER="$TARGET_NUMBER"
ISSABEL_HOST="$ISSABEL_HOST"
ISSABEL_PORT="$ISSABEL_PORT"
AMI_USER="$AMI_USER"
AMI_PASS="$AMI_PASS"
ASTERISK_CHANNEL_PREFIX="$ASTERISK_CHANNEL_PREFIX"
ASTERISK_CONTEXT="$ASTERISK_CONTEXT"
ASTERISK_EXTEN="$ASTERISK_EXTEN"
ASTERISK_PRIORITY="$ASTERISK_PRIORITY"
ASTERISK_CALLERID="$ASTERISK_CALLERID"
ASTERISK_TIMEOUT_MS="$ASTERISK_TIMEOUT_MS"
ISSABEL_SOCKET_TIMEOUT="$ISSABEL_SOCKET_TIMEOUT"
ISSABEL_STATE_FILE="$ISSABEL_STATE_FILE"
ISSABEL_LOG_FILE="$ISSABEL_LOG_FILE"
EOF
  chmod 600 "$ENV_FILE"
}

if [ -f "$ENV_FILE" ]; then
  echo "[INFO] Load config from $ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

ALERT_LEVEL_THRESHOLD="${ALERT_LEVEL_THRESHOLD:-12}"
ALERT_REQUIRED_GROUPS="${ALERT_REQUIRED_GROUPS:-sysmon_event_3,authentication_failed}"
ALERT_CALL_COOLDOWN="${ALERT_CALL_COOLDOWN:-600}"
ISSABEL_PORT="${ISSABEL_PORT:-5038}"
ASTERISK_CHANNEL_PREFIX="${ASTERISK_CHANNEL_PREFIX:-Local}"
ASTERISK_CONTEXT="${ASTERISK_CONTEXT:-from-internal}"
ASTERISK_EXTEN="${ASTERISK_EXTEN:-}"
ASTERISK_PRIORITY="${ASTERISK_PRIORITY:-1}"
ASTERISK_CALLERID="${ASTERISK_CALLERID:-WAZUH-ALERT <9999>}"
ASTERISK_TIMEOUT_MS="${ASTERISK_TIMEOUT_MS:-30000}"
ISSABEL_SOCKET_TIMEOUT="${ISSABEL_SOCKET_TIMEOUT:-10}"
ISSABEL_STATE_FILE="${ISSABEL_STATE_FILE:-/var/ossec/tmp/issabel-call-state.json}"
ISSABEL_LOG_FILE="${ISSABEL_LOG_FILE:-/var/ossec/logs/issabel-call.log}"

if [ "${NONINTERACTIVE:-0}" != "1" ]; then
  prompt_value TARGET_NUMBER "Target phone number"
  prompt_value ISSABEL_HOST "Issabel/Asterisk host"
  prompt_value ISSABEL_PORT "Issabel AMI port" "5038"
  prompt_value AMI_USER "AMI username"
  prompt_value AMI_PASS "AMI password" "" "yes"
  prompt_value ALERT_LEVEL_THRESHOLD "Minimum Wazuh alert level" "12"
  prompt_value ALERT_REQUIRED_GROUPS "Allowed Wazuh rule groups, comma-separated" "sysmon_event_3,authentication_failed"
  prompt_value ALERT_CALL_COOLDOWN "Cooldown seconds" "600"
  prompt_value ASTERISK_CHANNEL_PREFIX "Asterisk channel prefix" "Local"
  prompt_value ASTERISK_CONTEXT "Asterisk context" "from-internal"
  prompt_value ASTERISK_EXTEN "Asterisk extension, blank uses TARGET_NUMBER" ""
  prompt_value ASTERISK_PRIORITY "Asterisk priority" "1"
  prompt_value ASTERISK_CALLERID "Asterisk caller ID" "WAZUH-ALERT <9999>"
fi

if [ -z "${TARGET_NUMBER:-}" ] || [ -z "${ISSABEL_HOST:-}" ] || [ -z "${AMI_USER:-}" ] || [ -z "${AMI_PASS:-}" ]; then
  echo "[ERROR] TARGET_NUMBER, ISSABEL_HOST, AMI_USER, AMI_PASS ห้ามว่าง"
  exit 1
fi

write_env_file

curl -fsSL https://raw.githubusercontent.com/klongchu/wazuh-misp-integration/main/wazuh_issabel_alert_call.py -o "$TMP_DIR/wazuh_issabel_alert_call.py"
install -d "$INTEGRATION_DIR"
install -m 750 "$TMP_DIR/wazuh_issabel_alert_call.py" "$SCRIPT_PATH"

cat <<EOF
[INFO] Installed: $SCRIPT_PATH
[INFO] Config saved: $ENV_FILE
[INFO] Test command:
  set -a && . "$ENV_FILE" && set +a && python3 "$SCRIPT_PATH" --stdin-file alert.json
[INFO] Next step:
  wire script into Wazuh integration or active-response flow and load $ENV_FILE before execution
EOF
