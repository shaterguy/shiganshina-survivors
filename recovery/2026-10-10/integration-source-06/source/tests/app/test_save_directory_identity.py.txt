"""Static wiring regression; actual disk migration belongs to persistence tests."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class SaveDirectoryIdentityTests(unittest.TestCase):
    def test_current_controller_keeps_delivered_legacy_subdirectory(self):
        controller = (ROOT / "game/app/run_controller.gd").read_text()
        legacy = (ROOT / "game/persistence/save_store.gd").read_text()
        historical_default = re.search(r'_init\(directory: String = "([^"]+)"', legacy).group(1)
        current = re.search(r'var save_store = Save.new\("([^"]+)"', controller).group(1)
        self.assertEqual(historical_default, "user://saves")
        self.assertEqual(current, historical_default)

    def test_controller_recognizes_all_v2_terminal_phases(self):
        controller = (ROOT / "game/app/run_controller.gd").read_text()
        terminal = re.search(r'const TERMINAL := (\[[^\n]+\])', controller).group(1)
        for phase in ("dead", "won", "abandoned"):
            self.assertIn('"'+phase+'"', terminal)


if __name__ == "__main__":
    unittest.main()
