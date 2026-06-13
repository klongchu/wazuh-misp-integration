#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_SCRIPT="$SCRIPT_DIR/server_wazuh_misp_setup.sh"

if [ -f "$SERVER_SCRIPT" ]; then
  exec "$SERVER_SCRIPT" "$@"
fi

TMP_DIR="${TMPDIR:-/tmp}/wazuh-misp-setup.$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT
curl -fsSL https://raw.githubusercontent.com/klongchu/wazuh-misp-integration/main/server_wazuh_misp_setup.sh -o "$TMP_DIR/server_wazuh_misp_setup.sh"
chmod +x "$TMP_DIR/server_wazuh_misp_setup.sh"
exec "$TMP_DIR/server_wazuh_misp_setup.sh" "$@"
