import pytest
import os
from pathlib import Path
import importlib.util

# Dynamically load the script as a module
spec = importlib.util.spec_from_file_location("export_misp_to_wazuh", "export_misp_to_wazuh.py")
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)

# Now, access the functions through the loaded module
map_attribute_to_list = exporter.map_attribute_to_list
write_lists = exporter.write_lists # Also expose write_lists for Task 2


def test_map_attribute_to_list_routes_ioc_types():
    assert map_attribute_to_list({"type": "md5", "value": "a"}) == ("malware-hashes", "a")
    assert map_attribute_to_list({"type": "ip-dst", "value": "8.8.8.8"}) == ("misp-ip", "8.8.8.8")
    assert map_attribute_to_list({"type": "domain", "value": "Example.COM."}) == ("misp-domain", "example.com")
    assert map_attribute_to_list({"type": "url", "value": "https://Example.COM/a"}) == ("misp-url", "example.com")


def test_write_lists_dedupes_and_writes_all_targets(tmp_path):
    out_dir = tmp_path
    lists = {
        'malware-hashes': {'bbb', 'aaa', 'aaa'},
        'misp-ip': {'1.1.1.1'},
        'misp-domain': {'example.com'},
        'misp-url': set(),
    }

    write_lists(out_dir, lists)

    assert (out_dir / 'malware-hashes').read_text(encoding='utf-8').splitlines() == ['aaa', 'bbb']
    assert (out_dir / 'misp-ip').read_text(encoding='utf-8').splitlines() == ['1.1.1.1']
    assert (out_dir / 'misp-domain').read_text(encoding='utf-8').splitlines() == ['example.com']
    assert (out_dir / 'misp-url').read_text(encoding='utf-8').splitlines() == []

