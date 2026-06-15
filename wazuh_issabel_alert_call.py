#!/usr/bin/env python3
import argparse
import json
import os
import socket
import sys
import time
from pathlib import Path

DEFAULT_THRESHOLD = 12
DEFAULT_PORT = 5038
DEFAULT_TIMEOUT = 10
DEFAULT_COOLDOWN = 600
DEFAULT_STATE_FILE = "/var/ossec/tmp/issabel-call-state.json"
DEFAULT_LOG_FILE = "/var/ossec/logs/issabel-call.log"


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Trigger Issabel/Asterisk phone call from Wazuh alert JSON"
    )
    parser.add_argument(
        "--stdin-file",
        help="Read alert JSON from file instead of stdin",
    )
    parser.add_argument(
        "--state-file",
        default=os.getenv("ISSABEL_STATE_FILE", DEFAULT_STATE_FILE),
        help="Cooldown state file path",
    )
    parser.add_argument(
        "--log-file",
        default=os.getenv("ISSABEL_LOG_FILE", DEFAULT_LOG_FILE),
        help="Log file path",
    )
    return parser.parse_args(argv)


def getenv_int(name, default):
    value = os.getenv(name)
    if value is None or str(value).strip() == "":
        return default
    return int(value)


def load_alert(stdin_file=None):
    if stdin_file:
        raw = Path(stdin_file).read_text(encoding="utf-8").strip()
    else:
        raw = sys.stdin.read().strip()
    if not raw:
        raise ValueError("No alert JSON provided")
    return json.loads(raw)


def alert_level(alert):
    return int(alert.get("rule", {}).get("level", 0) or 0)


def alert_rule_id(alert):
    return str(alert.get("rule", {}).get("id", "unknown-rule"))


def alert_description(alert):
    return str(alert.get("rule", {}).get("description", "No description"))


def alert_groups(alert):
    groups = alert.get("rule", {}).get("groups", []) or []
    return [str(group) for group in groups]


def alert_agent_name(alert):
    return str(alert.get("agent", {}).get("name", "unknown-agent"))


def alert_source_ip(alert):
    candidates = [
        alert.get("data", {}).get("srcip"),
        alert.get("data", {}).get("src_ip"),
        alert.get("data", {}).get("source_ip"),
        alert.get("srcip"),
        alert.get("src_ip"),
    ]
    for value in candidates:
        if value:
            return str(value)
    return "unknown-ip"


