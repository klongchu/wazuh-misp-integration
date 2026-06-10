#!/bin/bash
set -e

echo "================================================="
echo " Wazuh 4.14.x MISP Integration Installer"
echo "================================================="

read -p "Enter MISP URL เช่น https://misp.domain.local: " MISP_URL
read -s -p "Enter MISP API Key: " MISP_KEY
echo ""

MISP_URL="${MISP_URL%/}"

if [ -z "$MISP_URL" ] || [ -z "$MISP_KEY" ]; then
  echo "[ERROR] MISP_URL และ MISP_KEY ห้ามว่าง"
  exit 1
fi

if [ ! -d "/var/ossec" ]; then
  echo "[ERROR] ไม่พบ /var/ossec กรุณารันบน Wazuh Manager"
  exit 1
fi

echo "[1/6] Install dependencies"
apt-get update -qq
apt-get install -y python3-requests curl >/dev/null

echo "[2/6] Create custom-misp.py"

cat > /var/ossec/integrations/custom-misp.py <<EOF
#!/var/ossec/framework/python/bin/python3
## MISP API Integration
#
import sys
import os
from socket import socket, AF_UNIX, SOCK_DGRAM
from datetime import date, datetime, timedelta
import time
import requests
from requests.exceptions import ConnectionError
import json
import ipaddress
import hashlib
import re
pwd = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
socket_addr = '{0}/queue/sockets/queue'.format(pwd)
def send_event(msg, agent = None):
    if not agent or agent["id"] == "000":
        string = '1:misp:{0}'.format(json.dumps(msg))
    else:
        string = '1:[{0}] ({1}) {2}->misp:{3}'.format(agent["id"], agent["name"], agent["ip"] if "ip" in agent else "any", json.dumps(msg))
    sock = socket(AF_UNIX, SOCK_DGRAM)
    sock.connect(socket_addr)
    sock.send(string.encode())
    sock.close()
false = False
# Read configuration parameters
alert_file = open(sys.argv[1])
# Read the alert file
alert = json.loads(alert_file.read())
alert_file.close()
# New Alert Output if MISP Alert or Error calling the API
alert_output = {}
# MISP Server Base URL
misp_base_url = "https://**your misp instance**/attributes/restSearch/"
# MISP Server API AUTH KEY
misp_api_auth_key = "*Your API Key"
# API - HTTP Headers
misp_apicall_headers = {"Content-Type":"application/json", "Authorization":f"{misp_api_auth_key}", "Accept":"application/json"}
## Extract Sysmon for Windows/Sysmon for Linux and Sysmon Event ID
event_source = alert["rule"]["groups"][0]
event_type = alert["rule"]["groups"][2]
## Regex Pattern used based on SHA256 length (64 characters)
regex_file_hash = re.compile('\w{64}')
if event_source == 'windows':
    if event_type == 'sysmon_event1':
        try:
            wazuh_event_param = regex_file_hash.search(alert["data"]["win"]["eventdata"]["hashes"]).group(0)
        except IndexError:
            sys.exit()
    elif event_type == 'sysmon_event3' and alert["data"]["win"]["eventdata"]["destinationIsIpv6"] == 'false':
        try:
            dst_ip = alert["data"]["win"]["eventdata"]["destinationIp"]
            if ipaddress.ip_address(dst_ip).is_global:
                wazuh_event_param = dst_ip
            else:
                sys.exit()
        except IndexError:
            sys.exit()
    elif event_type == 'sysmon_event3' and alert_output["data"]["win"]["eventdata"]["destinationIsIpv6"] == 'true':
        sys.exit()
    elif event_type == 'sysmon_event6':
        try:
            wazuh_event_param = regex_file_hash.search(alert["data"]["win"]["eventdata"]["hashes"]).group(0)
        except IndexError:
            sys.exit()
    elif event_type == 'sysmon_event7':
        try:
            wazuh_event_param = regex_file_hash.search(alert["data"]["win"]["eventdata"]["hashes"]).group(0)
        except IndexError:
            sys.exit()
    elif event_type == 'sysmon_event_15':
        try:
            wazuh_event_param = regex_file_hash.search(alert["data"]["win"]["eventdata"]["hashes"]).group(0)
        except IndexError:
            sys.exit()
    elif event_type == 'sysmon_event_22':
        try:
            wazuh_event_param = alert["data"]["win"]["eventdata"]["queryName"]
        except IndexError:
            sys.exit()
    elif event_type == 'sysmon_event_23':
        try:
            wazuh_event_param = regex_file_hash.search(alert["data"]["win"]["eventdata"]["hashes"]).group(0)
        except IndexError:
            sys.exit()
    elif event_type == 'sysmon_event_24':
        try:
            wazuh_event_param = regex_file_hash.search(alert["data"]["win"]["eventdata"]["hashes"]).group(0)
        except IndexError:
            sys.exit()
    elif event_type == 'sysmon_event_25':
        try:
            wazuh_event_param = regex_file_hash.search(alert["data"]["win"]["eventdata"]["hashes"]).group(0)
        except IndexError:
            sys.exit()
    else:
        sys.exit()
    misp_search_value = "value:"f"{wazuh_event_param}"
    misp_search_url = ''.join([misp_base_url, misp_search_value])
    try:
        misp_api_response = requests.get(misp_search_url, headers=misp_apicall_headers, verify=False)
    except ConnectionError:
        alert_output["misp"] = {}
        alert_output["integration"] = "misp"
        alert_output["misp"]["error"] = 'Connection Error to MISP API'
        send_event(alert_output, alert["agent"])
    else:
        misp_api_response = misp_api_response.json()
    # Check if response includes Attributes (IoCs)
        if (misp_api_response["response"]["Attribute"]):
    # Generate Alert Output from MISP Response
            alert_output["misp"] = {}
            alert_output["misp"]["source"] = {}
            alert_output["misp"]["event_id"] = misp_api_response["response"]["Attribute"][0]["event_id"]
            alert_output["misp"]["category"] = misp_api_response["response"]["Attribute"][0]["category"]
            alert_output["misp"]["value"] = misp_api_response["response"]["Attribute"][0]["value"]
            alert_output["misp"]["type"] = misp_api_response["response"]["Attribute"][0]["type"]
            alert_output["misp"]["source"]["description"] = alert["rule"]["description"]
            send_event(alert_output, alert["agent"])
