import json
import os
import tempfile
import time
import unittest
from pathlib import Path

from helpers import ROOT, load

import gosaab_drivers as drv
import gosaab_hotkeys as hk
import gosaab_hw

diag = load("usr/bin/gosaab-diagnose")
drivers_cli = load("usr/bin/gosaab-drivers")

LSPCI = """Slot:	c1:00.0
Class:	VGA compatible controller
Vendor:	Advanced Micro Devices, Inc. [AMD/ATI]
Device:	Phoenix3
Driver:	amdgpu

Slot:	02:00.0
Class:	Network controller
Vendor:	MEDIATEK Corp.
Device:	MT7922
Driver:	mt7921e

Slot:	00:05.0
Class:	Multimedia controller
Vendor:	Intel Corporation
Device:	IPU6

Slot:	00:00.0
Class:	Host bridge
Vendor:	AMD
Device:	Root Complex
"""

KLOG = """iwlwifi 0000:01:00.0: Direct firmware load for iwlwifi-so-a0-gf-a0-89.ucode failed with error -2
iwlwifi 0000:01:00.0: loaded firmware version 86.fb5c9aeb.0 so-a0-gf-a0-86.ucode op_mode iwlmvm
amdgpu 0000:c1:00.0: Direct firmware load for amdgpu/gc_11_5_1_mes_2.bin failed with error -2
bluetooth hci0: Direct firmware load for mediatek/BT_RAM_CODE_MT7922_1_1_hdr.bin failed with error -2
"""

INPUT = """I: Bus=0018 Vendor=04f3
N: Name="ELAN9008:00 04F3:2D55 Touchscreen"
H: Handlers=mouse2 event7

I: Bus=0003
N: Name="Microsoft X-Box 360 pad 0"
H: Handlers=event12 js0

I: Bus=0006
N: Name="gosaab-gamepad pointer"
H: Handlers=mouse3 event20
"""


class Drivers(unittest.TestCase):
    def test_parts_and_missing_driver(self):
        parts = drv.pci_parts(gosaab_hw.parse_lspci(LSPCI))
        cats = {p["category"] for p in parts}
        self.assertEqual(cats, {"Graphics", "Wi-Fi", "Camera"})  # bridges are skipped
        probs = drv.problems(parts, [], [])
        self.assertEqual([p["name"] for p in probs], ["Intel Corporation IPU6"])

    def test_firmware_failures_ignore_probing(self):
        fails = drv.firmware_failures(KLOG)
        names = [f["firmware"] for f in fails]
        self.assertNotIn("iwlwifi-so-a0-gf-a0-89.ucode", names)  # iwlwifi loaded another version
        self.assertIn("amdgpu/gc_11_5_1_mes_2.bin", names)
        self.assertIn("mediatek/BT_RAM_CODE_MT7922_1_1_hdr.bin", names)

    def test_input_parts(self):
        parts = drv.input_parts(INPUT)
        self.assertEqual([(p["category"], p["name"][:8]) for p in parts],
                         [("Input & Touch", "ELAN9008"), ("Controllers & accessories", "Microsof")])

    def test_bluetooth_dongle_without_adapter(self):
        self.assertEqual(drv.usb_bluetooth_without_adapter(["Realtek Bluetooth Radio"], []),
                         ["Realtek Bluetooth Radio"])
        self.assertEqual(drv.usb_bluetooth_without_adapter(["Realtek Bluetooth Radio"],
                                                           [{"category": "Bluetooth"}]), [])

    def test_fwupd_updates_skip_bios_and_bad_ids(self):
        good = "a" * 40
        data = {"Devices": [
            {"Name": "System Firmware", "Plugin": "uefi_capsule", "DeviceId": "b" * 40, "Releases": [{"Version": "2"}]},
            {"Name": "Samsung SSD 990", "Plugin": "nvme", "DeviceId": good, "Version": "1",
             "Releases": [{"Version": "2"}]},
            {"Name": "8BitDo Pro 2", "Plugin": "ebitdo", "DeviceId": "x; rm -rf /", "Releases": [{"Version": "2"}]},
        ]}
        ups = drv.fwupd_updates(json.dumps(data))
        self.assertEqual(ups, [{"id": f"fw:{good}", "category": "Storage", "name": "Samsung SSD 990",
                                "from": "1", "to": "2"}])

    def test_only_graphics(self):
        ups = [{"id": "fw:" + "a" * 40, "category": "Storage"}, {"id": "fw:" + "c" * 40, "category": "Graphics"}]
        self.assertEqual(drv.targets_for(["Graphics"], ups, False, True), ["gfx-apps", "fw:" + "c" * 40])
        self.assertEqual(drv.targets_for(["Wi-Fi"], ups, True, True), ["builtin"])

    def test_category_keys(self):
        self.assertEqual(drv.KEYS["Wi-Fi"], "wi-fi")
        self.assertEqual(drv.BY_KEY["usb-thunderbolt"], "USB & Thunderbolt")

    def test_root_helper_rejects_bad_device_id(self):
        root = load("usr/libexec/gill-osaab/gosaab-update-root", "update_root_drv")
        self.assertEqual(root.main(["firmware-device", "--force; reboot"]), 2)


