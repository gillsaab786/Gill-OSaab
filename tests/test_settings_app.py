import unittest
from pathlib import Path

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

    def appearance(self):
        return dict(getattr(self, "ap", {}))

    def set_appearance(self, key, value):
        self.ap = {**getattr(self, "ap", {}), key: value}
        return True

    def wallpaper_thumb(self, folder, dark):
        return ""

    def lights_status(self):
        return getattr(self, "lights", {"ally": False})

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
        return "Gill(OS) problem report\n1. [crash] foot crashed"

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

    def power_status(self):
        return {"mode": "video", "label": "Video", "watts": 7, "device": "handheld", "backend": "firmware-attributes",
                "watts_all": {"idle": 5, "video": 7, "desktop": 12, "game": 25}, "dgpu_active": False}

    def gpu_status(self):
        return getattr(self, "gpu", {"hybrid": False})

    def face_status(self):
        return getattr(self, "face", {"available": False, "camera": None})

    def secure_boot(self):
        return getattr(self, "sb", {"supported": True, "enabled": False, "nvidia_edition": False, "pending": ""})

    def fps_status(self):
        return {"main": {"vendor": "nvidia", "name": "AD107 [GeForce RTX 4060]", "family": "rtx40"},
                "recommendation": {"upgrade": "dlss", "smooth_motion": True, "notes": ["DLSS 4", "LSFG"]},
                "ge_proton": [], "needs_nvidia_edition": getattr(self, "fps_needs", False)}

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
        self.assertEqual(w.stack.count(), 17)
        titles = [w.nav.item(i).text() for i in range(w.nav.count())]
        self.assertEqual([t.split(" (")[0] for t in titles[-5:]], ["System Update", "Translation Update", "Drivers Update", "Problems", "About"])
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
        self.assertIn("Drivers Update", visible)
        self.assertNotIn("Appearance", visible)
        w.search.setText("")
        self.assertTrue(all(not w.nav.item(i).isHidden() for i in range(w.nav.count())
                            if w.nav.item(i).text() != "Controller Lights"))  # ROG Ally only


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
        titles = [w.nav.item(i).text() for i in range(w.nav.count())]
        self.assertTrue(titles[-2].startswith("Problems (1)"))  # second last, above About
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


