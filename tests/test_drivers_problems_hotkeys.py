import json
import os
import subprocess
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


upd_run = load("usr/libexec/gill-osaab/gosaab-update-run", "upd_run_sched")


class Schedule(unittest.TestCase):
    def test_intervals(self):
        day = 86400
        self.assertTrue(upd_run.is_due({}, None, 0))
        self.assertFalse(upd_run.is_due({"frequency": "weekly"}, 0, 3 * day))
        self.assertTrue(upd_run.is_due({"frequency": "weekly"}, 0, 7 * day))
        self.assertFalse(upd_run.is_due({"frequency": "6months"}, 0, 100 * day))
        self.assertTrue(upd_run.is_due({"frequency": "yearly"}, 0, 365 * day))
        self.assertFalse(upd_run.is_due({"frequency": "never"}, None, 10 ** 9))
        self.assertFalse(upd_run.is_due({"all": "off"}, None, 10 ** 9))

    def test_drivers_only_and_never(self):
        tools = lambda t: f"/usr/bin/{t}"
        self.assertEqual(upd_run.plan_updates({"scope": "drivers"}, which=tools, users=[]),
                         [["gosaab-drivers", "auto", "--install"]])
        self.assertEqual(upd_run.plan_updates({"frequency": "never"}, which=tools, users=[]), [])