class Problems(unittest.TestCase):
    def test_redact(self):
        text = ("/var/home/jas/x failed on jas-pc: wlan0 aa:bb:cc:dd:ee:ff 192.168.1.20 me@mail.com "
                "serial: ABC123 SSID 'Home WiFi'")
        out = diag.redact(text, user="jas", host="jas-pc", home="/var/home/jas")
        for secret in ("jas", "aa:bb", "192.168", "me@mail", "ABC123", "Home WiFi"):
            self.assertNotIn(secret, out)
        self.assertIn("~/x", out)

    def test_journal_entries_and_noise(self):
        lines = "\n".join(json.dumps(e) for e in [
            {"MESSAGE": "ACPI BIOS Error (bug): Could not resolve symbol", "SYSLOG_IDENTIFIER": "kernel",
             "__REALTIME_TIMESTAMP": "1700000000000000"},
            {"MESSAGE": "Process 4242 (foot) of user 1000 dumped core.\n\nStack trace...",
             "SYSLOG_IDENTIFIER": "systemd-coredump", "__REALTIME_TIMESTAMP": "1700000001000000"},
            {"MESSAGE": "amdgpu: ring gfx timeout", "SYSLOG_IDENTIFIER": "kernel",
             "__REALTIME_TIMESTAMP": "1700000002000000"},
        ])
        found = diag.journal_entries(lines)
        self.assertEqual([f["kind"] for f in found], ["crash", "error"])
        self.assertEqual(found[0]["title"], "foot crashed")

    def test_merge_counts_and_forgets_fixed(self):
        rec = {}
        e = {"kind": "error", "title": "x", "detail": "ring gfx timeout 12", "source": "kernel", "time": 100}
        s = {"kind": "failed-service", "title": "y", "detail": "a.service failed", "source": "a.service",
             "time": 100, "state": True}
        self.assertEqual(len(diag.merge(rec, [e, s], now=200)), 2)
        diag.merge(rec, [{**e, "time": 150, "detail": "ring gfx timeout 13"}, s], now=200)
        self.assertEqual(sorted(r["count"] for r in rec.values()), [1, 2])
        diag.merge(rec, [], now=300)  # the service was fixed
        self.assertEqual([r["kind"] for r in rec.values()], ["error"])

    def test_security_problems(self):
        out = diag.security_problems({"weak_password_users": ["gill"], "ssh": {"active": True},
                                      "firewall": {"active": False}}, user="gill")
        self.assertEqual(len(out), 3)
        self.assertEqual(diag.security_problems({"weak_password_users": ["bob"]}, user="gill"), [])

    def test_driver_problems(self):
        out = diag.driver_problems({"problems": [{"kind": "missing-driver", "category": "Camera", "name": "IPU6",
                                                  "detail": "no driver", "hint": "send report"}]})
        self.assertEqual(out[0]["title"], "Missing driver: IPU6")


