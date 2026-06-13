import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "server_wazuh_misp_setup.sh"


class TelegramFixTests(unittest.TestCase):
    def read_server_script(self):
        return SCRIPT.read_text(encoding="utf-8")

    def test_wazuh_called_custom_telegram_file_is_generated_from_template(self):
        text = self.read_server_script()
        self.assertIn('cat > "$TELEGRAM_WRAPPER_FILE" <<EOF', text)
        self.assertNotIn('cat > "$TELEGRAM_PY_FILE" <<EOF', text)

    def test_generated_custom_telegram_expands_token_and_chat_id(self):
        text = self.read_server_script()
        match = re.search(
            r'cat > "\$TELEGRAM_WRAPPER_FILE" <<EOF\n(?P<body>.*?)\nEOF',
            text,
            re.DOTALL,
        )
        self.assertIsNotNone(match, "custom-telegram heredoc not found")
        body = match.group("body")
        self.assertIn('BOT_TOKEN = os.getenv("TELEGRAM_TOKEN", "${TELEGRAM_TOKEN}").strip()', body)
        self.assertIn('CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "${TELEGRAM_CHAT_ID}").strip()', body)

    def test_deployment_summary_points_to_wazuh_called_custom_telegram_file(self):
        text = self.read_server_script()
        self.assertIn('Telegram Integration: $TELEGRAM_WRAPPER_FILE', text)
        self.assertNotIn('Telegram Integration: $TELEGRAM_PY_FILE', text)


if __name__ == "__main__":
    unittest.main()
