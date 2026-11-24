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
