import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "server_wazuh_misp_setup.sh"


class ServerExistingFileReplaceTests(unittest.TestCase):
    def read_script(self):
        return SCRIPT.read_text(encoding="utf-8")

    def test_existing_files_are_deleted_when_user_confirms_update(self):
        text = self.read_script()
        self.assertIn('DELETE_ON_UPDATE_FILES=(', text)
        self.assertIn('rm -f "$file"', text)
        self.assertIn('if [[ "$UPDATE_FILE" =~ ^[Yy]$ ]]; then', text)


if __name__ == "__main__":
    unittest.main()
