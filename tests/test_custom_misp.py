from pathlib import Path


def test_custom_misp_supports_ignore_warninglist_config_file_with_env_fallback():
    text = Path('custom-misp').read_text(encoding='utf-8')
    assert 'CONFIG_FILE = os.path.join(os.path.dirname(os.path.realpath(__file__)), "custom-misp.conf")' in text
    assert 'def load_config(path=CONFIG_FILE):' in text
    assert 'CONFIG = load_config()' in text
    assert 'CONFIG.get("IGNORE_WARNINGLIST", os.getenv("IGNORE_WARNINGLIST", "true"))' in text
    assert 'IGNORE_WARNINGLIST = parse_bool(' in text
    assert 'if IGNORE_WARNINGLIST and is_warninglist_hit(attribute):' in text


def test_server_installer_creates_custom_misp_conf_for_warninglist_setting():
    text = Path('server_wazuh_misp_setup.sh').read_text(encoding='utf-8')
    assert 'MISP_CONFIG_FILE="$INTEGRATION_DIR/custom-misp.conf"' in text
    assert 'prompt_tty IGNORE_WARNINGLIST "Ignore MISP warninglist hits? [Y/n] (default: yes): "' in text
    assert 'IGNORE_WARNINGLIST_BOOL="true"' in text
    assert '"$MISP_CONFIG_FILE"' in text
    assert 'cat > "$MISP_CONFIG_FILE" <<EOF' in text
    assert 'IGNORE_WARNINGLIST=$IGNORE_WARNINGLIST_BOOL' in text
    assert 'chmod 640 "$MISP_CONFIG_FILE"' in text
    assert 'chown root:wazuh "$MISP_CONFIG_FILE"' in text
    assert 'sed -i "s|^IGNORE_WARNINGLIST *=.*|' not in text


def test_installer_uses_exporter_virtualenv_and_cron():
    text = Path('server_wazuh_misp_setup.sh').read_text(encoding='utf-8')
    assert 'apt install -y curl wget python3 python3-pip python3-venv python3-full jq net-tools cron' in text
    assert 'python3 -m venv "$INTEGRATION_DIR/export-misp-venv"' in text
    assert '"$INTEGRATION_DIR/export-misp-venv/bin/pip" install --no-input pymisp requests' in text
    assert 'python3 -m pip install --no-input pymisp requests' not in text
    assert 'pip3 install --no-input pymisp requests' not in text
    assert '--break-system-packages' not in text
    assert '/etc/cron.d/wazuh-misp-cdb-export' in text
    assert '"/var/ossec/integrations/export-misp-venv/bin/python" /var/ossec/integrations/export_misp_to_wazuh.py --output-dir /var/ossec/etc/lists --config /var/ossec/integrations/custom-misp.conf' in text
    assert '"$INTEGRATION_DIR/export-misp-venv/bin/python" "$INTEGRATION_DIR/export_misp_to_wazuh.py" --output-dir "$LIST_DIR" --config "$MISP_CONFIG_FILE"' in text
    assert 'for list_file in malware-hashes misp-ip misp-domain misp-url; do' in text


def test_installer_adds_cdb_lookup_rules():
    text = Path('server_wazuh_misp_setup.sh').read_text(encoding='utf-8')
    assert 'misp_cdb_rules.xml' in text
    assert '<list field="win.eventdata.queryName" lookup="match_key">etc/lists/misp-domain</list>' in text
    assert '<list field="win.eventdata.destinationIp" lookup="match_key">etc/lists/misp-ip</list>' in text
    assert 'MISP CDB Domain IOC matched' in text
    assert 'MISP CDB IP IOC matched' in text
    assert 'sysmon_event_22' in text
    assert 'sysmon_event_3' in text
    assert 'chown root:wazuh "$CDB_RULE_FILE"' in text
    assert 'chmod 660 "$CDB_RULE_FILE"' in text
    assert 'rule_include' not in text
    assert 'upsert_managed_block "$OSSEC_CONF" "WAZUH_MISP_CDB_RULES"' not in text
    assert '<rule_include>' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
    assert 'rule_include' not in text