elif event_source == 'linux':
    if event_type == 'sysmon_event3' and alert["data"]["eventdata"]["destinationIsIpv6"] == 'false':
        try:
            dst_ip = alert["data"]["eventdata"]["DestinationIp"]
            if ipaddress.ip_address(dst_ip).is_global:
                wazuh_event_param = dst_ip
                misp_search_value = "value:"f"{wazuh_event_param}"
                misp_search_url = ''.join([misp_base_url, misp_search_value])
                try:
                    misp_api_response = requests.get(misp_search_url, headers=misp_apicall_headers, verify=False)
                except ConnectionError:
                    alert_output["misp"] = {}
                    alert_output["integration"] = "misp"
                    alert_output["misp"]["error"] = 'Connection Error to MISP API'
                    send_event(alert_output, alert["agent"])
                else:
                    misp_api_response = misp_api_response.json()
        # Check if response includes Attributes (IoCs)
                    if (misp_api_response["response"]["Attribute"]):
                # Generate Alert Output from MISP Response
                        alert_output["misp"] = {}
                        alert_output["misp"]["event_id"] = misp_api_response["response"]["Attribute"][0]["event_id"]
                        alert_output["misp"]["category"] = misp_api_response["response"]["Attribute"][0]["category"]
                        alert_output["misp"]["value"] = misp_api_response["response"]["Attribute"][0]["value"]
                        alert_output["misp"]["type"] = misp_api_response["response"]["Attribute"][0]["type"]
                        send_event(alert_output, alert["agent"])
            else:
                sys.exit()
        except IndexError:
            sys.exit()
    else:
        sys.exit()
elif event_source == 'ossec' and event_type == "syscheck_entry_added":
    try:
        wazuh_event_param = alert["syscheck"]["sha256_after"]
    except IndexError:
        sys.exit()
    misp_search_value = "value:"f"{wazuh_event_param}"
    misp_search_url = ''.join([misp_base_url, misp_search_value])
    try:
        misp_api_response = requests.get(misp_search_url, headers=misp_apicall_headers, verify=false)
    except ConnectionError:
        alert_output["misp"] = {}
        alert_output["integration"] = "misp"
        alert_output["misp"]["error"] = 'Connection Error to MISP API'
        send_event(alert_output, alert["agent"])
    else:
        misp_api_response = misp_api_response.json()
    # Check if response includes Attributes (IoCs)
        if (misp_api_response["response"]["Attribute"]):
    # Generate Alert Output from MISP Response
            alert_output["misp"] = {}
            alert_output["misp"]["event_id"] = misp_api_response["response"]["Attribute"][0]["event_id"]
            alert_output["misp"]["category"] = misp_api_response["response"]["Attribute"][0]["category"]
            alert_output["misp"]["value"] = misp_api_response["response"]["Attribute"][0]["value"]
            alert_output["misp"]["type"] = misp_api_response["response"]["Attribute"][0]["type"]
            send_event(alert_output, alert["agent"])
else:
    sys.exit()
EOF

echo "[3/6] Set permission"
chmod 750 /var/ossec/integrations/custom-misp.py
chown root:wazuh /var/ossec/integrations/custom-misp.py

echo "[4/6] Backup ossec.conf"
cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.bak.$(date +%Y%m%d_%H%M%S)

echo "[5/6] Add integration config"

if ! grep -q "custom-misp" /var/ossec/etc/ossec.conf; then
  sed -i '/<\/ossec_config>/i\
  <integration>\
    <name>custom-misp</name>\
    <alert_format>json</alert_format>\
    <level>7</level>\
  </integration>' /var/ossec/etc/ossec.conf
else
  echo "[INFO] custom-misp already exists in ossec.conf"
fi

echo "[6/6] Test MISP API"

HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: ${MISP_KEY}" \
  -H "Accept: application/json" \
  "${MISP_URL}/attributes/restSearch/")

echo "[INFO] MISP HTTP Code: $HTTP_CODE"

echo "[INFO] Restart Wazuh Manager"
systemctl restart wazuh-manager

echo ""
echo "================================================="
echo " DONE"
echo "================================================="
echo "MISP URL: $MISP_URL"
echo "Check log:"
echo "tail -f /var/ossec/logs/ossec.log"
echo "================================================="