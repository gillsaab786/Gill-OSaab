import unittest

from helpers import load

try:
    import PySide6  # noqa: F401
    HAVE_QT = True
except ImportError:
    HAVE_QT = False


class FakeBackend:
    def __init__(self, ok=True):
        self.ok = ok
        self.f = {"sandbox_windows_apps": "on", "screen_off_overnight": "off", "screen_off_idle_seconds": "15"}
        self.u = {"all": "on", "os": "on", "apps": "on", "containers": "on"}
        self.calls = []

    def features(self):
        return dict(self.f)

    def updates(self):
        return dict(self.u)

    def set_value(self, filename, key, value):
        self.calls.append(("set", filename, key, value))
        if self.ok:
            (self.u if filename == "updates.conf" else self.f)[key] = value
        return self.ok

    def run(self, cmd, wait=True):
        self.calls.append(tuple(cmd))
        return True

    def have(self, tool):
        return True

    def service_active(self, unit):
        return True

    def module_loaded(self, name):
        return True

    def kde_night_light(self):
        return False

    def color_scheme(self):
        return "GillOSaabDark"


@unittest.skipUnless(HAVE_QT, "PySide6 not installed")
class SettingsApp(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from PySide6.QtWidgets import QApplication, QMessageBox
        cls.gs = load("usr/bin/gosaab-settings")
        cls.app = QApplication.instance() or QApplication([])
        QMessageBox.warning = staticmethod(lambda *a, **k: None)

    def test_switches_reflect_files(self):
        b = FakeBackend()
        b.u["apps"] = "off"
        w = self.gs.Settings(b)
        self.assertTrue(w.switches[("updates.conf", "os")][0].isChecked())
        self.assertFalse(w.switches[("updates.conf", "apps")][0].isChecked())
        self.assertTrue(w.switches[("features.conf", "sandbox_windows_apps")][0].isChecked())

    def test_master_switch_disables_others(self):
        b = FakeBackend()
        w = self.gs.Settings(b)
        w.switches[("updates.conf", "all")][0].setChecked(False)
        self.assertIn(("set", "updates.conf", "all", "off"), b.calls)
        for key in ("os", "apps", "containers"):
            self.assertFalse(w.switches[("updates.conf", key)][0].isEnabled())
        w.switches[("updates.conf", "all")][0].setChecked(True)
        self.assertTrue(w.switches[("updates.conf", "os")][0].isEnabled())

    def test_failed_save_reverts_switch(self):
        b = FakeBackend(ok=False)
        w = self.gs.Settings(b)
        sw = w.switches[("updates.conf", "os")][0]
        sw.setChecked(False)
        self.assertTrue(sw.isChecked(), "switch flips back when saving fails")

    def test_optional_features_are_off_and_locked(self):
        w = self.gs.Settings(FakeBackend())
        for key in ("vpn", "cloud_drives", "phone_link"):
            sw = w.switches[("features.conf", key)][0]
            self.assertFalse(sw.isChecked())
            self.assertFalse(sw.isEnabled())

    def test_every_page_builds(self):
        w = self.gs.Settings(FakeBackend())
        self.assertEqual(w.stack.count(), 6)
        for i in range(6):
            w.nav.setCurrentRow(i)
            self.assertEqual(w.stack.currentIndex(), i)

    def test_apply_dark_light(self):
        b = FakeBackend()
        w = self.gs.Settings(b)
        w.apply_scheme("GillOSaabLight")
        self.assertIn(("plasma-apply-colorscheme", "GillOSaabLight"), b.calls)
        self.assertIn(("/usr/libexec/plasma-changeicons", "Papirus-Light"), b.calls)


if __name__ == "__main__":
    unittest.main()
