import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from helpers import load

import gosaab_lights as gl


class AllyLights(unittest.TestCase):
    def dmi(self, product, board):
        d = Path(tempfile.mkdtemp())
        (d / "product_name").write_text(product)
        (d / "board_name").write_text(board)
        return d

    def test_detects_ally_models_only(self):
        self.assertTrue(gl.is_rog_ally(self.dmi("ROG Ally RC71L_RC71L", "RC71L")))
        self.assertTrue(gl.is_rog_ally(self.dmi("ROG Ally X RC72LA", "RC72LA")))
        self.assertFalse(gl.is_rog_ally(self.dmi("Legion Go 8APU1", "LNVNB161216")))
        self.assertFalse(gl.is_rog_ally(self.dmi("G1619-04", "G1619-04")))

    def test_colour_brightness_and_contrast(self):
        self.assertEqual(gl.shade((255, 0, 0), 100, 100), (255, 0, 0))
        self.assertEqual(gl.shade((255, 0, 0), 50, 100), (128, 0, 0))
        self.assertEqual(gl.shade((255, 0, 0), 100, 0), (255, 255, 255))  # no contrast: white
        self.assertEqual(gl.parse_hex("ff2d55"), (255, 45, 85))
        self.assertEqual(gl.parse_hex("#30d158"), (48, 209, 88))
        self.assertEqual(gl.parse_hex("junk"), (10, 132, 255))

    def test_game_and_desktop_colours(self):
        s = {"lights_mode": "gaming", "lights_color": "0000ff", "lights_game_color": "ff0000",
             "lights_brightness": "100", "lights_vividness": "100"}
        self.assertEqual(gl.wanted(s, gaming=False), ((0, 0, 255), "solid"))
        self.assertEqual(gl.wanted(s, gaming=True), ((255, 0, 0), "solid"))
        self.assertEqual(gl.wanted({**s, "lights_mode": "always"}, gaming=True), ((0, 0, 255), "solid"))
        self.assertIsNone(gl.wanted({**s, "lights_mode": "off"}, gaming=True))
        self.assertIsNone(gl.wanted({**s, "lights_brightness": "0"}, gaming=False))

    def test_hid_packets(self):
        pk = gl.hid_packets((1, 2, 3), "breathing")
        self.assertTrue(all(len(p) == 64 and p[0] == 0x5A for p in pk))
        self.assertEqual(pk[0][1:15], b"ASUS Tech.Inc.")
        self.assertEqual(list(pk[1][:8]), [0x5A, 0xB3, 0, 0x01, 1, 2, 3, gl.SPEED])
        self.assertEqual(list(pk[-2][:2]) + list(pk[-1][:2]), [0x5A, 0xB5, 0x5A, 0xB4])  # set, apply
        off = gl.hid_packets(None, "solid")
        self.assertEqual(list(off[2][:5]), [0x5A, 0xBA, 0xC5, 0xC4, 0])  # brightness off

    def test_finds_led_and_hidraw(self):
        leds = Path(tempfile.mkdtemp())
        (leds / "input5::capslock").mkdir()
        ally = leds / "ally:rgb:joystick_rings"
        ally.mkdir()
        for f, v in (("multi_intensity", "0 0 0"), ("multi_index", "red green blue"), ("max_brightness", "255"),
                     ("brightness", "0")):
            (ally / f).write_text(v)
        self.assertEqual(gl.find_led(leds), ally)
        gl.led_write(ally, (10, 20, 30))
        self.assertEqual((ally / "multi_intensity").read_text().strip(), "10 20 30")
        self.assertEqual((ally / "brightness").read_text().strip(), "255")
        hid = Path(tempfile.mkdtemp())
        for n, vid, desc in (("hidraw0", "046D", b"\x06\x00\xff"), ("hidraw3", "0B05", b"\x05\x01\x06\x31\xff\x09\x80")):
            (hid / n / "device").mkdir(parents=True)
            (hid / n / "device/uevent").write_text(f"HID_ID=0003:0000{vid}:00001ABE\n")
            (hid / n / "device/report_descriptor").write_bytes(desc)
        self.assertEqual(gl.find_hidraw(hid), Path("/dev/hidraw3"))

    def test_config_accepts_only_valid_light_settings(self):
        cfg = load("usr/bin/gosaab-config")
        self.assertTrue(cfg.validate("features.conf", "lights_color", "ff2d55"))
        self.assertFalse(cfg.validate("features.conf", "lights_color", "#ff2d55"))  # '#' starts a comment
        self.assertFalse(cfg.validate("features.conf", "lights_color", "ff2d5"))
        self.assertTrue(cfg.validate("features.conf", "lights_mode", "gaming"))
        self.assertFalse(cfg.validate("features.conf", "lights_brightness", "101"))


