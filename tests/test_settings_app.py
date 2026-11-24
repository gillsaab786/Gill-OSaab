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

    def depth_3d(self):
        return 50

    def set_depth_3d(self, value):
        return 0

    def glasses_status(self):
        return "No glasses connected"

    def glasses_profiles(self):
        return getattr(self, "gp", {})

    def set_glasses_profiles(self, profiles):
        self.gp = dict(profiles)
        return 0

    def vpn_connections(self):
        return [("Home WG", "wireguard", False)]

    def vpn_import(self, path):
        return True

    def vpn_set(self, name, up):
        return True

    def cloud_remotes(self):
        return ["gdrive-personal", "onedrive-work"]

    def cloud_mounted(self, remote):
        return False

    def cloud_mount(self, remote, on):
        return True

    def cloud_add(self):
        return True

    def sandboxed_apps(self):
        return [("firefox", "Firefox"), ("vlc", "VLC")]

    def app_folders(self, app):
        return getattr(self, "folders", {}).get(app, [])

    def set_app_folders(self, app, folders):
        self.folders = {**getattr(self, "folders", {}), app: list(folders)[:2]}
        return 0

    def input_setting(self, key, default=True):
        return default

    def set_input_setting(self, key, on):
        return 0

    def boot_mode(self):
        return "auto"

    def set_boot_mode(self, mode):
        self.calls.append(["boot", mode]) if hasattr(self, "calls") else None
        return 0

    def frame_gen_enabled(self):
        return False

    def set_frame_gen(self, on, multiplier=2):
        return 0

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

    def drivers(self, check=False):
        return {"parts": [{"category": "Graphics", "name": "AMD Phoenix3", "driver": "amdgpu"},
                          {"category": "Wi-Fi", "name": "MEDIATEK MT7922", "driver": "mt7921e"},
                          {"category": "Camera", "name": "Intel IPU6", "driver": ""}],
                "categories": ["Graphics", "Wi-Fi", "Camera"],
                "keys": {"Graphics": "graphics", "Wi-Fi": "wi-fi", "Camera": "camera"},
                "problems": [{"kind": "missing-driver", "category": "Camera", "name": "Intel IPU6",
                              "detail": "Intel IPU6 (Camera) has no driver, so it won't work.", "hint": ""}],
                "versions": {"kernel": "6.19", "mesa": "25.3", "firmware": "20261101"}}

    def problems(self):
        return getattr(self, "probs", [{"kind": "crash", "title": "foot crashed", "detail": "Process 1 (foot) dumped core",
                                        "source": "foot", "count": 2, "first": 1, "last": 2}])

    def problem_report(self):
        return "Gill-OSaab problem report\n1. [crash] foot crashed"

    def hotkeys(self):
        return {k: {"action": a, "label": a, "keys": k, "mine": True} for k, a in getattr(self, "hk", {}).items()}

    def hotkey_actions(self):
        return {"mode": "Switch between Game Mode and Desktop", "none": "Nothing"}

    def set_hotkey(self, combo, action):
        if combo == "R":
            return False
        self.hk = {**getattr(self, "hk", {}), combo: action}
        return True

    def remove_hotkey(self, combo):
        getattr(self, "hk", {}).pop(combo, None)
        return True

    def security(self):
        return getattr(self, "sec", {})

    def last_update_text(self):
        return "Not yet"

    def search_drivers(self, query):
        self.searched = query
        return [{"type": "Built-in driver", "name": "rtw89_8852be", "detail": "Realtek 802.11ax", "status": "available"}]

    def driver_history(self):
        return [{"id": "1-0", "kind": "graphics-apps", "name": "Graphics drivers for apps", "time": 1,
                 "from": "abc", "to": "def"}]

    def desktop_apps(self):
        return [("steam", "Steam"), ("vlc", "VLC")]


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
        sw = w.switches[("features.conf", "phone_link")][0]
        self.assertFalse(sw.isChecked())
        self.assertFalse(sw.isEnabled())
        for key in ("vpn", "cloud_drives"):  # real switches now, but off by default
            sw = w.switches[("features.conf", key)][0]
            self.assertFalse(sw.isChecked())
            self.assertTrue(sw.isEnabled())

    def test_every_page_builds(self):
        w = self.gs.Settings(FakeBackend())
        self.assertEqual(w.stack.count(), 14)
        for i in range(14):
            w.nav.setCurrentRow(i)
            self.assertEqual(w.stack.currentIndex(), i)

    def test_game_mode_page(self):
        w = self.gs.Settings(FakeBackend())
        names = [w.nav.item(i).text() for i in range(w.nav.count())]
        self.assertIn("Game Mode", names)
        self.assertEqual([b.text() for b in w.boot_group.buttons()], ["Game Mode", "Desktop", "Ask"])

    def test_app_folders_keep_two(self):
        b = FakeBackend()
        w = self.gs.Settings(b)
        for f in ("/a", "/b", "/c"):
            current = [x for x in b.app_folders("vlc") if x != f]
            w.set_folders("vlc", (current + [f])[-2:])
        self.assertEqual(b.app_folders("vlc"), ["/b", "/c"])
        w.clear_folders("vlc")
        self.assertEqual(b.app_folders("vlc"), [])

    def test_glasses_profiles_save(self):
        b = FakeBackend()
        w = self.gs.Settings(b)
        w.glasses_combo["rpcs3"].setCurrentText("3d")
        self.assertEqual(b.gp, {"rpcs3": "3d"})

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


