import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "server_wazuh_misp_setup.sh"


def read_script():
    return SCRIPT.read_text(encoding="utf-8")


def line_no(text, needle):
    for idx, line in enumerate(text.splitlines(), start=1):
        if needle in line:
            return idx
    raise AssertionError(f"Missing expected text: {needle}")


def test_env_file_written_before_root_guard():
    text = read_script()
    env_write = line_no(text, 'cat > "$ENV_FILE" <<EOF')
    root_check = line_no(text, 'if [ "$EUID" -ne 0 ]; then')
    assert env_write < root_check


def test_telegram_values_are_required_in_current_installer_flow():
    text = read_script()
    required_check = re.search(
        r'if \[ -z "\$MISP_URL" \] \|\| \[ -z "\$MISP_API_KEY" \] \|\| \[ -z "\$TELEGRAM_TOKEN" \] \|\| \[ -z "\$TELEGRAM_CHAT_ID" \]; then',
        text,
    )
    assert required_check, "combined required-value check missing"
    assert 'Telegram Bot Token:' in text
    assert 'Telegram Chat ID:' in text


def test_existing_files_are_backed_up_after_ossec_check():
    text = read_script()
    ossec_check = line_no(text, 'if [ ! -d "$OSSEC_DIR" ]; then')
    backup_dir_create = line_no(text, 'mkdir -p "$BACKUP_DIR"')
    backup_call = line_no(text, 'backup_file_if_exists "$file"')
    assert ossec_check < backup_dir_create < backup_call

    ossec_index = text.index('if [ ! -d "$OSSEC_DIR" ]; then')
    backup_index = text.index('backup_file_if_exists "$file"')
    assert ossec_index < backup_index


def test_custom_misp_config_is_updated_by_sed_and_runtime_config_file():
    text = read_script()
    assert 'sed -i "s|^MISP_BASE_URL *=.*|MISP_BASE_URL = \\"${MISP_URL}/attributes/restSearch/\\"|g" custom-misp || true' in text
    assert 'sed -i "s|^MISP_API_KEY *=.*|MISP_API_KEY = \\"${MISP_API_KEY}\\"|g" custom-misp || true' in text
    assert 'cat > "$MISP_CONFIG_FILE" <<EOF' in text
    assert 'IGNORE_WARNINGLIST=$IGNORE_WARNINGLIST_BOOL' in text


def test_cdb_lists_are_created_and_registered():
    text = read_script()
    assert 'for list_file in malware-hashes misp-ip misp-domain misp-url; do' in text
    assert 'touch "$LIST_DIR/$list_file"' in text
    assert 'if ! grep -q "etc/lists/malware-hashes" "$OSSEC_CONF"; then' in text
    assert '<list>etc/lists/malware-hashes</list>' in text
    assert '<list>etc/lists/misp-ip</list>' in text
    assert '<list>etc/lists/misp-domain</list>' in text
    assert '<list>etc/lists/misp-url</list>' in text


def test_linux_active_response_uses_current_shell_parser():
    text = read_script()
    ar_start = line_no(text, 'cat > "$LINUX_AR_FILE" <<\'EOF\'')
    ar_end = line_no(text, 'chmod 750 "$LINUX_AR_FILE"')
    ar_block = "\n".join(text.splitlines()[ar_start - 1:ar_end - 1])
    assert 'IOC=$(echo "$INPUT_JSON" | grep -oP' in ar_block
    assert 'iptables -I INPUT -s "$IOC" -j DROP || true' in ar_block
    assert 'iptables -D OUTPUT -d "$IOC" -j DROP || true' in ar_block


def test_server_script_generates_windows_artifacts_for_manual_agent_install():
    text = read_script()
    assert 'Create Windows Active Response files' in text
    assert 'WINDOWS_AR_BAT' in text
    assert 'WINDOWS_AR_PS1' in text
    assert 'WINDOWS_FIM_FILE' in text
    assert 'Apply file to Windows agent ossec.conf under <ossec_config>' in text


def test_script_uses_base_url_for_exporter_and_restsearch_for_custom_misp():
    text = read_script()
    assert 'export MISP_BASE_URL="$MISP_URL"' in text
    assert '^MISP_BASE_URL *=.*' in text
    assert '${MISP_URL}/attributes/restSearch/' in text
    assert 'custom-misp || true' in text


def test_script_uses_event_id_field_for_cdb_ip_rule_not_missing_group():
    text = read_script()
    assert '<field name="win.system.eventID">^3$</field>' in text
    assert '<if_group>sysmon_event_3</if_group>' not in text


def test_custom_misp_still_handles_sysmon_event_3_alert_groups():
    text = (ROOT / "custom-misp").read_text(encoding="utf-8")
    assert 'if "sysmon_event_3" in group_set:' in text
    assert 'destinationIp' in text
    assert 'DestinationIp' in text
    assert 'destinationIsIpv6' in text
    assert 'win.system.eventID' not in text
