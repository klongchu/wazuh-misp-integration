# Wazuh + MISP + Telegram + Windows Active Response

![Wazuh](https://img.shields.io/badge/Wazuh-4.x-blue?style=for-the-badge&logo=wazuh&logoColor=white)
![MISP](https://img.shields.io/badge/MISP-Threat%20Intelligence-green?style=for-the-badge&logo=misp&logoColor=white)
![Telegram](https://img.shields.io/badge/Telegram-Notifications-blue?style=for-the-badge&logo=telegram&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-Windows%20Client-blue?style=for-the-badge&logo=powershell&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-Linux%20Scripts-green?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Sysmon](https://img.shields.io/badge/Sysmon-Event%20Logging-purple?style=for-the-badge&logo=windows&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-Server%2FClient-orange?style=for-the-badge&logo=ubuntu&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-Client-blue?style=for-the-badge&logo=windows&logoColor=white)

## ภาพรวมโปรเจกต์

โปรเจกต์นี้ใช้สำหรับทำ Lab Wazuh ที่เชื่อมต่อกับ MISP และ Telegram พร้อมตัวอย่างการติดตั้ง Wazuh Agent บน Windows และ Linux รวมถึงการเปิดใช้ Active Response เพื่อ block IP อัตโนมัติเมื่อเจอ IOC ที่ตรงเงื่อนไข

เหมาะสำหรับใช้เป็นคู่มือทดลองติดตั้งแบบ step-by-step เพื่อให้เห็น flow ตั้งแต่รับ log, ตรวจ IOC, แจ้งเตือน, จนถึงสั่ง block ที่ endpoint

## Flow การทำงาน

```text
+----------------------+        ส่ง log / event        +----------------------+
|   Windows Client     | ---------------------------> |     Wazuh Manager    |
| - Wazuh Agent        |                              | - วิเคราะห์ Alert    |
| - Sysmon             |                              | - เรียก Integration |
| - Active Response    |                              | - สั่ง Response      |
+----------+-----------+                              +----------+-----------+
           ^                                                     |
           |                                                     |
           | block IP ผ่าน Windows Firewall                      | ตรวจ IOC
           |                                                     v
+----------+-----------+                              +----------------------+
|    Linux Client      |        ส่ง log / event        |         MISP         |
| - Wazuh Agent        | ---------------------------> | - Threat Intel      |
| - Active Response    |                              | - IOC Database      |
| - iptables           |                              +----------------------+
+----------+-----------+
           ^                                                     |
           |                                                     | แจ้งเตือน
           | block IP ผ่าน iptables                              v
           |                                          +----------------------+
           +------------------------------------------|       Telegram       |
                                                      | - Alert Message     |
                                                      +----------------------+

Flow สั้น:
Client -> Wazuh Manager -> MISP lookup -> Telegram alert -> Active Response block IP
```

ลำดับการทำงานหลัก:

1. Windows หรือ Linux client ส่ง log ไปที่ Wazuh Manager
2. Wazuh Manager วิเคราะห์ event และตรวจ IOC ผ่าน MISP
3. ถ้าตรงเงื่อนไขที่ตั้งไว้ จะส่งแจ้งเตือนไป Telegram
4. ถ้าเปิด Active Response เอาไว้ Wazuh จะสั่ง endpoint ให้ block IP อัตโนมัติ

## ไฟล์หลักในโปรเจกต์

| ไฟล์ | ใช้ทำอะไร |
| --- | --- |
| `install-wazuh-misp-full.sh` | Entry point สำหรับติดตั้งฝั่ง Wazuh Manager และเรียก `server_wazuh_misp_setup.sh` |
| `install-wazuh-issabel-alert-call.sh` | Entry point แบบ one-line สำหรับติดตั้ง `wazuh_issabel_alert_call.py` ลง `Wazuh Manager` |
| `server_wazuh_misp_setup.sh` | ติดตั้งและตั้งค่า Wazuh Manager ฝั่ง Server พร้อม MISP, Telegram และ Active Response |
| `client_wazuh_sysmon_setup.ps1` | ติดตั้ง Wazuh Agent + Sysmon + Active Response ฝั่ง Windows Client |
| `client_wazuh_linux_setup.sh` | ติดตั้ง Wazuh Agent + Active Response ฝั่ง Linux Client |
| `wazuh_issabel_alert_call.py` | รับ alert JSON จาก Wazuh แล้วสั่ง `Issabel/Asterisk` โทรออกผ่าน AMI |
| `lib/wazuh_misp_common.sh` | ฟังก์ชันร่วมที่สคริปต์ฝั่ง shell ใช้งานร่วมกัน |
| `tests/` | ชุดทดสอบของสคริปต์และ integration logic |
| `Lab-Wazuh-Guild/` | เอกสาร Lab HTML และรูปประกอบ |

> ถ้าต้องการใช้งานจริงใน repo นี้ ให้เริ่มจาก `server_wazuh_misp_setup.sh`, `client_wazuh_sysmon_setup.ps1`, `client_wazuh_linux_setup.sh` และ `wazuh_issabel_alert_call.py`

## ข้อกำหนดก่อนเริ่ม

### Server / Linux Client

- ต้องมี `bash`, `curl`, `sudo`
- Linux client script นี้ออกแบบมาสำหรับ Debian/Ubuntu ที่มี `apt`
- ถ้าจะใช้ Active Response ฝั่ง Linux ต้องมี `iptables`
- Wazuh Manager ควรเข้าถึง MISP URL ได้
- ถ้าจะใช้ Telegram ต้องมี Bot Token และ Chat ID พร้อมใช้งาน

### Windows Client

- ต้องรัน PowerShell แบบ `Run as Administrator`
- ต้องใช้งาน `msiexec.exe` และ `Invoke-WebRequest` ได้
- ต้องดาวน์โหลดไฟล์จาก internet ได้
- เครื่อง client ต้องติดต่อ Wazuh Manager ได้

## ติดตั้งแบบเร็ว

> คำสั่ง one-line แบบ `curl | bash` และ `irm | iex` ควรใช้เฉพาะกรณีที่เชื่อถือ source และตรวจสอบ script แล้วเท่านั้น

### Server (Ubuntu)

```bash
curl -fsSL https://raw.githubusercontent.com/klongchu/wazuh-misp-integration/main/install-wazuh-misp-full.sh | sudo bash
```

> `install-wazuh-misp-full.sh` เป็น entry point ที่เรียก `server_wazuh_misp_setup.sh` ต่ออีกที

### Windows Client (PowerShell Run as Administrator)

```powershell
powershell.exe -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/klongchu/wazuh-misp-integration/main/client_wazuh_sysmon_setup.ps1 | iex"
```

> ถ้าเป็น production หรือเครื่องใช้งานจริง แนะนำให้ดาวน์โหลดไฟล์ `.ps1` มาก่อน แล้วรันจากไฟล์ local แทน `irm | iex`

### Linux Client

```bash
curl -fsSL https://raw.githubusercontent.com/klongchu/wazuh-misp-integration/main/client_wazuh_linux_setup.sh | sudo bash
```

### Issabel Alert Call Script

```bash
curl -fsSL https://raw.githubusercontent.com/klongchu/wazuh-misp-integration/main/install-wazuh-issabel-alert-call.sh | sudo bash
```

> คำสั่งนี้จะติดตั้ง `wazuh_issabel_alert_call.py` ไปที่ `/var/ossec/integrations/wazuh_issabel_alert_call.py`

## ขั้นตอนติดตั้งแบบ Lab

### 1) ติดตั้งฝั่ง Server: Wazuh Manager + MISP + Telegram

รันบนเครื่อง Ubuntu ที่เป็น Wazuh Manager:

```bash
sudo bash server_wazuh_misp_setup.sh
```

สคริปต์จะถามค่าหลัก ๆ เช่น:

- ทำ server preparation แล้วหรือยัง
- ต้องการตั้ง hostname เป็น `wazuh-server` หรือไม่
- MISP URL
- MISP API Key
- Telegram Bot Token
- Telegram Chat ID
- ต้องการเปิด Active Response หรือไม่
- Active Response timeout

สิ่งที่สคริปต์ทำ:

- เตรียม machine-id, dbus และ network ตามแนวทาง lab
- ตั้ง hostname/hosts ถ้าเลือกทำ
- ตรวจ integration เดิมก่อนเขียนทับ
- ติดตั้ง `custom-misp`
- ติดตั้ง `custom-telegram.py`
- เพิ่ม integration ลงใน `ossec.conf`
- เพิ่ม Active Response script ฝั่ง Linux manager
- เพิ่ม rule สำหรับ Sysmon Event ID 22 fallback
- เพิ่ม rule กรอง noise ของ `Brother BrLog` (ไม่เก็บเป็น alert)
- restart Wazuh Manager

### 2) ติดตั้งฝั่ง Windows Client: Wazuh Agent + Sysmon + Active Response

เปิด PowerShell แบบ Run as Administrator แล้วรัน:

**แบบที่ 1: รันแบบโต้ตอบถามค่า (Interactive)**
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\client_wazuh_sysmon_setup.ps1
```

**แบบที่ 2: รันแบบส่ง Parameter โดยตรง (Unattended / Automation)**
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\client_wazuh_sysmon_setup.ps1 -WazuhManager "192.168.1.10" -AgentGroup "windows,sysmon,misp" -ActiveResponse "Y"
```

Parameter ที่รองรับ:
- `-WazuhManager` (หรือ `-Manager`, `-Domain`, `-IP`): IP หรือ FQDN ของ Wazuh Manager
- `-AgentGroup` (หรือ `-Group`): กลุ่มของ Agent (ค่าเริ่มต้น: `windows,sysmon,misp`)
- `-InstallActiveResponse` (หรือ `-ActiveResponse`, `-AR`): เปิดใช้งาน Active Response หรือไม่ (`Y`/`n`)
- `-AgentName` (หรือ `-Name`): ชื่อ Agent (ค่าเริ่มต้น: ComputerName)
- `-ReinstallMode` (หรือ `-Mode`): กรณีมี Agent อยู่แล้ว เลือกลงทับหรือถอนก่อน (`reinstall`/`uninstall`)

> หากไม่ระบุ Parameter ใด สคริปต์จะถามค่าผ่านหน้าต่างโต้ตอบ (Interactive prompt) ให้อัตโนมัติ

สิ่งที่สคริปต์ทำ:

- ดาวน์โหลดและติดตั้ง Wazuh Agent MSI
- ดาวน์โหลด `Sysmon64.exe`
- ดาวน์โหลด Sysmon config จาก SwiftOnSecurity
- ติดตั้งหรืออัปเดต Sysmon
- เพิ่ม EventChannel `Microsoft-Windows-Sysmon/Operational` ใน Wazuh Agent config
- เขียนไฟล์ Active Response ลงในเครื่อง client โดยตรง
- restart Wazuh Agent service

ไฟล์สำคัญที่ได้หลังติดตั้ง:

```text
C:\Program Files (x86)\ossec-agent\active-response\bin\action-script.bat
C:\Program Files (x86)\ossec-agent\active-response\bin\block-malicious.ps1
C:\Program Files (x86)\ossec-agent\active-response\active-response.log
```

### 3) ติดตั้งฝั่ง Linux Client: Wazuh Agent + Active Response

รันบน Linux Client:

```bash
sudo bash ./client_wazuh_linux_setup.sh
```

สคริปต์จะถามค่าหลัก ๆ เช่น:

- Wazuh Manager IP/FQDN
- Agent Name
- Agent Group ค่า default คือ `linux,misp`
- ต้องการติดตั้ง Active Response สำหรับ block IP หรือไม่

สิ่งที่สคริปต์ทำ:

- ติดตั้ง Wazuh Agent
- ตั้งค่า Agent config
- ติดตั้ง Active Response script ฝั่ง Linux client
- restart Wazuh Agent service
- ตรวจสอบ service และ active-response log

ไฟล์สำคัญที่ได้หลังติดตั้ง:

```text
/var/ossec/active-response/bin/block-malicious.sh
/var/ossec/logs/active-responses.log
```

## วิธีตรวจสอบหลังติดตั้ง

### ตรวจสอบฝั่ง Windows Client

เช็ค service ของ Wazuh Agent และ Sysmon:

```powershell
Get-Service | Where-Object { $_.Name -match '^WazuhSvc$|^wazuh-agent$|^ossec-agent$|Sysmon64' -or $_.DisplayName -match '^Wazuh Agent$|Sysmon' }
```

> ถ้าติดตั้งสำเร็จ service อาจชื่อ `WazuhSvc`, `wazuh-agent` หรือ `ossec-agent` แล้วแต่ version

เช็คว่า `ossec.conf` มี Sysmon EventChannel:

```text
C:\Program Files (x86)\ossec-agent\ossec.conf
```

ควรมี block นี้:

```xml
<localfile>
  <location>Microsoft-Windows-Sysmon/Operational</location>
  <log_format>eventchannel</log_format>
</localfile>
```

เช็ค firewall rule ที่ถูกสร้างจาก Active Response:

```powershell
Get-NetFirewallRule -DisplayName "Wazuh MISP Block *" | Format-Table DisplayName, Direction, Action, Enabled
```

เช็ค log สำคัญ:

```text
C:\Program Files (x86)\ossec-agent\active-response\active-response.log
C:\Program Files (x86)\ossec-agent\ossec.log
%TEMP%\wazuh_sysmon\wazuh-agent-install.log
```

### ตรวจสอบฝั่ง Linux Client

```bash
sudo systemctl status wazuh-agent --no-pager
sudo tail -f /var/ossec/logs/ossec.log
sudo tail -f /var/ossec/logs/active-responses.log
sudo iptables -S | grep wazuh-misp-block
```

> ถ้าเครื่องใช้ `nftables` เป็นหลัก อาจต้องตรวจ rule ผ่านเครื่องมือของระบบเพิ่มเติม ไม่ใช่ดูผ่าน `iptables` อย่างเดียว

### ตรวจสอบฝั่ง Wazuh Manager

ดู log ของ Wazuh และ Active Response:

```bash
sudo tail -f /var/ossec/logs/ossec.log
sudo tail -f /var/ossec/logs/active-responses.log
sudo tail -f /var/ossec/logs/integrations.log
```

ถ้ามี alert ที่ตรง IOC ควรเห็นการเรียก integration `custom-misp` และถ้าเปิด Telegram ไว้ ควรมีข้อความแจ้งเตือนส่งเข้า Telegram

### ตรวจสอบ MISP CDB List Export

บน Wazuh Manager ตรวจสอบไฟล์ CDB list ที่ export จาก MISP:

```bash
sudo cat /var/ossec/etc/lists/malware-hashes
sudo cat /var/ossec/etc/lists/misp-ip
sudo cat /var/ossec/etc/lists/misp-domain
sudo cat /var/ossec/etc/lists/misp-url
sudo grep -n '<list>etc/lists/' /var/ossec/etc/ossec.conf
sudo cat /etc/cron.d/wazuh-misp-cdb-export
sudo ls -l /var/ossec/integrations/export_misp_to_wazuh.py
```

## แจ้งเตือนโทรออกผ่าน Issabel Voice

ใช้ `wazuh_issabel_alert_call.py` เมื่อต้องการให้ `Wazuh` โทรออกหาเบอร์ที่กำหนดผ่าน `Issabel/Asterisk` ตอนมี alert level สูง

### Flow โทรออกผ่าน Issabel

```text
Wazuh Alert JSON -> custom integration / active-response -> wazuh_issabel_alert_call.py -> Issabel AMI -> โทรออกปลายทาง
```

### เงื่อนไขที่สคริปต์รองรับ

- โทรเมื่อ `rule.level >= ALERT_LEVEL_THRESHOLD`
- จำกัดเฉพาะบาง group ได้ผ่าน `ALERT_REQUIRED_GROUPS`
- กันโทรซ้ำตาม `rule id + agent name + source ip`
- เก็บ cooldown state และ log ลงไฟล์

### Environment Variables

| ตัวแปร | ความหมาย | ค่า default |
| --- | --- | --- |
| `ALERT_LEVEL_THRESHOLD` | ระดับ alert ขั้นต่ำที่จะโทร | `12` |
| `ALERT_REQUIRED_GROUPS` | group ที่อนุญาตให้โทร คั่นด้วย comma | ว่าง |
| `ALERT_CALL_COOLDOWN` | เวลากันโทรซ้ำ หน่วยวินาที | `600` |
| `TARGET_NUMBER` | เบอร์ปลายทาง | ไม่มี ต้องกำหนด |
| `ISSABEL_HOST` | IP/FQDN ของ Issabel | ไม่มี ต้องกำหนด |
| `ISSABEL_PORT` | พอร์ต AMI | `5038` |
| `AMI_USER` | ชื่อผู้ใช้ AMI | ไม่มี ต้องกำหนด |
| `AMI_PASS` | รหัสผ่าน AMI | ไม่มี ต้องกำหนด |
| `ASTERISK_CHANNEL_PREFIX` | channel prefix สำหรับ originate | `Local` |
| `ASTERISK_CONTEXT` | dialplan context | `from-internal` |
| `ASTERISK_EXTEN` | extension ที่จะให้ dialplan วิ่งต่อ | ใช้ค่า `TARGET_NUMBER` |
| `ASTERISK_PRIORITY` | dialplan priority | `1` |
| `ASTERISK_CALLERID` | caller ID ตอนโทรออก | `WAZUH-ALERT <9999>` |
| `ASTERISK_TIMEOUT_MS` | timeout การ originate หน่วย ms | `30000` |
| `ISSABEL_SOCKET_TIMEOUT` | socket timeout หน่วยวินาที | `10` |
| `ISSABEL_STATE_FILE` | ไฟล์เก็บ cooldown state | `/var/ossec/tmp/issabel-call-state.json` |
| `ISSABEL_LOG_FILE` | ไฟล์ log | `/var/ossec/logs/issabel-call.log` |

### ตัวอย่างการทดสอบสคริปต์บน Wazuh Manager

ติดตั้งแบบ one-line:

```bash
curl -fsSL https://raw.githubusercontent.com/klongchu/wazuh-misp-integration/main/install-wazuh-issabel-alert-call.sh | sudo bash
```

สคริปต์จะทำให้เลย:

- ติดตั้ง `wazuh_issabel_alert_call.py`
- สร้าง wrapper `custom-issabel-call`
- สร้าง rule `100950` ใน `/var/ossec/etc/rules/local_rules.xml`
- เพิ่ม integration `custom-issabel-call` ลง `ossec.conf`
- บันทึกค่า config ลงไฟล์ env ที่ `/var/ossec/etc/wazuh-issabel-alert-call.env`

สร้างไฟล์ตัวอย่าง `alert.json` แล้วรัน:

```bash
export ALERT_LEVEL_THRESHOLD=12
export ALERT_REQUIRED_GROUPS="sysmon_event_3,authentication_failed"
export TARGET_NUMBER="0812345678"
export ISSABEL_HOST="192.168.1.20"
export AMI_USER="admin"
export AMI_PASS="change-me"
python3 /var/ossec/integrations/wazuh_issabel_alert_call.py --stdin-file alert.json
```

ตัวอย่าง `alert.json`:

```json
{
  "rule": {
    "id": "100200",
    "level": 15,
    "description": "Suspicious outbound connection",
    "groups": ["sysmon", "sysmon_event_3", "windows"]
  },
  "agent": {
    "name": "win-client-01"
  },
  "data": {
    "srcip": "10.10.10.25"
  }
}
```

### แนวทางผูกเข้ากับ Wazuh

1. คัด alert ที่ต้องการโทร เช่น level `>= 12`
2. ให้ `Wazuh` ส่ง alert JSON เข้า `wazuh_issabel_alert_call.py`
3. ตั้ง dialplan ฝั่ง `Issabel` ให้ extension หรือ context ที่ใช้สามารถโทรออกและเล่นเสียงแจ้งเตือนได้
4. ตรวจ log ที่ `/var/ossec/logs/issabel-call.log`

### ตัวอย่าง Rule สำหรับ Voice Alert

installer จะเพิ่ม rule นี้ให้อัตโนมัติ ถ้ายังไม่มีอยู่

แนะนำให้สร้าง custom rule แยกสำหรับงานโทรออก โดยใส่ group เช่น `issabel_call`

ตัวอย่าง `local_rules.xml`:

```xml
<group name="local,issabel,">
  <rule id="100950" level="15">
    <if_sid>100805</if_sid>
    <description>High severity MISP alert for Issabel voice notification</description>
    <group>issabel_call,misp_high,</group>
  </rule>
</group>
```

ความหมาย:

- `if_sid 100805` อ้างอิง rule MISP high severity ที่มีอยู่แล้วในโปรเจกต์นี้
- ยก alert ให้ชัดว่าเป็นกลุ่ม `issabel_call`
- ใช้ร่วมกับ env `ALERT_REQUIRED_GROUPS="issabel_call"`

ถ้าต้องการโทรจาก rule อื่น ก็เปลี่ยน `if_sid` ได้ เช่น:

- `100801` สำหรับ `misp_ip`
- `100802` สำหรับ `misp_domain`
- `100804` สำหรับ `misp_hash`
- `100805` สำหรับ high severity IOC

### ตัวอย่าง Integration ใน `ossec.conf`

installer จะเพิ่ม block นี้ให้อัตโนมัติ ถ้ายังไม่มีอยู่

เพิ่ม block นี้ใน `/var/ossec/etc/ossec.conf`:

```xml
<integration>
  <name>custom-issabel-call</name>
  <group>issabel_call</group>
  <alert_format>json</alert_format>
</integration>
```

หมายเหตุ:

- ถ้าใช้ wrapper script ชื่อ `custom-issabel-call` ให้ wrapper นั้นเป็นตัว `source` env file แล้วเรียก `wazuh_issabel_alert_call.py`
- ถ้าไม่ใช้ wrapper, Wazuh จะไม่โหลด env file อัตโนมัติจาก path ที่เราบันทึกไว้

### ตัวอย่าง Wrapper Script

ตัวอย่าง `/var/ossec/integrations/custom-issabel-call`:

```bash
#!/bin/bash
ENV_FILE="/var/ossec/etc/wazuh-issabel-alert-call.env"
SCRIPT="/var/ossec/integrations/wazuh_issabel_alert_call.py"

if [ -f "$ENV_FILE" ]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

exec /usr/bin/python3 "$SCRIPT" "$@"
```

จากนั้นตั้ง permission:

```bash
sudo chown root:wazuh /var/ossec/integrations/custom-issabel-call
sudo chmod 750 /var/ossec/integrations/custom-issabel-call
```

### ค่าที่แนะนำใน env

```bash
ALERT_LEVEL_THRESHOLD="15"
ALERT_REQUIRED_GROUPS="issabel_call"
ALERT_CALL_COOLDOWN="600"
```

### ตรวจสอบหลังตั้งค่า Issabel

```bash
sudo tail -f /var/ossec/logs/issabel-call.log
sudo cat /var/ossec/tmp/issabel-call-state.json
sudo cat /var/ossec/etc/wazuh-issabel-alert-call.env
```

ถ้าฝั่ง `Issabel` รับคำสั่งสำเร็จ log จะมี `Call triggered` และฝั่ง `Asterisk` ควรเห็น `Originate successfully queued`

## กรอง Noise ที่ไม่ต้องการเก็บ (Ignore Rules)

บาง event ที่ agent ส่งมาเป็น noise ที่ไม่มีความสำคัญด้าน security แต่เกิดถี่มาก เช่น error ของ printer driver `Brother BrLog` (`FindPushAwareAppName:: Invalid Arg`) ซึ่งจะไปโดน rule `60602` และเมื่อเกิดซ้ำ ๆ ก็จะถูกรวมเป็น rule correlation `61061` ทำให้ alert รก และเปลือง storage ของ Wazuh Indexer

installer จะสร้างไฟล์ `/var/ossec/etc/rules/brother_brlog_ignore.xml` ให้อัตโนมัติ เพื่อ **ไม่ให้ Wazuh เก็บ event เหล่านี้เลย**

### หลักการทำงาน

- `level="0"` → ไม่สร้าง alert
- `<options>no_log</options>` → ไม่เขียนลง `alerts.json` / `archives.json` และไม่ถูก index เข้า Wazuh Indexer

### ตัวอย่าง `brother_brlog_ignore.xml`

```xml
<group name="windows,windows_application,local_ignore,">
  <rule id="100902" level="0">
    <if_sid>60602</if_sid>
    <field name="win.system.providerName">^Brother BrLog$</field>
    <field name="win.system.eventID">^1001$</field>
    <field name="win.eventdata.data" type="pcre2">FindPushAwareAppName:: Invalid Arg</field>
    <description>Discard Brother BrLog FindPushAwareAppName noise</description>
    <options>no_log</options>
  </rule>

  <rule id="100903" level="0">
    <if_sid>61061</if_sid>
    <field name="win.system.providerName">^Brother BrLog$</field>
    <description>Discard aggregated Brother BrLog application noise</description>
    <options>no_log</options>
  </rule>
</group>
```

ความหมาย:

- `100902` จับ event เดี่ยว (rule `60602`) เฉพาะ provider `Brother BrLog` + Event ID `1001` + ข้อความ `FindPushAwareAppName:: Invalid Arg`
- `100903` จับ event ที่ถูกรวมแบบ correlation (rule `61061` — "Multiple Windows error application events") ของ provider `Brother BrLog`
- ทั้งคู่ใช้ `level="0"` + `no_log` จึงไม่ถูกเก็บและไม่แจ้งเตือน

### วิธีเพิ่ม Ignore Rule ของ event อื่นเอง

1. หา `rule.id` ที่ event ไปโดน (ดูจากฟิลด์ `rule.id` ใน alert JSON)
2. หา field ที่ระบุตัวตนของ noise เช่น `win.system.providerName`, `win.system.eventID`
3. เพิ่ม rule ใหม่โดยใช้ id ในช่วง custom (`100000`–`120000`) ที่ยังไม่ถูกใช้ พร้อม `level="0"` และ `<options>no_log</options>`

### ตรวจสอบและ apply

```bash
sudo /var/ossec/bin/wazuh-analysisd -t   # ตรวจ syntax ของ rule
sudo systemctl restart wazuh-manager
```

> หมายเหตุ: rule นี้มีผลกับ event **ใหม่** เท่านั้น ส่วนข้อมูลเก่าที่ถูก index ไปแล้วจะยังคงอยู่ ต้องลบผ่าน Wazuh Indexer / index management แยกต่างหาก

## Troubleshooting

### 1) Windows Agent service ไม่ขึ้น

ให้เช็คไฟล์:

```text
%TEMP%\wazuh_sysmon\wazuh-agent-install.log
C:\Program Files (x86)\ossec-agent\ossec.log
```

### 2) Active Response ไม่ทำงาน

ให้ตรวจ:

- ฝั่ง manager มี config ใน `ossec.conf` ครบหรือไม่
- endpoint ติดต่อกับ Wazuh Manager ได้หรือไม่
- log ที่ `/var/ossec/logs/active-responses.log` หรือ `active-response.log` มี error อะไรหรือไม่

### 3) Linux Client ไม่ block IP

ให้ตรวจ:

- เครื่องใช้ `iptables` หรือ backend อื่น
- script ถูกติดตั้งที่ `/var/ossec/active-response/bin/block-malicious.sh` หรือไม่
- service `wazuh-agent` ทำงานอยู่หรือไม่

### 4) Telegram ไม่ส่งข้อความ

ให้ตรวจ:

- Bot Token ถูกต้องหรือไม่
- Chat ID ถูกต้องหรือไม่
- log integration ฝั่ง manager มี error หรือไม่

### 5) Issabel ไม่โทรออก

ให้ตรวจ:

- ค่า `ISSABEL_HOST`, `AMI_USER`, `AMI_PASS`, `TARGET_NUMBER` ถูกต้องหรือไม่
- `Issabel/Asterisk` เปิด `AMI` และยอมให้ IP ของ `Wazuh Manager` เชื่อมต่อหรือไม่
- context ที่ตั้งใน `ASTERISK_CONTEXT` ใช้งานโทรออกได้จริงหรือไม่
- wrapper integration มีการ load `/var/ossec/etc/wazuh-issabel-alert-call.env` หรือไม่
- rule ที่ใช้โทรมี group `issabel_call` หรือ group ที่ตรงกับ `ALERT_REQUIRED_GROUPS` หรือไม่
- log ที่ `/var/ossec/logs/issabel-call.log` มี error อะไรหรือไม่
- ถ้ามี cooldown อยู่ สคริปต์จะ skip การโทรซ้ำชั่วคราว

## ทดสอบ Firewall Block แบบ Manual บน Windows

ถ้าต้องการทดสอบ rule แบบ manual บน Windows client:

```powershell
$ruleName = "Wazuh MISP Block 192.168.1.100"
New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -RemoteAddress 192.168.1.100 -Action Block -Profile Any -Enabled True
Get-NetFirewallRule -DisplayName "Wazuh MISP Block *"
Remove-NetFirewallRule -DisplayName $ruleName
```

ถ้าต้องการลบ rule block เดิมออกก่อน:

```powershell
$Ioc = "192.168.1.100"
$RuleBase = "Wazuh MISP Block $Ioc"
Get-NetFirewallRule -DisplayName $RuleBase -ErrorAction SilentlyContinue | Remove-NetFirewallRule
Get-NetFirewallRule -DisplayName "$RuleBase Inbound" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
```

## หมายเหตุสำคัญ

- ต้องรัน PowerShell ด้วยสิทธิ์ Administrator
- Windows client ต้องติดต่อ Wazuh Manager ได้
- Agent group ที่ใช้บ่อยคือ `windows,sysmon,misp` และ `linux,misp`
- ถ้าเคยติดตั้ง Wazuh Agent มาก่อน สคริปต์จะติดตั้งทับหรือให้เลือกถอนของเดิมก่อน
- หาก Active Response ไม่ทำงาน ให้เช็ค `ossec.conf` ฝั่ง Wazuh Manager ก่อน
- ไฟล์ `action-script.bat` และ `block-malicious.ps1` ถูกฝังไว้ใน `client_wazuh_sysmon_setup.ps1` แล้ว
- Linux client script นี้อิง `apt` และ `iptables`; ถ้าใช้ distro หรือ firewall backend อื่น อาจต้องปรับสคริปต์เพิ่ม
- อย่าใส่ MISP API Key, Telegram Bot Token หรือข้อมูลลับอื่นลงใน commit
- คำสั่ง one-line ควรใช้เฉพาะกรณีที่ตรวจสอบ script แล้วและเชื่อถือ source เท่านั้น