class DriverHistoryAndSearch(unittest.TestCase):
    def test_history_roundtrip(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "h.json"
            e1 = drv.add_history({"kind": "firmware", "name": "SSD firmware", "target": "a" * 40, "from": "1",
                                  "to": "2", "time": 10}, p)
            drv.add_history({"kind": "system", "name": "Built-in", "from": "x", "to": "y", "time": 20}, p)
            hist = drv.load_history([p])
            self.assertEqual([h["kind"] for h in hist], ["system", "firmware"])
            self.assertEqual(hist[1]["id"], e1["id"])

    def test_search_everywhere(self):
        inv = {"parts": [{"category": "Wi-Fi", "name": "Realtek RTL8852BE", "driver": "rtw89_8852be"},
                         {"category": "Camera", "name": "Intel IPU6", "driver": ""}]}
        mods = {"rtw89_8852be": "Realtek 802.11ax wireless 8852BE driver", "amdgpu": "AMD GPU",
                "ipu6": "Intel IPU6 input system"}
        with tempfile.TemporaryDirectory() as fw:
            (Path(fw) / "rtw89").mkdir()
            (Path(fw) / "rtw89" / "rtw8852b_fw.bin.xz").write_text("x")
            res = drv.search("realtek", inv, mods, {"rtw89_8852be"}, fw)
            types = [(r["type"], r["status"]) for r in res]
            self.assertIn(("This device", "in use"), types)
            self.assertIn(("Built-in driver", "loaded"), types)
            self.assertIn("rtw89_8852be", [r["name"] for r in drv.search("realtek wifi", {}, mods, set(), None)])
            res = drv.search("rtw 8852b", inv, mods, set(), fw)
            self.assertIn("Firmware file", [r["type"] for r in res])
        self.assertEqual(drv.search("ipu6", inv, mods, set(), None)[0]["status"], "missing")
        self.assertEqual(drv.search("a", inv, mods), [])

    def test_firmware_version_validated(self):
        root = load("usr/libexec/gill-osaab/gosaab-update-root", "update_root_fwv")
        self.assertEqual(root.main(["firmware-version", "a" * 40, "1.2; reboot"]), 2)
        self.assertEqual(root.main(["firmware-version", "zz", "1.2"]), 2)


def load_core(rel, name):
    import importlib.machinery
    import importlib.util
    loader = importlib.machinery.SourceFileLoader(name, str(ROOT / "files/core-system" / rel))
    spec = importlib.util.spec_from_loader(name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class Installer(unittest.TestCase):
    inst = load_core("usr/bin/gosaab-install", "gosaab_install")
    LSBLK = json.dumps({"blockdevices": [
        {"name": "sda", "path": "/dev/sda", "size": 64 * 10 ** 9, "model": "USB Stick", "tran": "usb", "rm": "1",
         "type": "disk"},
        {"name": "nvme0n1", "path": "/dev/nvme0n1", "size": 1000 * 10 ** 9, "model": "WD SN770", "tran": "nvme",
         "rm": "0", "type": "disk"},
        {"name": "zram0", "path": "/dev/zram0", "size": 8 * 10 ** 9, "type": "disk"},
        {"name": "sdb", "path": "/dev/sdb", "size": 16 * 10 ** 9, "model": "Small", "rm": "1", "type": "disk"}]})

    def test_never_offers_the_running_drive(self):
        disks = self.inst.candidate_disks(self.LSBLK, "/dev/sda")
        self.assertEqual([d["path"] for d in disks], ["/dev/nvme0n1", "/dev/sdb"])
        self.assertFalse(disks[1]["big_enough"])

    def test_encrypted_install_command(self):
        cmd = self.inst.install_command("ghcr.io/x/gill-osaab-core:latest", "/dev/nvme0n1", True)
        self.assertEqual(cmd[-4:], ["btrfs", "--block-setup", "tpm2-luks", "/dev/nvme0n1"])
        self.assertIn("to-disk", cmd)
        self.assertNotIn("--block-setup", self.inst.install_command("i", "/dev/x", False))

    def test_account_validated(self):
        self.assertEqual(self.inst.account_record("gill", "$y$abc")["name"], "gill")
        for bad in ("root;rm", "Gill", ""):
            with self.assertRaises(ValueError):
                self.inst.account_record(bad, "$y$abc")
        with self.assertRaises(ValueError):
            self.inst.account_record("gill", "plaintext")

    def test_password_hash(self):
        try:
            h = self.inst.hash_password("correct horse")
        except OSError:
            self.skipTest("no libcrypt")
        self.assertTrue(h.startswith("$y$"))


import gosaab_gpu  # noqa: E402

fps = load("usr/bin/gosaab-fps", "gosaab_fps")


class FpsProfiles(unittest.TestCase):
    def dev(self, vendor, name, cls="VGA compatible controller"):
        return {"Class": cls, "Vendor": vendor, "Device": name, "Driver": ""}

    def test_families(self):
        cases = [("NVIDIA Corporation", "AD107M [GeForce RTX 4060 Max-Q / Mobile]", "rtx40"),
                 ("NVIDIA Corporation", "GB203 [GeForce RTX 5080]", "rtx50"),
                 ("NVIDIA Corporation", "GP107 [GeForce GTX 1050 Ti]", "nvidia-old"),
                 ("Advanced Micro Devices, Inc. [AMD/ATI]", "Navi 48 [Radeon RX 9070 XT]", "rdna4"),
                 ("Advanced Micro Devices, Inc. [AMD/ATI]", "Navi 31 [Radeon RX 7900 XTX]", "rdna3"),
                 ("Advanced Micro Devices, Inc. [AMD/ATI]", "Phoenix1", "rdna3-apu"),
                 ("Advanced Micro Devices, Inc. [AMD/ATI]", "Van Gogh [AMD Custom GPU 0405]", "rdna2"),
                 ("Intel Corporation", "DG2 [Arc A770]", "arc"),
                 ("Intel Corporation", "Meteor Lake-P [Intel Arc Graphics]", "xe-igpu"),
                 ("Intel Corporation", "Alder Lake-P GT2 [Iris Xe Graphics]", "intel-igpu")]
        for vendor, name, fam in cases:
            self.assertEqual(gosaab_gpu.gpus([self.dev(vendor, name)])[0]["family"], fam, name)

    def test_best_setup_per_gpu(self):
        def env(name, vendor="NVIDIA Corporation", smooth=False):
            g = gosaab_gpu.gpus([self.dev(vendor, name)])[0]
            return gosaab_gpu.environment(gosaab_gpu.recommendation(g), True, smooth)
        self.assertEqual(env("AD104 [GeForce RTX 4070]", smooth=True),
                         {"PROTON_DLSS_UPGRADE": "1", "PROTON_ENABLE_NVAPI": "1", "NVPRESENT_ENABLE_SMOOTH_MOTION": "1"})
        self.assertNotIn("NVPRESENT_ENABLE_SMOOTH_MOTION", env("TU106 [GeForce RTX 2060]", smooth=True))
        self.assertEqual(env("Navi 48 [Radeon RX 9070 XT]", "AMD"), {"PROTON_FSR4_UPGRADE": "1"})
        self.assertEqual(env("Navi 32", "AMD"), {"PROTON_FSR4_RDNA3_UPGRADE": "1"})
        self.assertEqual(env("DG2 [Arc A770]", "Intel"), {"PROTON_XESS_UPGRADE": "1"})
        self.assertEqual(env("Phoenix1", "AMD"), {"PROTON_FSR3_UPGRADE": "1"})

    def test_discrete_preferred_and_nvidia_edition(self):
        gs = gosaab_gpu.gpus([self.dev("Intel Corporation", "Raptor Lake-P [Iris Xe Graphics]"),
                              self.dev("NVIDIA Corporation", "AD106M [GeForce RTX 4070 Max-Q]", "3D controller")])
        self.assertEqual(gosaab_gpu.main_gpu(gs)["vendor"], "nvidia")
        self.assertTrue(gosaab_gpu.nvidia_needs_driver(gs))
        self.assertFalse(gosaab_gpu.nvidia_needs_driver(gosaab_gpu.gpus([self.dev("NVIDIA", "GP107")])))

    def test_steam_default_tool(self):
        vdf = '"InstallConfigStore"\n{\n\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n\t\t\t"Steam"\n\t\t\t{\n\t\t\t\t"x"\t\t"1"\n\t\t\t}\n\t\t}\n\t}\n}\n'
        out = fps.add_default_tool(vdf, "GE-Proton10-30")
        self.assertIn('"CompatToolMapping"', out)
        self.assertIn('"GE-Proton10-30"', out)
        self.assertEqual(out.count("{"), out.count("}"))
        self.assertEqual(fps.add_default_tool("garbage", "x"), "garbage")


class SecureBootFirmware(unittest.TestCase):
    def test_certificate_updates_only_with_secure_boot(self):
        data = json.dumps({"Devices": [{"Name": "UEFI db", "Plugin": "uefi_db", "DeviceId": "d" * 40,
                                        "Releases": [{"Version": "2023"}]},
                                       {"Name": "System Firmware", "Plugin": "uefi_capsule", "DeviceId": "e" * 40,
                                        "Releases": [{"Version": "2"}]}]})
        self.assertEqual(drv.fwupd_updates(data), [])
        self.assertEqual([u["name"] for u in drv.fwupd_updates(data, allow_sb_keys=True)], ["UEFI db"])

    def test_installer_picks_nvidia_edition(self):
        self.assertEqual(Installer.inst.nvidia_variant("ghcr.io/x/gill-osaab-core:latest"),
                         "ghcr.io/x/gill-osaab-core-nvidia:latest")
        self.assertEqual(Installer.inst.nvidia_variant("ghcr.io/x/gill-osaab-core-nvidia:latest"),
                         "ghcr.io/x/gill-osaab-core-nvidia:latest")

    def test_secureboot_script(self):
        out = subprocess.run(["bash", str(ROOT / "files/core-system/usr/bin/gosaab-secureboot"), "status"],
                             capture_output=True, text=True).stdout
        self.assertIn('"enabled"', json.dumps(json.loads(out)))


import gosaab_power as pw  # noqa: E402

gpu_cli = load("usr/bin/gosaab-gpu", "gosaab_gpu_cli")
activity = load("usr/libexec/gill-osaab/gosaab-activity", "gosaab_activity")


class SmartPowerLogic(unittest.TestCase):
    def test_device_class(self):
        self.assertEqual(pw.device_class("AMD Ryzen Z1 Extreme", "31", True), "handheld")
        self.assertEqual(pw.device_class("Intel Core i7-13700H", "10", True), "laptop")
        self.assertEqual(pw.device_class("AMD Ryzen 7 7800X3D", "3", False), "desktop")

    def test_modes(self):
        self.assertEqual(pw.decide({"game": True, "idle": True}), "game")
        self.assertEqual(pw.decide({"gpu_busy": 85}), "game")  # heavy work without a known game
        self.assertEqual(pw.decide({"video": True}, "desktop", 100), "video")
        self.assertEqual(pw.decide({"idle": True}, "desktop", 100), "idle")
        self.assertEqual(pw.decide({}, "game", 3), "game")  # waits before dropping power
        self.assertEqual(pw.decide({}, "game", 20), "desktop")

    def test_games_detected(self):
        self.assertTrue(pw.game_running(["/home/a/.steam/ubuntu12_32/reaper SteamLaunch AppId=1091500 -- proton"]))
        self.assertTrue(pw.game_running(["/usr/bin/retroarch -L core.so game.sfc"]))
        self.assertFalse(pw.game_running(["/usr/lib/steam/steamwebhelper --type=renderer", "vlc movie.mkv"]))

    def test_watts(self):
        w = pw.watts_for("handheld", {"tdp_game": "30", "tdp_idle": "0"})
        self.assertEqual((w["idle"], w["game"]), (5, 30))
        self.assertEqual(pw.watts_for("desktop", {})["game"], 0)

    def test_backends(self):
        with tempfile.TemporaryDirectory() as root:
            r = Path(root)
            (r / "proc").mkdir()
            (r / "proc/cpuinfo").write_text("vendor_id : AuthenticAMD\n")
            (r / "usr/bin").mkdir(parents=True)
            (r / "usr/bin/ryzenadj").write_text("")
            att = r / "sys/class/firmware-attributes/asus-armoury/attributes/ppt_pl1_spl"
            att.mkdir(parents=True)
            (att / "current_value").write_text("15")
            names = [b for b, _ in pw.tdp_backends(r)]
            self.assertEqual(names, ["firmware-attributes", "ryzenadj", "power-profile"])
            (r / "proc/cpuinfo").write_text("vendor_id : GenuineIntel\n")
            rapl = r / "sys/class/powercap/intel-rapl:0"
            rapl.mkdir(parents=True)
            (rapl / "constraint_0_power_limit_uw").write_text("0")
            self.assertIn("intel-rapl", [b for b, _ in pw.tdp_backends(r)])
            self.assertNotIn("ryzenadj", [b for b, _ in pw.tdp_backends(r)])
        acts = pw.tdp_actions("ryzenadj", "ryzenadj", 15)
        self.assertEqual(acts[0][1][:2], ["ryzenadj", "--stapm-limit=15000"])
        self.assertEqual(pw.tdp_actions("intel-rapl", "/x", 20)[0], ("write", "/x/constraint_0_power_limit_uw", "20000000"))
        self.assertEqual(pw.tdp_actions("power-profile", "", 20), [])

    def test_hybrid_and_offload(self):
        ig = {"vendor": "amd", "discrete": False, "name": "780M", "slot": "c4:00.0", "driver": "amdgpu"}
        nv = {"vendor": "nvidia", "discrete": True, "name": "RTX 4060", "slot": "01:00.0", "driver": "nvidia"}
        amd = {"vendor": "amd", "discrete": True, "name": "RX 7600S", "slot": "03:00.0", "driver": "amdgpu"}
        self.assertEqual(pw.hybrid([ig, nv]), (ig, nv))
        self.assertIsNone(pw.hybrid([ig]))
        self.assertEqual(pw.offload_env(nv)["__NV_PRIME_RENDER_OFFLOAD"], "1")
        self.assertEqual(pw.offload_env(amd), {"DRI_PRIME": "pci-0000_03_00_0"})
        self.assertTrue(pw.app_wants_dgpu("steam"))
        self.assertTrue(pw.app_wants_dgpu("some-game", "Game;ActionGame;"))
        self.assertFalse(pw.app_wants_dgpu("vlc", "AudioVideo;Player;"))

    def test_desktop_wrap(self):
        out = gpu_cli.wrap_desktop("[Desktop Entry]\nName=Steam\nExec=steam %U\n[Desktop Action X]\nExec=steam -x\n")
        self.assertIn("Exec=gosaab-gpu run steam %U", out)
        self.assertIn("Exec=gosaab-gpu run steam -x", out)
        self.assertIn(gpu_cli.MARK, out)
        self.assertEqual(out.count("gosaab-gpu run"), 2)

    def test_gpu_popup(self):
        self.assertEqual(activity.gpu_change_message(False, True, "RTX 4060", "780M", [(1, "Cyberpunk2077.exe")]),
                         ("Dedicated graphics on", "RTX 4060 is now running Cyberpunk2077.exe."))
        self.assertEqual(activity.gpu_change_message(True, False, "RTX 4060", "780M", [])[0], "Integrated graphics")
        self.assertIsNone(activity.gpu_change_message(True, True, "a", "b", []))


if __name__ == "__main__":
    unittest.main()
