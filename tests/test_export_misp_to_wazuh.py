import pytest
import os
from pathlib import Path
import importlib.util
import json

# Dynamically load the script as a module
spec = importlib.util.spec_from_file_location("export_misp_to_wazuh", "export_misp_to_wazuh.py")
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)

# Now, access the functions through the loaded module
map_attribute_to_list = exporter.map_attribute_to_list
normalize_misp_url = exporter.normalize_misp_url
write_lists = exporter.write_lists
fetch_attributes = exporter.fetch_attributes
SUPPORTED_TYPES = exporter.SUPPORTED_TYPES


class DummyResponse:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        return None

    def json(self):
        return self._payload


class DummySession:
    def __init__(self, payload):
        self.payload = payload
        self.calls = []

    def post(self, url, headers=None, json=None, verify=None, timeout=None):
        self.calls.append(
            {
                "url": url,
                "headers": headers,
                "json": json,
                "verify": verify,
                "timeout": timeout,
            }
        )
        return DummyResponse(self.payload)


class ExplodingPyMISP:
    def __init__(self, *args, **kwargs):
        raise AssertionError("PyMISP should not be used")


def test_normalize_misp_url_strips_restsearch_path():
    assert normalize_misp_url("https://misp.example.com/attributes/restSearch/") == "https://misp.example.com"
    assert normalize_misp_url("https://misp.example.com/") == "https://misp.example.com"


def test_map_attribute_to_list_routes_ioc_types():
    assert map_attribute_to_list({"type": "md5", "value": "a"}) == ("malware-hashes", "a")
    assert map_attribute_to_list({"type": "ip-dst", "value": "8.8.8.8"}) == ("misp-ip", "8.8.8.8")
    assert map_attribute_to_list({"type": "domain", "value": "Example.COM."}) == ("misp-domain", "example.com")
    assert map_attribute_to_list({"type": "url", "value": "https://Example.COM/a"}) == ("misp-url", "example.com")


def test_fetch_attributes_posts_to_restsearch_without_pymisp(monkeypatch):
    attributes = [{"type": "sha256", "value": "abc", "to_ids": True}]
    session = DummySession({"response": {"Attribute": attributes}})
    monkeypatch.setattr(exporter, "requests", session, raising=False)

    result = fetch_attributes("https://misp.example.com", "secret", verify_ssl=True)

    assert result == attributes
    assert session.calls == [
        {
            "url": "https://misp.example.com/attributes/restSearch",
            "headers": {
                "Content-Type": "application/json",
                "Authorization": "secret",
                "Accept": "application/json",
            },
            "json": {
                "type": sorted(SUPPORTED_TYPES),
                "to_ids": 1,
                "includeWarninglistHits": True,
            },
            "verify": True,
            "timeout": 30,
        }
    ]


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