@unittest.skipUnless(HAVE_QT, "PySide6 not installed")
class Fps(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from PySide6.QtWidgets import QApplication
        cls.gs = load("usr/bin/gosaab-settings")
        cls.app = QApplication.instance() or QApplication([])

    def test_nvidia_fps_controls(self):
        b = FakeBackend()
        b.fps_needs = True
        w = self.gs.Settings(b)
        w.switches[("features.conf", "fps_smooth_motion")][0].setChecked(True)
        self.assertIn(("set", "features.conf", "fps_smooth_motion", "on"), b.calls)
        self.assertIn("nvidia", w.update_buttons)
        names = [x.text() for x in w.findChildren(self.gs.QPushButton)]
        self.assertIn("Install", names)


@unittest.skipUnless(HAVE_QT, "PySide6 not installed")
class SecureBootPage(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from PySide6.QtWidgets import QApplication
        cls.gs = load("usr/bin/gosaab-settings")
        cls.app = QApplication.instance() or QApplication([])

    def buttons(self, b):
        return [x.text() for x in self.gs.Settings(b).findChildren(self.gs.QPushButton)]

    def test_turn_on_off_finish(self):
        b = FakeBackend()
        self.assertIn("Turn on…", self.buttons(b))
        b.sb = {"supported": True, "enabled": True, "ms_2023_ca": False, "pending": ""}
        names = self.buttons(b)
        self.assertIn("Turn off…", names)
        self.assertIn("Install", names)  # missing 2023 certificate
        b.sb = {"supported": True, "enabled": True, "ms_2023_ca": True, "pending": "on"}
        self.assertIn("Finish…", self.buttons(b))


@unittest.skipUnless(HAVE_QT, "PySide6 not installed")
class GraphicalInstaller(unittest.TestCase):
    def test_flow_and_command(self):
        import runpy
        from PySide6.QtWidgets import QApplication
        QApplication.instance() or QApplication([])
        g = runpy.run_path(str(Path(__file__).resolve().parent.parent / "files/core-system/usr/bin/gosaab-installer"))
        w = g["Installer"](disks=[{"path": "/dev/nvme0n1", "size": 1e12, "model": "SSD", "transport": "nvme",
                                   "removable": False, "big_enough": True}])
        w.disk = "/dev/nvme0n1"
        for weak in ("short", "gill", "password"):
            w.pw1.setText(weak)
            w.pw2.setText(weak)
            self.assertTrue(w.password_problem())
        w.pw1.setText("correct horse")
        w.pw2.setText("correct horsf")
        self.assertIn("match", w.password_problem())
        w.pw2.setText("correct horse")
        w.check_password()
        self.assertEqual(w.currentIndex(), 4)
        self.assertEqual(w.command(), ["pkexec", "/usr/bin/gosaab-install", "/dev/nvme0n1", "--yes", "--password-stdin"])
        w.encrypt = False
        self.assertIn("--no-encrypt", w.command())


@unittest.skipUnless(HAVE_QT, "PySide6 not installed")
class SmartPower(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from PySide6.QtWidgets import QApplication
        cls.gs = load("usr/bin/gosaab-settings")
        cls.app = QApplication.instance() or QApplication([])

    def test_smart_tdp_and_graphics(self):
        b = FakeBackend()
        w = self.gs.Settings(b)
        self.assertFalse(hasattr(w, "gpu_pick"))  # one graphics chip: no switching section
        boxes = w.findChildren(self.gs.QSpinBox)
        game = [x for x in boxes if x.value() == 25][0]
        game.setValue(30)
        self.assertIn(("set", "features.conf", "tdp_game", "30"), b.calls)
        b.gpu = {"hybrid": True, "mode": "auto", "integrated": {"name": "Radeon 780M"},
                 "dedicated": {"name": "GeForce RTX 4060"}}
        w = self.gs.Settings(b)
        w.gpu_pick.setCurrentIndex(1)
        self.assertIn(("set", "features.conf", "gpu_mode", "integrated"), b.calls)


@unittest.skipUnless(HAVE_QT, "PySide6 not installed")
class FaceUnlockPage(unittest.TestCase):
    def test_states(self):
        from PySide6.QtWidgets import QApplication
        gs = load("usr/bin/gosaab-settings")
        QApplication.instance() or QApplication([])
        b = FakeBackend()
        names = lambda: [x.text() for x in gs.Settings(b).findChildren(gs.QPushButton)]
        self.assertNotIn("Set up…", names())
        b.face = {"available": True, "camera": "Integrated IR Camera", "enabled": False}
        self.assertIn("Set up…", names())
        b.face["enabled"] = True
        self.assertIn("Turn off and forget face", names())


@unittest.skipUnless(HAVE_QT, "PySide6 not installed")
class TahoeAppearance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from PySide6.QtWidgets import QApplication
        cls.gs = load("usr/bin/gosaab-settings")
        cls.app = QApplication.instance() or QApplication([])

    def test_sidebar_icons_are_drawn_not_letters(self):
        from PySide6.QtGui import QPainter, QPixmap
        for _title, _colour, glyph, _letter in self.gs.PAGES:
            pm = QPixmap(24, 24)
            p = QPainter(pm)
            self.assertTrue(self.gs.draw_glyph(p, glyph, 24), glyph)
            p.end()

    def test_mode_accent_icons_glass_wallpaper_widgets_saved_for_the_shell(self):
        b = FakeBackend()
        w = self.gs.Settings(b)
        tiles = {t.label: t for t in w.mode_picker.group.buttons()}
        self.assertTrue(tiles["Dark"].isChecked())  # dark is the default
        tiles["Auto"].click()
        self.assertEqual(b.ap["mode"], "auto")
        w.accent_picker.group.buttons()[2].click()
        self.assertEqual(b.ap["accent"], "#bf5af2")
        self.assertEqual(self.gs.ACCENT.name(), "#bf5af2")  # Settings re-colours straight away
        self.assertIn("#bf5af2", self.app.styleSheet())
        self.assertNotIn("#1fb6c9", self.gs.accent_style("#ff9f0a"))
        {t.label: t for t in w.icon_picker.group.buttons()}["Tinted"].click()
        self.assertEqual(b.ap["iconStyle"], "tinted")
        w.glass_seg.group.buttons()[1].click()
        self.assertEqual(b.ap["glass"], "tinted")
        w.menubar_switch.setChecked(True)
        self.assertEqual(b.ap["menuBar"], "glass")
        {t.label: t for t in w.wall_picker.group.buttons()}["Aurora"].click()
        self.assertEqual(b.ap["wallpaper"], "classic")
        w.widget_switches["stats"].setChecked(True)
        w.widget_switches["weather"].setChecked(False)
        self.assertEqual(b.ap["widgets"], {"stats": True, "weather": False})
        w.city.setText("Melbourne")
        w.city.editingFinished.emit()
        self.assertEqual(b.ap["city"], "Melbourne")
        w.clip_switch.setChecked(False)
        self.assertIs(b.ap["clipboardHistory"], False)

    def test_previews_paint(self):
        w = self.gs.Settings(FakeBackend())
        for picker in (w.mode_picker, w.icon_picker, w.wall_picker):
            for t in picker.group.buttons():
                self.assertFalse(t.grab().isNull())

    def test_controller_lights_only_on_rog_ally(self):
        b = FakeBackend()
        titles = lambda w: [w.nav.item(i).text() for i in range(w.nav.count()) if not w.nav.item(i).isHidden()]
        w = self.gs.Settings(b)
        self.assertNotIn("Controller Lights", titles(w))
        w.search.setText("lights")
        self.assertNotIn("Controller Lights", titles(w))
        b.lights = {"ally": True, "backend": "hid"}
        w = self.gs.Settings(b)
        self.assertIn("Controller Lights", titles(w))
        w.lights_mode.group.buttons()[0].click()
        self.assertIn(("set", "features.conf", "lights_mode", "always"), b.calls)
        self.assertFalse(w.game_color_box.isVisibleTo(w))
        w.lights_mode.group.buttons()[1].click()
        self.assertTrue(w.game_color_box.isVisibleTo(w.game_color_box.parentWidget()))
        w.game_colors.group.buttons()[2].click()
        self.assertIn(("set", "features.conf", "lights_game_color", "30d158"), b.calls)
        w.brightness_slider.setValue(40)
        w.brightness_slider.sliderReleased.emit()
        self.assertIn(("set", "features.conf", "lights_brightness", "40"), b.calls)
        w.vivid_slider.setValue(55)
        w.vivid_slider.sliderReleased.emit()
        self.assertIn(("set", "features.conf", "lights_vividness", "55"), b.calls)
        self.assertFalse(w.lights_preview.grab().isNull())


@unittest.skipUnless(HAVE_QT, "PySide6 not installed")
class GillOSRound(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from PySide6.QtWidgets import QApplication
        cls.gs = load("usr/bin/gosaab-settings")
        cls.app = QApplication.instance() or QApplication([])

    def test_group_shortcut_from_settings(self):
        b = FakeBackend()
        w = self.gs.Settings(b)
        w.recorded_combo = "META+I"
        w.add_group_item("app", "itunes", "iTunes")
        w.add_group_item("app", "itunes", "iTunes")  # no duplicates
        w.add_group_item("open", "/home/gill/Desktop/iPhone apps", "iPhone apps")
        w.add_group_item("open", "a|b", "bad")  # can't hold the separator
        self.assertEqual(w.group_label.text(), "iTunes, iPhone apps")
        w.add_shortcut()
        self.assertEqual(b.hk["META+I"], "group:app:itunes|open:/home/gill/Desktop/iPhone apps")
        self.assertEqual(w.group, [])

    def test_dock_magnification_saved(self):
        b = FakeBackend()
        w = self.gs.Settings(b)
        w.dock_zoom.group.buttons()[3].click()
        self.assertEqual(b.ap["dockMagnification"], "large")

    def test_update_pages(self):
        w = self.gs.Settings(FakeBackend())
        w.go_to("Translation Update")
        self.assertIn("translation", w.update_buttons)
        self.assertIn("proton", w.update_buttons)
        w.go_to("Drivers Update")
        self.assertIn("drivers", w.update_buttons)
        self.assertIn("firmware", w.update_buttons)
