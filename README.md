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
| `server_wazuh_misp_setup.sh` | ติดตั้งและตั้งค่า Wazuh Manager ฝั่ง Server พร้อม MISP, Telegram และ Active Response |
| `client_wazuh_sysmon_setup.ps1` | ติดตั้ง Wazuh Agent + Sysmon + Active Response ฝั่ง Windows Client |
| `client_wazuh_linux_setup.sh` | ติดตั้ง Wazuh Agent + Active Response ฝั่ง Linux Client |
| `lib/wazuh_misp_common.sh` | ฟังก์ชันร่วมที่สคริปต์ฝั่ง shell ใช้งานร่วมกัน |
| `tests/` | ชุดทดสอบของสคริปต์และ integration logic |
| `Lab-Wazuh-Guild/` | เอกสาร Lab HTML และรูปประกอบ |

> ถ้าต้องการใช้งานจริงใน repo นี้ ให้เริ่มจาก `server_wazuh_misp_setup.sh`, `client_wazuh_sysmon_setup.ps1` และ `client_wazuh_linux_setup.sh`

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
- restart Wazuh Manager

### 2) ติดตั้งฝั่ง Windows Client: Wazuh Agent + Sysmon + Active Response

เปิด PowerShell แบบ Run as Administrator แล้วรัน:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\client_wazuh_sysmon_setup.ps1
```

สคริปต์จะถามค่าหลัก ๆ เช่น:

- Wazuh Manager IP/FQDN
- Agent Name
- Agent Group ค่า default คือ `windows,sysmon,misp`
- ต้องการติดตั้ง Active Response สำหรับ block IP หรือไม่
- ถ้ามี Wazuh Agent อยู่แล้ว จะให้เลือก `reinstall` หรือ `uninstall`

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
