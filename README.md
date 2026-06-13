# Wazuh + MISP + Telegram + Windows Active Response

![Wazuh](https://img.shields.io/badge/Wazuh-4.x-blue?style=for-the-badge&logo=wazuh&logoColor=white)
![MISP](https://img.shields.io/badge/MISP-Threat%20Intelligence-green?style=for-the-badge&logo=misp&logoColor=white)
![Telegram](https://img.shields.io/badge/Telegram-Notifications-blue?style=for-the-badge&logo=telegram&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-Windows%20Client-blue?style=for-the-badge&logo=powershell&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-Linux%20Scripts-green?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Sysmon](https://img.shields.io/badge/Sysmon-Event%20Logging-purple?style=for-the-badge&logo=windows&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-Server%2FClient-orange?style=for-the-badge&logo=ubuntu&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-Client-blue?style=for-the-badge&logo=windows&logoColor=white)

## ✨ คุณสมบัติหลัก

- 🛡️ **Wazuh Manager Setup**: ติดตั้งและตั้งค่า Wazuh Manager บน Ubuntu.
- 🚨 **MISP Integration**: เชื่อมต่อกับ MISP เพื่อรับ Threat Intelligence.
- 💬 **Telegram Notifications**: แจ้งเตือนผ่าน Telegram เมื่อมี Alert สำคัญ.
- 🚀 **Active Response**: กลไกตอบโต้ภัยคุกคามอัตโนมัติ (IP Blocking) บน Windows และ Linux.
- 💻 **Windows Client Setup**: ติดตั้ง Wazuh Agent, Sysmon, และ Active Response บน Windows.
- 🐧 **Linux Client Setup**: ติดตั้ง Wazuh Agent และ Active Response บน Linux.

โปรเจกต์นี้ใช้ติดตั้ง Lab Wazuh ที่เชื่อมกับ MISP และ Telegram พร้อม Windows client ที่ติดตั้ง Wazuh Agent + Sysmon + Active Response สำหรับ block IP อัตโนมัติ

## ไฟล์หลัก

| ไฟล์ | ใช้ทำอะไร |
| --- | --- |
| `install-wazuh-misp-full.sh` | Entrypoint สำหรับ Wazuh Manager. เรียก `server_wazuh_misp_setup.sh` |
| `server_wazuh_misp_setup.sh` | ติดตั้ง/ตั้งค่า Wazuh Manager ฝั่ง Server พร้อม MISP, Telegram, Active Response |
| `client_wazuh_sysmon_setup.ps1` | ติดตั้ง Wazuh Agent + Sysmon + Windows Active Response ฝั่ง Windows Client |
| `client_wazuh_linux_setup.sh` | ติดตั้ง Wazuh Agent + Active Response ฝั่ง Linux Client |
| `Lab-Wazuh-Guild/` | เอกสาร Lab HTML และรูปประกอบ |

> ใช้งานจริงแนะนำใช้ `server_wazuh_misp_setup.sh`, `client_wazuh_sysmon_setup.ps1`, และ `client_wazuh_linux_setup.sh` เป็นหลัก

## ข้อกำหนดก่อนติดตั้ง

### Server / Linux Client

- ต้องมี `bash`, `curl`, `sudo`
- Linux ฝั่ง client script นี้ออกแบบมาสำหรับ Debian/Ubuntu ที่มี `apt`
- ถ้าจะใช้ Active Response ฝั่ง Linux ต้องมี `iptables`

### Windows Client

- ต้องรัน PowerShell แบบ `Run as Administrator`
- ต้องใช้งาน `msiexec.exe` และ `Invoke-WebRequest` ได้
- ต้องดาวน์โหลดไฟล์จาก internet ได้

## ติดตั้งแบบเร็ว

> คำสั่ง one-line แบบ `curl | bash` และ `irm | iex` ควรใช้เฉพาะกรณีที่เชื่อถือ source และตรวจสอบ script แล้วเท่านั้น

### Server (Ubuntu)

```bash
curl -fsSL https://raw.githubusercontent.com/klongchu/wazuh-misp-integration/main/install-wazuh-misp-full.sh | sudo bash
```

> หมายเหตุ: `install-wazuh-misp-full.sh` ตอนนี้เป็น entrypoint ที่เรียก `server_wazuh_misp_setup.sh` อีกที

### Windows Client (PowerShell Run as Administrator)

```powershell
powershell.exe -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/klongchu/wazuh-misp-integration/main/client_wazuh_sysmon_setup.ps1 | iex"
```

> สำหรับ production แนะนำให้ดาวน์โหลดไฟล์ `.ps1` มาก่อน แล้วรันจากไฟล์ local แทน `irm | iex`

### Linux Client

```bash
curl -fsSL https://raw.githubusercontent.com/klongchu/wazuh-misp-integration/main/client_wazuh_linux_setup.sh | sudo bash
```

## ลำดับการติดตั้ง

### 1. ติดตั้งฝั่ง Server: Wazuh Manager + MISP + Telegram

รันบน Ubuntu/Wazuh Manager:

```bash
sudo bash server_wazuh_misp_setup.sh
```

สคริปต์จะถามค่าเหล่านี้:

- ทำ server preparation แล้วหรือยัง
- ต้องการตั้ง hostname เป็น `wazuh-server` หรือไม่
- MISP URL
- MISP API Key
- Telegram Bot Token
- Telegram Chat ID
- ต้องการเปิด Active Response หรือไม่
- Active Response timeout

สิ่งที่สคริปต์ทำ:

- เตรียม machine-id/dbus/network ตามแนว Lab
- ตั้ง hostname/hosts ถ้าเลือกทำ
- ตรวจว่ามี integration เดิมหรือไม่ก่อนเขียนทับ
- ติดตั้ง `custom-misp`
- ติดตั้ง `custom-telegram.py`
- เพิ่ม integration ใน `ossec.conf`
- เพิ่ม Active Response script ฝั่ง Linux manager
- เพิ่ม rule สำหรับ Sysmon Event ID 22 fallback
- restart Wazuh Manager

### 2. ติดตั้งฝั่ง Windows Client: Wazuh Agent + Sysmon + Active Response

เปิด PowerShell แบบ Run as Administrator แล้วรัน:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\client_wazuh_sysmon_setup.ps1
```

สคริปต์จะถามค่าเหล่านี้:

- Wazuh Manager IP/FQDN
- Agent Name
- Agent Group ค่า default คือ `windows,sysmon,misp`
- ต้องการติดตั้ง Active Response สำหรับ block IP หรือไม่
- ถ้ามี Wazuh Agent ติดตั้งอยู่แล้ว: `reinstall` (ติดตั้งทับ) หรือ `uninstall` (ลบก่อนแล้วติดตั้งใหม่) ค่า default คือ `reinstall`

สิ่งที่สคริปต์ทำ:

- ดาวน์โหลดและติดตั้ง Wazuh Agent MSI
- ดาวน์โหลด Sysmon64.exe
- ดาวน์โหลด Sysmon config จาก SwiftOnSecurity
- ติดตั้งหรือ update Sysmon
- เพิ่ม EventChannel `Microsoft-Windows-Sysmon/Operational` ใน Wazuh Agent config
- เขียนไฟล์ Active Response ลงในเครื่อง client โดยตรง:
  - `C:\Program Files (x86)\ossec-agent\active-response\bin\action-script.bat`
  - `C:\Program Files (x86)\ossec-agent\active-response\bin\block-malicious.ps1`
- restart Wazuh Agent service

### 3. ติดตั้งฝั่ง Linux Client: Wazuh Agent + Active Response

รันบน Linux Client:

```bash
sudo bash ./client_wazuh_linux_setup.sh
```

สคริปต์จะถามค่าเหล่านี้:

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

## ไฟล์ Active Response บน Linux Client

หลังรัน `client_wazuh_linux_setup.sh` จะมีไฟล์:

```text
/var/ossec/active-response/bin/block-malicious.sh
/var/ossec/logs/active-responses.log
```

## ตรวจสอบ Linux Client หลังติดตั้ง

```bash
sudo systemctl status wazuh-agent --no-pager
sudo tail -f /var/ossec/logs/ossec.log
sudo tail -f /var/ossec/logs/active-responses.log
sudo iptables -S | grep wazuh-misp-block
```

> หมายเหตุ: ถ้าเครื่องใช้ `nftables` เป็นหลัก อาจต้องตรวจสอบ rule ผ่าน tooling ของระบบเพิ่มเติม ไม่ใช่ดูผ่าน `iptables` อย่างเดียว

## Active Response คืออะไร

Active Response คือกลไกที่ให้ Wazuh สั่ง endpoint ทำ action อัตโนมัติเมื่อเจอ alert ที่ตรง rule

ในโปรเจกต์นี้ flow คือ:

1. Windows client ส่ง Sysmon event ไป Wazuh Manager
2. Wazuh Manager ตรวจ IOC ผ่าน MISP
3. ถ้าเจอ IOC และ rule ตรงเงื่อนไข จะ trigger Active Response
4. Windows client รัน `action-script.bat`
5. `action-script.bat` เรียก `block-malicious.ps1`
6. `block-malicious.ps1` อ่าน IP จาก alert JSON
7. Windows Firewall สร้าง inbound/outbound block rule สำหรับ IP นั้น

## ไฟล์ Active Response บน Windows Client

หลังรัน `client_wazuh_sysmon_setup.ps1` จะมีไฟล์:

```text
C:\Program Files (x86)\ossec-agent\active-response\bin\action-script.bat
C:\Program Files (x86)\ossec-agent\active-response\bin\block-malicious.ps1
C:\Program Files (x86)\ossec-agent\active-response\active-response.log
```

ไม่ต้อง copy ไฟล์แยกแล้ว เพราะฝังอยู่ใน `client_wazuh_sysmon_setup.ps1` แล้ว

## ตรวจสอบ Service บน Windows

```powershell
Get-Service | Where-Object { $_.Name -match '^WazuhSvc$|^wazuh-agent$|^ossec-agent$|Sysmon64' -or $_.DisplayName -match '^Wazuh Agent$|Sysmon' }
```

ควรเห็น service ของ Wazuh Agent และ Sysmon ทำงานอยู่

> ถ้าติดตั้งสำเร็จ service อาจชื่อ `WazuhSvc`, `wazuh-agent`, หรือ `ossec-agent` แล้วแต่ Wazuh Agent version

## ตรวจสอบ Sysmon EventChannel ใน Wazuh Agent

เปิดไฟล์:

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

## ตรวจสอบ Firewall Rule หลัง Active Response ทำงาน

```powershell
Get-NetFirewallRule -DisplayName "Wazuh MISP Block *" | Format-Table DisplayName, Direction, Action, Enabled
```

## Log ที่ควรดู

### Log ฝั่ง Windows Client

```text
C:\Program Files (x86)\ossec-agent\active-response\active-response.log
C:\Program Files (x86)\ossec-agent\ossec.log
%TEMP%\wazuh_sysmon\wazuh-agent-install.log
```

ถ้า script ขึ้น `Wazuh Agent Service not found` หรือ service start ไม่ได้ ให้เปิดดู:

```text
%TEMP%\wazuh_sysmon\wazuh-agent-install.log
C:\Program Files (x86)\ossec-agent\ossec.log
```

### Wazuh Manager

```bash
sudo tail -f /var/ossec/logs/ossec.log
sudo tail -f /var/ossec/logs/active-responses.log
```

## ทดสอบ MISP Integration

บน Wazuh Manager ดู log:

```bash
sudo tail -f /var/ossec/logs/ossec.log
```

ถ้ามี alert ที่ตรง IOC จะเห็นการเรียก integration `custom-misp` และถ้าเปิด Telegram จะมีข้อความแจ้งเตือนเข้า Telegram

## ตรวจสอบ MISP CDB List Export

บน Wazuh Manager ตรวจสอบไฟล์ CDB list ที่ export จาก MISP:

```bash
sudo cat /var/ossec/etc/lists/malware-hashes
sudo cat /var/ossec/etc/lists/misp-ip
sudo cat /var/ossec/etc/lists/misp-domain
sudo cat /var/ossec/etc/lists/misp-url
sudo grep -n '<list>etc/lists/' /var/ossec/etc/ossec.conf
sudo tail -f /var/ossec/logs/integrations.log
```

ไฟล์ cron สำหรับ refresh อัตโนมัติ:

```bash
sudo cat /etc/cron.d/wazuh-misp-cdb-export
```

Exporter อยู่ที่:

```bash
sudo ls -l /var/ossec/integrations/export_misp_to_wazuh.py
```

## ทดสอบ Windows Firewall Block แบบ Manual

บน Windows client ใช้ PowerShell Run as Administrator:

```powershell
$ruleName = "Wazuh MISP Block 192.168.1.100"
New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -RemoteAddress 192.168.1.100 -Action Block -Profile Any -Enabled True
Get-NetFirewallRule -DisplayName "Wazuh MISP Block *"
Remove-NetFirewallRule -DisplayName $ruleName
```

## หมายเหตุสำคัญ

- ต้องรัน PowerShell ด้วยสิทธิ์ Administrator
- Windows client ต้องติดต่อ Wazuh Manager ได้
- Agent group แนะนำใช้ `windows,sysmon,misp`
- หากเคยติดตั้ง Wazuh Agent มาก่อน สคริปต์จะ install/update ทับผ่าน MSI
- หาก Active Response ไม่ทำงาน ให้เช็ค config ฝั่ง Wazuh Manager ใน `ossec.conf`
- ไฟล์แยก `action-script.bat` และ `block-malicious.ps1` ไม่มีแล้ว; รวมเข้า `client_wazuh_sysmon_setup.ps1` แล้ว
- คำสั่ง one-line ควรใช้เฉพาะกรณีที่ตรวจสอบ script แล้วและเชื่อถือ source
- Linux client script นี้อิง `apt` และ `iptables`; ถ้าใช้ distro/firewall backend อื่น อาจต้องปรับ script เพิ่ม
- หากต้องการ unblock IP ที่ถูก block ไปแล้ว ให้ลบ firewall rule เดิมออกก่อน แล้วค่อยสร้าง allow rule ถ้าจำเป็น
- ตัวอย่างบน Windows Client:

  ```powershell
  $Ioc = "192.168.1.100"
  $RuleBase = "Wazuh MISP Block $Ioc"
  Get-NetFirewallRule -DisplayName $RuleBase -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  Get-NetFirewallRule -DisplayName "$RuleBase Inbound" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  ```
