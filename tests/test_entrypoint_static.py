import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENTRYPOINT = ROOT / "install-wazuh-misp-full.sh"


class EntrypointStaticTests(unittest.TestCase):
    def read_entrypoint(self):
        return ENTRYPOINT.read_text(encoding="utf-8")

    def test_one_line_entrypoint_does_not_prefer_stale_local_server_script(self):
        text = self.read_entrypoint()
        self.assertNotIn('if [ -f "$SERVER_SCRIPT" ]; then', text)
        self.assertNotIn('exec bash "$SERVER_SCRIPT" "$@"', text)

    def test_one_line_entrypoint_downloads_server_script_and_shared_library(self):
        text = self.read_entrypoint()
        self.assertIn('server_wazuh_misp_setup.sh', text)
        self.assertIn('lib/wazuh_misp_common.sh', text)
        self.assertIn('mkdir -p "$TMP_DIR/lib"', text)
        self.assertIn('exec bash "$TMP_DIR/server_wazuh_misp_setup.sh" "$@"', text)


if __name__ == "__main__":
    unittest.main()
