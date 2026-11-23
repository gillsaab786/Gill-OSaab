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

    def decky_plugin_installed(self):
        return False

    def run_async(self, cmd, parent, done):
        self.calls.append(("async",) + tuple(cmd))
        done(self.async_code)
        return None

    async_code = 0

    def versions(self):
        return {"gill_osaab": "1.2.0", "os": "45", "kernel": "6.19", "wine": "wine-11.21", "proton": "GE-Proton10-30",
                "image": getattr(self, "image", "ostree-unverified-registry:ghcr.io/x/gill-osaab-desktop:latest")}

    def hardware(self):
        return {"model": {"name": "GPD G1619-04", "bios_version": "2.11", "bios_date": "2025"}, "cpu": "Ryzen",
                "gpus": [{"vendor": "NVIDIA Corporation", "device": "RTX 2060", "driver": "nouveau"}],
                "network": [{"kind": "Wi-Fi", "vendor": "MEDIATEK", "device": "MT7922", "driver": "mt7921e"}],
                "nvidia": getattr(self, "nvidia", True), "support_page": "https://gpd.hk/"}

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
        self.assertEqual(w.stack.count(), 8)
        for i in range(8):
            w.nav.setCurrentRow(i)
            self.assertEqual(w.stack.currentIndex(), i)

    def test_apply_dark_light(self):
        b = FakeBackend()
        w = self.gs.Settings(b)
        w.apply_scheme("GillOSaabLight")
        self.assertIn(("plasma-apply-colorscheme", "GillOSaabLight"), b.calls)
        self.assertIn(("/usr/libexec/plasma-changeicons", "Papirus-Light"), b.calls)


@unittest.skipUnless(HAVE_QT, "PySide6 not installed")
class SettingsUpdates(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from PySide6.QtWidgets import QApplication, QMessageBox
        cls.gs = load("usr/bin/gosaab-settings")
        cls.app = QApplication.instance() or QApplication([])
        QMessageBox.warning = staticmethod(lambda *a, **k: None)

    def test_every_part_has_an_update_button(self):
        w = self.gs.Settings(FakeBackend())
        for part in ("all", "os", "android", "proton", "wine", "apps", "containers", "decky",
                     "drivers", "firmware", "bios", "nvidia"):
            self.assertIn(part, w.update_buttons, part)

    def test_update_button_runs_updater_and_shows_result(self):
        b = FakeBackend()
        b.async_code = 4
        w = self.gs.Settings(b)
        btn = w.update_buttons["proton"]
        btn.click()
        self.assertIn(("async", "gosaab-update-component", "proton"), b.calls)
        self.assertEqual(btn.text(), "Up to date")
        self.assertTrue(btn.isEnabled())

    def test_nvidia_switch_hidden_on_nvidia_edition(self):
        b = FakeBackend()
        b.image = "ostree-unverified-registry:ghcr.io/x/gill-osaab-desktop-nvidia:latest"
        self.assertNotIn("nvidia", self.gs.Settings(b).update_buttons)
        b2 = FakeBackend()
        b2.nvidia = False
        self.assertNotIn("nvidia", self.gs.Settings(b2).update_buttons)

    def test_bios_not_available_offers_support_page(self):
        from PySide6.QtWidgets import QMessageBox
        b = FakeBackend()
        b.async_code = 3
        w = self.gs.Settings(b)
        shown = []
        w.bios_not_available = lambda: shown.append(True)
        w.update_buttons["bios"].click()
        self.assertEqual(shown, [True])
        self.assertEqual(w.update_buttons["bios"].text(), "Not available")
        del QMessageBox  # keep linters quiet

    def test_search_filters_pages(self):
        w = self.gs.Settings(FakeBackend())
        w.search.setText("bios")
        visible = [w.nav.item(i).text() for i in range(w.nav.count()) if not w.nav.item(i).isHidden()]
        self.assertIn("Device & Drivers", visible)
        self.assertNotIn("Appearance", visible)
        w.search.setText("")
        self.assertTrue(all(not w.nav.item(i).isHidden() for i in range(w.nav.count())))


if __name__ == "__main__":
    unittest.main()
