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


def test_installer_mentions_exporter_and_cron():
    text = Path('server_wazuh_misp_setup.sh').read_text(encoding='utf-8')
    assert 'export_misp_to_wazuh.py' in text
    assert 'python3 -m pip install --no-input pymisp requests' in text or 'pip install pymisp requests' in text
    assert '/etc/cron.d/wazuh-misp-cdb-export' in text
    assert '/var/ossec/etc/lists/malware-hashes' in text
    assert '/var/ossec/etc/lists/misp-ip' in text
    assert '/var/ossec/etc/lists/misp-domain' in text
    assert '/var/ossec/etc/lists/misp-url' in text
    assert 'systemctl enable --now cron || true' in text
    assert 'MISP_BASE_URL="$MISP_URL/attributes/restSearch/" MISP_API_KEY="$MISP_API_KEY" /var/ossec/integrations/export_misp_to_wazuh.py --output-dir /var/ossec/etc/lists' in text