def read_json_file(path):
    file_path = Path(path)
    if not file_path.exists():
        return {}
    try:
        return json.loads(file_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def write_json_file(path, payload):
    file_path = Path(path)
    file_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = file_path.with_suffix(file_path.suffix + ".tmp")
    tmp_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp_path.replace(file_path)


def append_log(path, message):
    file_path = Path(path)
    file_path.parent.mkdir(parents=True, exist_ok=True)
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    with file_path.open("a", encoding="utf-8") as handle:
        handle.write(f"[{timestamp}] {message}\n")


def build_dedupe_key(alert):
    rule_id = alert_rule_id(alert)
    agent_name = alert_agent_name(alert)
    source_ip = alert_source_ip(alert)
    return f"{rule_id}|{agent_name}|{source_ip}"


def should_skip_for_cooldown(alert, state_file, cooldown_seconds):
    if cooldown_seconds <= 0:
        return False, 0

    state = read_json_file(state_file)
    key = build_dedupe_key(alert)
    now = int(time.time())
    last_called = int(state.get(key, 0) or 0)
    elapsed = now - last_called

    if elapsed < cooldown_seconds:
        return True, cooldown_seconds - elapsed

    state[key] = now
    write_json_file(state_file, state)
    return False, 0


def build_alert_message(alert):
    level = alert_level(alert)
    rule_id = alert_rule_id(alert)
    description = alert_description(alert)
    agent_name = alert_agent_name(alert)
    source_ip = alert_source_ip(alert)
    return (
        f"Wazuh critical alert. "
        f"Level {level}. "
        f"Rule {rule_id}. "
        f"Agent {agent_name}. "
        f"Source {source_ip}. "
        f"Description {description}"
    )


def ami_expect(sock, marker):
    data = sock.recv(4096).decode(errors="ignore")
    if marker not in data:
        raise RuntimeError(f"AMI response missing marker: {marker}. Response: {data}")
    return data


def ami_send(sock, line):
    sock.sendall((line + "\r\n").encode())


def originate_call(message, target_number):
    host = os.getenv("ISSABEL_HOST")
    port = getenv_int("ISSABEL_PORT", DEFAULT_PORT)
    username = os.getenv("AMI_USER")
    secret = os.getenv("AMI_PASS")
    channel_prefix = os.getenv("ASTERISK_CHANNEL_PREFIX", "Local")
    context = os.getenv("ASTERISK_CONTEXT", "from-internal")
    extension = os.getenv("ASTERISK_EXTEN", target_number)
    priority = os.getenv("ASTERISK_PRIORITY", "1")
    caller_id = os.getenv("ASTERISK_CALLERID", "WAZUH-ALERT <9999>")
    timeout_ms = getenv_int("ASTERISK_TIMEOUT_MS", 30000)
    socket_timeout = getenv_int("ISSABEL_SOCKET_TIMEOUT", DEFAULT_TIMEOUT)

    missing = [
        name
        for name, value in {
            "ISSABEL_HOST": host,
            "AMI_USER": username,
            "AMI_PASS": secret,
            "TARGET_NUMBER": target_number,
        }.items()
        if not value
    ]
    if missing:
        raise RuntimeError(f"Missing required settings: {', '.join(missing)}")

    with socket.create_connection((host, port), timeout=socket_timeout) as sock:
        sock.settimeout(socket_timeout)
        ami_expect(sock, "Asterisk Call Manager")

        ami_send(sock, "Action: Login")
        ami_send(sock, f"Username: {username}")
        ami_send(sock, f"Secret: {secret}")
        ami_send(sock, "")
        ami_expect(sock, "Success")

        ami_send(sock, "Action: Originate")
        ami_send(sock, f"Channel: {channel_prefix}/{target_number}@{context}")
        ami_send(sock, f"Context: {context}")
        ami_send(sock, f"Exten: {extension}")
        ami_send(sock, f"Priority: {priority}")
        ami_send(sock, f"CallerID: {caller_id}")
        ami_send(sock, f"Timeout: {timeout_ms}")
        ami_send(sock, "Async: true")
        ami_send(sock, f"Variable: ALERT_MSG={message}")
        ami_send(sock, "")
        originate_response = ami_expect(sock, "Response")

        ami_send(sock, "Action: Logoff")
        ami_send(sock, "")

    return originate_response


def main(argv=None):
    args = parse_args(argv)
    threshold = getenv_int("ALERT_LEVEL_THRESHOLD", DEFAULT_THRESHOLD)
    cooldown_seconds = getenv_int("ALERT_CALL_COOLDOWN", DEFAULT_COOLDOWN)
    target_number = os.getenv("TARGET_NUMBER", "").strip()
    required_groups = [
        group.strip()
        for group in os.getenv("ALERT_REQUIRED_GROUPS", "").split(",")
        if group.strip()
    ]

    try:
        alert = load_alert(args.stdin_file)
        level = alert_level(alert)

        if level < threshold:
            append_log(args.log_file, f"Skip: level {level} < threshold {threshold}")
            return 0

        if required_groups:
            groups = set(alert_groups(alert))
            if not groups.intersection(required_groups):
                append_log(
                    args.log_file,
                    f"Skip: rule groups {sorted(groups)} not in required groups {required_groups}",
                )
                return 0

        skip, wait_seconds = should_skip_for_cooldown(alert, args.state_file, cooldown_seconds)
        if skip:
            append_log(args.log_file, f"Skip: cooldown active for {wait_seconds}s")
            return 0

        message = build_alert_message(alert)
        response = originate_call(message, target_number)
        append_log(args.log_file, f"Call triggered to {target_number}. Response: {response.strip()}")
        print("Call triggered")
        return 0
    except Exception as exc:
        append_log(args.log_file, f"Error: {exc}")
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
