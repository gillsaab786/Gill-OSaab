import json
import os
import struct
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from helpers import load


class SharedLibrary(unittest.TestCase):
    def setUp(self):
        self.lib = load("usr/libexec/gill-osaab/gosaab-library")

    def test_vdf_round_trip_and_appid(self):
        obj = {"shortcuts": {"0": {"appid": -123, "AppName": "Mine", "Exe": '"/x"', "tags": {"0": "fav"}}}}
        self.assertEqual(self.lib.vdf_load(self.lib.vdf_dump(obj)), obj)
        a = self.lib.shortcut_appid('"/usr/bin/gio"', "Hollow Knight")
        self.assertLess(a, 0)  # high bit set, stored signed like Steam does

    def test_keeps_your_shortcuts_replaces_ours(self):
        mine = {"appid": 1, "AppName": "My Game", "tags": {}}
        old_ours = self.lib.shortcut_for({"name": "Old", "file": "/x.desktop", "kind": "Windows", "icon": ""})
        merged = self.lib.merge({"shortcuts": {"0": mine, "1": old_ours}},
                                [{"name": "New", "file": "/y.desktop", "kind": "Android", "icon": ""}])
        names = [s["AppName"] for s in merged["shortcuts"].values()]
        self.assertEqual(names, ["My Game", "New"])
        self.assertEqual(merged["shortcuts"]["1"]["LaunchOptions"], 'launch "/y.desktop"')

    def test_finds_games_and_emulators_only(self):
        d = Path(tempfile.mkdtemp())
        (d / "hk.desktop").write_text("[Desktop Entry]\nName=Hollow Knight\nExec=gosaab-open --wine-run \"/p\" hk.exe\nCategories=Game;\n")
        (d / "waydroid.com.supercell.clashroyale.desktop").write_text("[Desktop Entry]\nName=Clash Royale\nExec=waydroid app launch x\nCategories=Game;\n")
        (d / "org.libretro.RetroArch.desktop").write_text("[Desktop Entry]\nName=RetroArch\nExec=retroarch\n")
        (d / "brave.desktop").write_text("[Desktop Entry]\nName=Brave\nExec=brave\nCategories=Network;\n")
        found = {g["name"]: g["kind"] for g in self.lib.games([d])}
        self.assertEqual(found, {"Hollow Knight": "Windows", "Clash Royale": "Android", "RetroArch": "Linux"})

    def test_sync_writes_each_steam_account_but_not_while_steam_runs(self):
        home = Path(tempfile.mkdtemp())
        self.lib.STEAM = home / "Steam"
        (self.lib.STEAM / "userdata/123/config").mkdir(parents=True)
        g = [{"name": "HK", "file": "/hk.desktop", "kind": "Windows", "icon": ""}]
        self.assertEqual(self.lib.write_all(g), 1)
        data = self.lib.vdf_load((self.lib.STEAM / "userdata/123/config/shortcuts.vdf").read_bytes())
        self.assertEqual(data["shortcuts"]["0"]["AppName"], "HK")
        (self.lib.STEAM / "userdata/123/config/shortcuts.vdf").write_bytes(b"\x07garbage")
        self.assertEqual(self.lib.write_all(g), 0)  # unreadable file is left alone
        with mock.patch.object(self.lib, "steam_running", return_value=True), mock.patch("builtins.print"):
            with mock.patch.object(self.lib, "write_all") as w:
                self.lib.main(["sync"])
                w.assert_not_called()


class Emulator3D(unittest.TestCase):
    def test_turns_3d_on_and_off_in_each_emulator(self):
        import importlib.machinery
        import importlib.util
        from helpers import ROOT
        loader = importlib.machinery.SourceFileLoader("gosaab3d", str(ROOT / "files/core-system/usr/bin/gosaab-3d"))
        spec = importlib.util.spec_from_loader("gosaab3d", loader)
        g = importlib.util.module_from_spec(spec)
        loader.exec_module(g)
        home = Path(tempfile.mkdtemp())
        azahar = home / "azahar.ini"
        azahar.write_text("[Renderer]\nrender_3d=0\n[Layout]\nlayout_option=0\n")
        dolphin = home / "GFX.ini"
        dolphin.write_text("[Settings]\nAspectRatio = 0\n")
        rpcs3 = home / "config.yml"
        rpcs3.write_text("Video:\n  Renderer: Vulkan\n  3D Display Mode: Disabled\n")
        ra = home / "core-options.cfg"
        ra.write_text('vb_3dmode = "anaglyph"\n')
        conf = home / "glasses.conf"
        conf.write_text("depth.dolphin=70\ndepth.3ds=30\n")
        g.FILES = {"3ds": [azahar], "dolphin": [dolphin], "rpcs3": [rpcs3], "vb": [ra], "cemu": []}
        found = g.apply(True, conf)
        self.assertTrue(all(found[k] for k in ("3ds", "dolphin", "rpcs3", "vb")))
        a = azahar.read_text()
        self.assertIn("render_3d=1", a)
        self.assertIn("factor_3d=30", a)
        self.assertIn("layout_option=4", a)  # bottom screen in its own window (goes to the touchscreen)
        self.assertIn("[Stereoscopy]\nStereoMode=1\nStereoDepth=70", dolphin.read_text())
        self.assertIn("3D Display Mode: Side-by-Side", rpcs3.read_text())
        self.assertIn('vb_3dmode = "side-by-side"', ra.read_text())
        g.apply(False, conf)
        self.assertIn("render_3d=0", azahar.read_text())
        self.assertIn("3D Display Mode: Disabled", rpcs3.read_text())


class SmartUpdatesAndUndervolt(unittest.TestCase):
    def test_smart_updates_wait_for_a_good_time(self):
        u = load("usr/libexec/gill-osaab/gosaab-update-run")
        self.assertTrue(u.smart_ok("idle", True, False, 15))
        self.assertTrue(u.smart_ok("desktop", True, False, 3))   # night
        self.assertFalse(u.smart_ok("game", True, False, 3))     # never while gaming
        self.assertFalse(u.smart_ok("idle", False, False, 3))    # on battery
        self.assertFalse(u.smart_ok("idle", True, True, 3))      # mobile data
        self.assertFalse(u.smart_ok("desktop", True, False, 15))  # you're using it

    def test_undervolt_command(self):
        import gosaab_power as pw
        self.assertEqual(pw.undervolt_cmd(10), ["ryzenadj", f"--set-coall={0x100000 - 10}"])
        self.assertEqual(pw.undervolt_cmd(0), ["ryzenadj", "--set-coall=0"])
        self.assertEqual(pw.undervolt_cmd(99), ["ryzenadj", f"--set-coall={0x100000 - 30}"])
        self.assertFalse(pw.undervolt_supported("GenuineIntel", True))
        self.assertTrue(pw.undervolt_supported("AuthenticAMD", True))


class Widevine(unittest.TestCase):
    def test_on_once_then_respects_your_choice(self):
        w = load("usr/libexec/gill-osaab/gosaab-widevine")
        w.STATE = Path(tempfile.mkdtemp()) / "Local State"
        w.STATE.write_text(json.dumps({"browser": {"x": 1}}))
        w.main(["ensure"])
        data = json.loads(w.STATE.read_text())
        self.assertTrue(data["brave"]["widevine_opted_in"])
        self.assertEqual(data["browser"], {"x": 1})
        w.main(["off"])
        w.main(["ensure"])
        self.assertFalse(json.loads(w.STATE.read_text())["brave"]["widevine_opted_in"])


if __name__ == "__main__":
    unittest.main()
