#!/bin/bash

backup_file_if_exists() {
  local file="$1"
  if [ -f "$file" ]; then
    local safe_name
    safe_name=$(echo "$file" | sed 's#/#_#g')
    cp "$file" "$BACKUP_DIR/${safe_name}.bak"
  fi
}

prompt_tty() {
  local var_name="$1"
  local prompt_text="$2"
  local value=""
  if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    read -r -p "$prompt_text" value </dev/tty >/dev/tty 2>/dev/tty
  else
    read -r -p "$prompt_text" value
  fi
  printf -v "$var_name" '%s' "$value"
}

upsert_managed_block() {
  local file="$1"
  local marker="$2"
  local content="$3"

  python3 - "$file" "$marker" "$content" <<'PY'
import sys
from pathlib import Path

file_path = Path(sys.argv[1])
marker = sys.argv[2]
content = sys.argv[3]
start = f"<!-- {marker}:BEGIN -->"
end = f"<!-- {marker}:END -->"
block = f"{start}\n{content}\n{end}"
text = file_path.read_text(encoding="utf-8")

if start in text and end in text:
    s = text.index(start)
    e = text.index(end, s) + len(end)
    text = text[:s] + block + text[e:]
elif content in text:
    pass
elif "</ossec_config>" in text:
    text = text.replace("</ossec_config>", block + "\n</ossec_config>", 1)
else:
    raise SystemExit("Missing </ossec_config> in ossec.conf")

file_path.write_text(text, encoding="utf-8")
PY
}
