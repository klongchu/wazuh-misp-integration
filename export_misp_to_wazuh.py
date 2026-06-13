#!/usr/bin/env python3
import argparse
import os
import sys
from pathlib import Path

import requests

LIST_NAMES = ("malware-hashes", "misp-ip", "misp-domain", "misp-url")
SUPPORTED_TYPES = {
    "md5",
    "sha1",
    "sha256",
    "ip-src",
    "ip-dst",
    "domain",
    "hostname",
    "url",
}


def normalize_misp_url(url):
    normalized = str(url).strip().rstrip("/")
    suffix = "/attributes/restSearch"
    if normalized.endswith(suffix):
        return normalized[: -len(suffix)]
    return normalized


def normalize_value(value):
    value = str(value).strip().lower()
    value = value.rstrip(".")
    if value.startswith("http://") or value.startswith("https://"):
        value = value.split("://", 1)[1]
    value = value.split("/", 1)[0]
    return value


def map_attribute_to_list(attribute):
    value = normalize_value(attribute.get("value", ""))
    attr_type = attribute.get("type", "")
    if attr_type in {"md5", "sha1", "sha256"}:
        return "malware-hashes", value
    if attr_type in {"ip-src", "ip-dst"}:
        return "misp-ip", value
    if attr_type in {"domain", "hostname"}:
        return "misp-domain", value
    if attr_type == "url":
        return "misp-url", value
    return None


def read_config(path):
    config = {}
    if not path:
        return config

    config_path = Path(path)
    if not config_path.exists():
        return config

    for line in config_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        config[key.strip()] = value.strip().strip('"').strip("'")
    return config


def fetch_attributes(url, key, verify_ssl=False):
    normalized_url = normalize_misp_url(url)
    response = requests.post(
        f"{normalized_url}/attributes/restSearch",
        headers={
            "Content-Type": "application/json",
            "Authorization": key,
            "Accept": "application/json",
        },
        json={
            "type": sorted(SUPPORTED_TYPES),
            "to_ids": 1,
            "includeWarninglistHits": True,
        },
        verify=verify_ssl,
        timeout=30,
    )
    response.raise_for_status()
    result = response.json()
    return result.get("response", {}).get("Attribute", [])




def build_lists(attributes):
    lists = {name: set() for name in LIST_NAMES}
    for attribute in attributes:
        mapped = map_attribute_to_list(attribute)
        if not mapped:
            continue
        list_name, value = mapped
        if value:
            lists[list_name].add(value)
    return lists


def write_lists(out_dir, lists):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    for name in LIST_NAMES:
        path = out_dir / name
        tmp = path.with_suffix(path.suffix + ".tmp")
        lines = sorted(v for v in lists.get(name, set()) if v)
        tmp.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
        tmp.replace(path)


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description="Export MISP IOC attributes to Wazuh CDB list files")
    parser.add_argument("--url", default=os.getenv("MISP_BASE_URL"), help="MISP base URL")
    parser.add_argument("--key", default=os.getenv("MISP_API_KEY"), help="MISP API key")
    parser.add_argument("--output-dir", default="/var/ossec/etc/lists", help="Wazuh lists directory")
    parser.add_argument("--config", default="/var/ossec/integrations/custom-misp.conf", help="Optional KEY=VALUE config file")
    parser.add_argument("--verify-ssl", action="store_true", help="Verify MISP TLS certificate")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    config = read_config(args.config)
    url = args.url or config.get("MISP_URL") or config.get("MISP_BASE_URL")
    key = args.key or config.get("MISP_API_KEY")

    if not url or not key:
        print("MISP URL and API key are required", file=sys.stderr)
        return 2

    attributes = fetch_attributes(url, key, verify_ssl=args.verify_ssl)
    lists = build_lists(attributes)
    write_lists(args.output_dir, lists)
    total = sum(len(values) for values in lists.values())
    print(f"exported {total} IOCs to {args.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