class Clipboard(unittest.TestCase):
    def setUp(self):
        self.cb = load("usr/libexec/gill-osaab/gosaab-clipboard")
        d = tempfile.mkdtemp()
        self.cb.HISTORY = os.path.join(d, "clip.json")
        self.cb.APPEARANCE = os.path.join(d, "appearance.json")

    def test_history_newest_first_no_duplicates_capped(self):
        items = []
        for t in ["a", "b", "a", "   "] + [str(i) for i in range(40)]:
            items = self.cb.add(items, t)
        self.assertEqual(len(items), 25)
        self.assertEqual(items[0], "39")
        self.assertEqual(self.cb.add(["x", "y"], "y"), ["y", "x"])

    def test_store_respects_switch_and_password_managers(self):
        with mock.patch("sys.stdin") as stdin, mock.patch.object(self.cb, "is_secret", return_value=False):
            stdin.read.return_value = "hello"
            self.cb.main(["store"])
        self.assertEqual(self.cb.load(), ["hello"])
        self.assertEqual(oct(os.stat(self.cb.HISTORY).st_mode & 0o777), "0o600")
        with mock.patch("sys.stdin") as stdin, mock.patch.object(self.cb, "is_secret", return_value=True):
            stdin.read.return_value = "hunter2"
            self.cb.main(["store"])
        self.assertEqual(self.cb.load(), ["hello"])
        Path(self.cb.APPEARANCE).write_text(json.dumps({"clipboardHistory": False}))
        with mock.patch("sys.stdin") as stdin:
            stdin.read.return_value = "x"
            self.cb.main(["store"])
        self.assertFalse(os.path.exists(self.cb.HISTORY))  # turning it off forgets everything


class Weather(unittest.TestCase):
    def test_describe_and_offline_cache(self):
        w = load("usr/libexec/gill-osaab/gosaab-weather")
        self.assertEqual(w.describe(0), "Clear")
        self.assertEqual(w.describe(95), "Thunderstorm")
        w.CACHE = os.path.join(tempfile.mkdtemp(), "w.json")
        Path(w.CACHE).write_text(json.dumps({"city": "Melbourne", "temp": 18}))
        with mock.patch.object(w, "fetch", side_effect=OSError("offline")), mock.patch("builtins.print") as out:
            w.main(["Melbourne"])
        self.assertEqual(json.loads(out.call_args[0][0])["temp"], 18)
        with mock.patch("builtins.print") as out:
            w.main([])
        self.assertIn("Settings", json.loads(out.call_args[0][0])["error"])


if __name__ == "__main__":
    unittest.main()


class GroupShortcut(unittest.TestCase):
    def test_one_shortcut_opens_several_things(self):
        import gosaab_hotkeys as hk
        a = "group:app:itunes|app:sideloadly|open:/home/gill/Desktop/iPhone apps|open:https://appleid.apple.com"
        self.assertTrue(hk.valid_action(a))
        self.assertEqual(hk.group_items(a)[2], ("open", "/home/gill/Desktop/iPhone apps"))
        self.assertEqual(hk.describe_action(a), "Open itunes, sideloadly, iPhone apps, https://appleid.apple.com")
        for bad in ("group:", "group:app:x;rm", "group:open:relative/path", "group:run:sh",
                    "group:open:javascript:alert(1)", "group:" + "|".join(["app:a"] * 13)):
            self.assertFalse(hk.valid_action(bad), bad)
        conf = hk.parse_config(f"META+I = {a}\n")
        self.assertEqual(conf, {"META+I": a})

    def test_translation_layers_update_together(self):
        uc = load("usr/bin/gosaab-update-component")
        self.assertEqual(uc.GROUPS["translation"], ["android", "proton", "wine", "containers"])