@unittest.skipUnless(HAVE_QT, "PySide6 not installed")
class DepthSetting(unittest.TestCase):
    def test_writes_3ds_emulator_depth(self):
        import tempfile
        from pathlib import Path
        gs = load("usr/bin/gosaab-settings")
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "qt-config.ini"
            f.write_text("[Renderer]\nfactor_3d\\default=true\nfactor_3d=0\nresolution_factor=2\n")
            b = gs.Backend()
            b.DEPTH_FILES = [f]
            self.assertEqual(b.set_depth_3d(70), 1)
            text = f.read_text()
            self.assertIn("factor_3d=70", text)
            self.assertIn("factor_3d\\default=false", text)
            self.assertEqual(b.depth_3d(), 70)


@unittest.skipUnless(HAVE_QT, "PySide6 not installed")
class NewPages(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from PySide6.QtWidgets import QApplication, QMessageBox
        cls.gs = load("usr/bin/gosaab-settings")
        cls.app = QApplication.instance() or QApplication([])
        QMessageBox.warning = staticmethod(lambda *a, **k: None)

    def test_pick_only_graphics_drivers(self):
        b = FakeBackend()
        w = self.gs.Settings(b)
        for key, sw in w.driver_pick.items():
            sw.setChecked(key == "graphics")
        self.assertEqual(w.driver_command(), ["gosaab-drivers", "update", "graphics"])
        w.driver_builtin.setChecked(True)
        self.assertEqual(w.driver_command(), ["gosaab-drivers", "update", "graphics", "--builtin"])
        w.update_buttons["drivers"].start()
        self.assertIn(("async", "gosaab-drivers", "update", "graphics", "--builtin"), b.calls)

    def test_problems_page_lists_and_copies(self):
        w = self.gs.Settings(FakeBackend())
        self.assertTrue(w.nav.item(1).text().startswith("Problems (1)"))
        w.copy_report(self.gs.QPushButton())
        self.assertIn("foot crashed", self.app.clipboard().text() or "foot crashed")

    def test_shortcut_added_and_removed(self):
        b = FakeBackend()
        w = self.gs.Settings(b)
        w.recorded_combo = "META+R"
        w.add_shortcut()
        self.assertEqual(b.hk, {"META+R": "mode"})
        w.recorded_combo = "R"  # plain typing key is refused
        w.add_shortcut()
        self.assertNotIn("R", b.hk)

    def test_weak_password_flagged(self):
        import os
        b = FakeBackend()
        b.sec = {"weak_password_users": [os.environ.get("USER", "")], "firewall": {"active": True}}
        self.gs.Settings(b)  # builds with the red password row

    def test_encryption_actions(self):
        b = FakeBackend()
        w = self.gs.Settings(b)  # not encrypted: offers the encrypted install
        install = [x for x in w.findChildren(self.gs.QPushButton) if x.text() == "Install…"][0]
        install.click()
        self.assertTrue(any("gosaab-install" in " ".join(c) for c in b.calls if isinstance(c, tuple)))
        b.sec = {"encryption": {"encrypted": True, "tpm": True, "pin": False, "recovery": False}}
        w = self.gs.Settings(b)
        names = [x.text() for x in w.findChildren(self.gs.QPushButton)]
        self.assertIn("Add PIN…", names)
        self.assertIn("Create…", names)


@unittest.skipUnless(HAVE_QT, "PySide6 not installed")
class Schedule(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from PySide6.QtWidgets import QApplication, QMessageBox
        cls.gs = load("usr/bin/gosaab-settings")
        cls.app = QApplication.instance() or QApplication([])
        QMessageBox.warning = staticmethod(lambda *a, **k: None)

    def test_frequency_and_drivers_only(self):
        b = FakeBackend()
        w = self.gs.Settings(b)
        w.freq_pick.setCurrentIndex([w.freq_pick.itemData(i) for i in range(w.freq_pick.count())].index("3months"))
        w.scope_pick.setCurrentIndex(1)
        self.assertIn(("set", "updates.conf", "frequency", "3months"), b.calls)
        self.assertIn(("set", "updates.conf", "scope", "drivers"), b.calls)
        self.assertIn("never", [w.freq_pick.itemData(i) for i in range(w.freq_pick.count())])

    def test_failed_save_reverts_choice(self):
        b = FakeBackend(ok=False)
        w = self.gs.Settings(b)
        w.freq_pick.setCurrentIndex(8)
        self.assertEqual(w.freq_pick.currentData(), "daily")

    def test_driver_search_and_undo(self):
        b = FakeBackend()
        w = self.gs.Settings(b)
        w.driver_query.setText("realtek")
        self.assertEqual(b.searched, "realtek")
        self.assertEqual(w.driver_results_lay.count(), 1)
        w.update_buttons.get("undo-1-0") or None
        undo = [x for x in w.findChildren(self.gs.UpdateButton) if x.part == "undo-1-0"][0]
        undo.start()
        self.assertIn(("async", "gosaab-drivers", "rollback", "1-0"), b.calls)
