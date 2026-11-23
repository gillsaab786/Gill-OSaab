import importlib.machinery
import importlib.util
import unittest
from types import SimpleNamespace

from helpers import ROOT

PATH = ROOT / "files/core-system/usr/libexec/gill-osaab/gosaab-gamepad"
loader = importlib.machinery.SourceFileLoader("gamepad", str(PATH))
spec = importlib.util.spec_from_loader("gamepad", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)


class Gamepad(unittest.TestCase):
    def test_deadzone_and_curve(self):
        self.assertEqual(mod.curve(0.1), 0.0)
        self.assertEqual(mod.curve(-0.1), 0.0)
        self.assertAlmostEqual(mod.curve(1.0), 1.0)
        self.assertAlmostEqual(mod.curve(-1.0), -1.0)
        self.assertLess(mod.curve(0.5), 0.5)  # gentle near the middle for precise pointing

    def test_normalise_stick(self):
        info = SimpleNamespace(min=-32768, max=32767)
        self.assertAlmostEqual(mod.normalise(32767, info), 1.0, places=3)
        self.assertAlmostEqual(mod.normalise(-32768, info), -1.0, places=3)
        self.assertAlmostEqual(mod.normalise(0, info), 0.0, places=3)

    def test_every_button_has_an_action(self):
        for name in ("BTN_SOUTH", "BTN_EAST", "BTN_NORTH", "BTN_WEST", "BTN_START", "BTN_MODE", "BTN_TL", "BTN_TR"):
            self.assertIn(name, mod.BUTTONS)


if __name__ == "__main__":
    unittest.main()