class GameProfiles(unittest.TestCase):
    def test_which_game_is_running(self):
        import gosaab_profiles as gp
        self.assertEqual(gp.current_game(["steam -gamepadui", "reaper SteamLaunch AppId=1245620 -- x"])[0], "steam:1245620")
        self.assertEqual(gp.current_game(["wine64-preloader C:\\Games\\HK\\hollow_knight.exe"])[0], "exe:hollow_knight.exe")
        self.assertEqual(gp.current_game(["C:\\windows\\system32\\explorer.exe /desktop"])[0], "")
        self.assertEqual(gp.current_game(["/app/bin/retroarch -L core.so"])[0], "app:retroarch")

    def test_profiles_validated_on_save(self):
        import gosaab_profiles as gp
        path = Path(tempfile.mkdtemp()) / "game-profiles.json"
        self.assertEqual(gp.clean({"tdp": 15, "fps": 40, "gpu": "dedicated", "lights": "ff2d55", "evil": 1}),
                         {"tdp": 15, "fps": 40, "gpu": "dedicated", "lights": "ff2d55"})
        self.assertEqual(gp.clean({"tdp": 999, "fps": 7, "gpu": "x", "lights": "#ff"}), {})
        gp.save({"steam:1": {"name": "A", "tdp": 10}}, path)
        path.write_text(path.read_text().replace("}}", '}, "../etc/passwd": {"tdp": 5}}'))
        self.assertEqual(gp.load(path), {"steam:1": {"name": "A", "tdp": 10}})
        self.assertFalse(gp.valid_key("steam:abc"))

    def test_config_tool_profile_command(self):
        cfg = load("usr/bin/gosaab-config")
        import gosaab_profiles as gp
        d = Path(tempfile.mkdtemp())
        with mock.patch.object(gp, "PATH", d / "p.json"), mock.patch.dict(os.environ, {"GOSAAB_ETC": str(d)}):
            self.assertEqual(cfg.main(["profile", "set", "steam:42", '{"name": "Game", "tdp": 12, "fps": 60}']), 0)
            self.assertEqual(gp.load(d / "p.json")["steam:42"]["tdp"], 12)
            self.assertEqual(cfg.main(["profile", "set", "steam:42", '{"tdp": 500}']), 2)
            self.assertEqual(cfg.main(["profile", "set", "steam:42", '{"tdp": 10, "shell": "rm"}']), 2)
            self.assertEqual(cfg.main(["profile", "remove", "steam:42"]), 0)
            self.assertEqual(gp.load(d / "p.json"), {})

    def test_steam_library_scan(self):
        import gosaab_profiles as gp
        home = Path(tempfile.mkdtemp())
        apps = home / ".local/share/Steam/steamapps"
        apps.mkdir(parents=True)
        (apps / "appmanifest_1245620.acf").write_text('"AppState"\n{\n "appid" "1245620"\n "name" "ELDEN RING"\n}')
        (apps / "appmanifest_1493710.acf").write_text('"AppState"\n{\n "appid" "1493710"\n "name" "Proton Experimental"\n}')
        self.assertEqual(gp.steam_games(home), [("steam:1245620", "ELDEN RING")])


class Memory(unittest.TestCase):
    def test_memory_listing(self):
        mem = load("usr/libexec/gill-osaab/gosaab-memory")
        d = Path(tempfile.mkdtemp())
        (d / "meminfo").write_text("MemTotal: 16000000 kB\nMemAvailable: 9000000 kB\nCached: 2000000 kB\n")
        self.assertEqual(mem.meminfo(d / "meminfo")["MemTotal"], 16000000 * 1024)
        (d / "zram0").mkdir()
        (d / "zram0/mm_stat").write_text("3000 1000 1100 0 1100 0 0 0 0\n")
        self.assertEqual(mem.zram(d), {"stored": 3000, "compressed": 1000, "ram": 1100, "saved": 1900})
        data = mem.listing()  # this machine: real numbers, this test's own process listed under some app
        self.assertGreater(data["total"], 0)
        self.assertTrue(all("canClose" in a for a in data["apps"]))
        self.assertFalse(mem.close("desktop")["ok"])

    def test_zram_and_memory_settings_shipped(self):
        from helpers import ROOT
        conf = (ROOT / "files/system/usr/lib/systemd/zram-generator.conf").read_text()
        self.assertIn("compression-algorithm = zstd", conf)
        self.assertIn("vm.swappiness = 180", (ROOT / "files/system/usr/lib/sysctl.d/60-gill-osaab.conf").read_text())
