# Wazuh + MISP integration design

Date: 2026-06-12

## Goal
Build automated scripts for Wazuh + MISP based on lab HTML in `Lab-Wazuh-Guild/Labs Wazuh 245960d8062880c4b891c065cc9d545a.html`.

Target outcome:
- Wazuh manager can pull IOC intelligence from MISP.
- Windows agent setup can install Wazuh Agent, Sysmon, and active response files.
- Linux agent setup can install Wazuh Agent and active response files.
- One-line install stays available, but implementation is split into role-based wrappers with shared core logic.

## Scope
In scope:
- Server/manager automation
- Windows client automation
- Linux client automation
- Shared config helpers
- MISP integration config
- Rules and CDB list wiring
- Optional Telegram notification setup already present in current script
- Backup and validation flow

Out of scope:
- Rewriting Wazuh dashboard UI
- Changing MISP server behavior
- Building a two-way sync from Wazuh back to MISP
- Replacing lab content with a separate design

## Architecture
Use core + wrapper structure.

### Shared core
Shared helpers handle:
- env loading and prompting
- file backup
- managed config block upserts
- root/admin checks
- validation
- config cleanup/logging helpers

### Server wrapper
Role: Wazuh manager on Ubuntu.
Responsibilities:
- verify Wazuh manager exists
- install required packages
- install or refresh `custom-misp`
- set `MISP_BASE_URL` and `MISP_API_KEY`
- write `misp.xml` rules
- create/update CDB list files
- add `<list>` entries to `ossec.conf`
- add `<integration>` block for `custom-misp`
- add optional Telegram integration
- add optional Linux active response config
- add Windows support files referenced by lab docs when useful for downstream endpoint setup
- run config validation, then restart manager

### Windows wrapper
Role: Wazuh agent on Windows.
Responsibilities:
- install or update Wazuh Agent
- install Sysmon and Sysmon config
- ensure Sysmon event channel is collected
- add Windows group/agent config for FIM if needed
- write `action-script.bat`
- write `block-malicious.ps1`
- restart agent service

### Linux wrapper
Role: Wazuh agent on Linux.
Responsibilities:
- install Wazuh Agent
- configure manager address and agent group
- write Linux active response script
- restart agent service

## File layout
Planned files:
- `install-wazuh-misp-full.sh` - entrypoint or server wrapper
- `server_wazuh_misp_setup.sh` - manager setup wrapper
- `client_wazuh_sysmon_setup.ps1` - Windows setup wrapper
- `client_wazuh_linux_setup.sh` - Linux setup wrapper
- optional helper scripts or shared fragments if needed

Keep current entrypoint working if possible.

## Data flow
1. Manager script configures Wazuh integration with MISP.
2. MISP IOC data is fetched by `custom-misp`.
3. Wazuh rules in `misp.xml` match IOC categories/types.
4. Alerts are emitted in JSON and can trigger Telegram or active response.
5. Windows and Linux agents send logs/events to manager using their role-specific setup.
6. Endpoint scripts perform response actions such as firewall blocking when rules fire.

## Error handling and safety
- Backup every edited config before changes.
- Use managed markers for idempotent updates.
- Ask before overwriting existing integration files unless forced by config flag.
- Validate required inputs before writing any config.
- For Wazuh manager changes, run config test before restart.
- Stop on validation failure and print backup location.
- Do not log secrets.

## Validation
Minimum checks:
- shell syntax sanity for shell scripts
- PowerShell syntax sanity for Windows script
- Wazuh manager config test passes after manager changes
- script output clearly tells user where backup and final files are

## Notes from lab doc
The HTML doc includes manual steps for:
- cloning/starting lab VM
- Wazuh manager install
- MISP connection
- rule editing
- Windows agent deployment
- Sysmon install
- CDB list export from MISP
- active response setup

The scripts should automate the repeatable parts of those steps without changing the lab intent.