class Hotkeys(unittest.TestCase):
    def test_combo_parsing(self):
        self.assertEqual(hk.parse_combo("Win+r"), "META+R")
        self.assertEqual(hk.parse_combo("KEY_R + KEY_LEFTMETA"), "META+R")
        self.assertEqual(hk.parse_combo("BTN_MODE+BTN_SOUTH"), "BTN_MODE+BTN_SOUTH")
        self.assertEqual(hk.parse_combo("META+$(x)"), "")

    def test_typing_keys_not_allowed(self):
        for combo in ("R", "SHIFT+R", "SPACE"):
            self.assertFalse(hk.is_allowed(combo), combo)
        for combo in ("META+R", "CTRL+ALT+G", "BTN_MODE", "F15", "PROG1", "BTN_MODE+BTN_SOUTH", "META"):
            self.assertTrue(hk.is_allowed(combo), combo)

    def test_matcher_fires_on_completed_combo(self):
        m = hk.Matcher({"META+R": "mode"})
        self.assertIsNone(m.press("KEY_LEFTMETA"))
        self.assertEqual(m.press("KEY_R"), "mode")
        m.release("KEY_R")
        self.assertEqual(m.release("KEY_LEFTMETA"), "META+R")  # recorded combo once all are up

    def test_config_and_user_override(self):
        sys_b = hk.parse_config("# x\nMETA+R = mode\nSYSRQ = screenshot\nR = mode\nCTRL+ALT+T = run:foot\n")
        self.assertEqual(sys_b, {"META+R": "mode", "SYSRQ": "screenshot", "CTRL+ALT+T": "run:foot"})
        user = hk.parse_config("META+R = none\nBTN_MODE+BTN_SELECT = app:steam\n")
        eff = hk.effective(sys_b, user)
        self.assertNotIn("META+R", eff)
        self.assertEqual(eff["BTN_MODE+BTN_SELECT"], "app:steam")
        self.assertEqual(hk.parse_config(hk.format_config(eff)), eff)

    def test_actions_validated(self):
        self.assertTrue(hk.valid_action("app:org.videolan.VLC"))
        self.assertFalse(hk.valid_action("app:../../evil"))
        self.assertFalse(hk.valid_action("format-disk"))

    def test_user_conf_safe_read(self):
        with tempfile.TemporaryDirectory() as home:
            conf = Path(home) / hk.USER_CONF_NAME
            conf.parent.mkdir(parents=True)
            conf.write_text("META+R = mode\n")
            self.assertIn("META+R", hk.read_user_conf(home, os.getuid()))
            self.assertEqual(hk.read_user_conf(home, os.getuid() + 1), "")  # someone else's file
            conf.unlink()
            secret = Path(home) / "secret"
            secret.write_text("x")
            conf.symlink_to(secret)
            self.assertEqual(hk.read_user_conf(home, os.getuid()), "")  # symlinks are refused

    def test_describe(self):
        self.assertEqual(hk.describe("META+R"), "Windows + R")
        self.assertEqual(hk.describe("BTN_MODE+BTN_SOUTH"), "Home button + A")


class Cli(unittest.TestCase):
    def test_drivers_cli_usage(self):
        self.assertEqual(drivers_cli.main([]), 2)
        self.assertEqual(drivers_cli.main(["update", "nonsense"]), 2)

    def test_scripts_parse(self):
        for rel in ("files/core-system/usr/libexec/gill-osaab/gosaab-hotkeyd", "files/core-system/usr/bin/gosaab-hotkeys",
                    "files/system/usr/libexec/gill-osaab/gosaab-security-check"):
            compile((ROOT / rel).read_text(), rel, "exec")


if __name__ == "__main__":
    unittest.main()
