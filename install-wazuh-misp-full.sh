#!/bin/bash
set -e

TMP_DIR="${TMPDIR:-/tmp}/wazuh-misp-setup.$$"
mkdir -p "$TMP_DIR/lib"
trap 'rm -rf "$TMP_DIR"' EXIT
curl -fsSL https://raw.githubusercontent.com/klongchu/wazuh-misp-integration/main/server_wazuh_misp_setup.sh -o "$TMP_DIR/server_wazuh_misp_setup.sh"
curl -fsSL https://raw.githubusercontent.com/klongchu/wazuh-misp-integration/main/lib/wazuh_misp_common.sh -o "$TMP_DIR/lib/wazuh_misp_common.sh"
exec bash "$TMP_DIR/server_wazuh_misp_setup.sh" "$@"
