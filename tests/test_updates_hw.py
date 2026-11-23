import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from helpers import load

import gosaab_hw as hw

upc = load("usr/bin/gosaab-update-component")
root = load("usr/libexec/gill-osaab/gosaab-update-root")

LSPCI = """Slot:	c1:00.0
Class:	VGA compatible controller
Vendor:	Advanced Micro Devices, Inc. [AMD/ATI]
Device:	Phoenix3
Driver:	amdgpu
Module:	amdgpu

Slot:	01:00.0
Class:	3D controller
Vendor:	NVIDIA Corporation
Device:	TU106 [GeForce RTX 2060]
Driver:	nouveau

Slot:	02:00.0
Class:	Network controller
Vendor:	MEDIATEK Corp.
Device:	MT7922 802.11ax PCI Express Wireless Network Adapter
Driver:	mt7921e

Slot:	03:00.0
Class:	Ethernet controller
Vendor:	Realtek Semiconductor Co., Ltd.
Device:	RTL8111/8168/8411
Driver:	r8169

Slot:	00:14.0
Class:	USB controller
Vendor:	AMD
Device:	USB4
"""


class Hardware(unittest.TestCase):
    def test_classify_lspci(self):
        gpus, net = hw.classify(hw.parse_lspci(LSPCI))
        self.assertEqual([g["driver"] for g in gpus], ["amdgpu", "nouveau"])
        self.assertTrue(hw.has_nvidia(gpus))
        self.assertEqual([(n["kind"], n["driver"]) for n in net], [("Wi-Fi", "mt7921e"), ("Ethernet", "r8169")])

    def test_dmi_and_cpu(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / "sys_vendor").write_text("GPD\n")
            (d / "product_name").write_text("G1619-04\n")
            (d / "bios_version").write_text("2.11\n")
            model = hw.device_model(d)
            self.assertEqual(model["name"], "GPD G1619-04")
            self.assertEqual(model["bios_version"], "2.11")
            cpu = d / "cpuinfo"
            cpu.write_text("processor\t: 0\nmodel name\t: AMD Ryzen Z1 Extreme\n")
            self.assertEqual(hw.cpu_model(cpu), "AMD Ryzen Z1 Extreme")

    def test_support_pages(self):
        self.assertIn("asus", hw.support_page("ASUSTeK COMPUTER INC."))
        self.assertIn("gpd", hw.support_page("GPD"))
        self.assertEqual(hw.support_page("Unknown Maker"), "")

    def test_summary_with_fake_lspci(self):
        fake = mock.Mock(return_value=mock.Mock(stdout=LSPCI))
        with mock.patch("shutil.which", return_value="/usr/bin/lspci"):
            s = hw.summary(dmi=Path("/nonexistent"), runner=fake, cpuinfo="/nonexistent")
        self.assertTrue(s["nvidia"])
        self.assertEqual(len(s["network"]), 2)


class RootHelper(unittest.TestCase):
    def test_nvidia_target(self):
        self.assertEqual(root.nvidia_target("ostree-unverified-registry:ghcr.io/gillsaab786/gill-osaab-desktop:latest"),
                         "ostree-unverified-registry:ghcr.io/gillsaab786/gill-osaab-desktop-nvidia:latest")
        self.assertEqual(root.nvidia_target("ostree-unverified-registry:ghcr.io/gillsaab786/gill-osaab:latest"), "",
                         "handheld edition has no Nvidia variant")
        self.assertEqual(root.nvidia_target("ostree-unverified-registry:ghcr.io/x/gill-osaab-desktop-nvidia:latest"),
                         "")
        self.assertEqual(root.nvidia_target(""), "")

    def test_system_firmware_ids(self):
        devices = {"Devices": [
            {"Name": "System Firmware", "Plugin": "uefi_capsule", "DeviceId": "abc"},
            {"Name": "Samsung SSD 980", "Plugin": "nvme", "DeviceId": "ssd"},
            {"Name": "UEFI dbx", "Plugin": "uefi_dbx", "DeviceId": "dbx"},
        ]}
        self.assertEqual(root.system_firmware_ids(json.dumps(devices)), ["abc", "dbx"])
        self.assertEqual(root.system_firmware_ids("not json"), [])

    def test_rejects_unknown_actions(self):
        self.assertEqual(root.main(["rm"]), 2)
        self.assertEqual(root.main([]), 2)


class Updater(unittest.TestCase):
    def test_groups(self):
        self.assertEqual(upc.expand("drivers"), ["os", "firmware"])
        self.assertNotIn("bios", upc.expand("all"), "BIOS is never part of 'update everything'")
        self.assertEqual(upc.expand("proton"), ["proton"])
        for part in upc.expand("all"):
            self.assertIn(part, upc.PARTS)

    def test_every_part_has_a_runner(self):
        for part, (_t, _d, kind) in upc.PARTS.items():
            if kind == "user":
                self.assertIn(part, upc.USER_PARTS)

    def test_version_sorting(self):
        names = ["GE-Proton9-27", "GE-Proton10-3", "GE-Proton10-30", "GE-Proton10-4"]
        self.assertEqual(sorted(names, key=upc.version_key)[-1], "GE-Proton10-30")

    def test_proton_versions_and_steam_root(self):
        with tempfile.TemporaryDirectory() as d:
            steam = Path(d) / ".local/share/Steam/compatibilitytools.d"
            for n in ("GE-Proton10-4", "GE-Proton10-30", "Proton-Custom"):
                (steam / n).mkdir(parents=True)
            self.assertEqual(upc.proton_versions(d), ["GE-Proton10-4", "GE-Proton10-30"])

    def test_messages(self):
        self.assertEqual(upc.message_for({"proton": 4, "apps": 3}, []), "Already up to date.")
        self.assertEqual(upc.message_for({"os": 0}, []), "Updated. Restart to finish.")
        self.assertIn("Proton-GE", upc.message_for({"proton": 1}, ["Proton-GE"]))

    def test_update_flow_with_fakes(self):
        calls = []
        with mock.patch.object(upc, "as_root", side_effect=lambda a: calls.append(a) or 0), \
                mock.patch.dict(upc.USER_PARTS, {"proton": lambda p: 4, "wine": lambda p: 3,
                                                 "apps": lambda p: 0, "containers": lambda p: 0}):
            rc = upc.update("all")
        self.assertEqual(calls, ["os", "firmware", "android", "decky"])
        self.assertEqual(rc, 0)

    def test_exit_codes(self):
        self.assertEqual(upc.exit_code({"bios": 3}, []), upc.NOT_AVAILABLE)
        self.assertEqual(upc.exit_code({"proton": 4, "wine": 3}, []), upc.UP_TO_DATE)
        self.assertEqual(upc.exit_code({"os": 0, "wine": 3}, []), 0)
        self.assertEqual(upc.exit_code({"os": 1}, ["x"]), upc.FAILED)
        self.assertEqual(upc.message_for({"bios": 3}, []), "Not available on this device.")

    def test_failure_is_reported(self):
        with mock.patch.dict(upc.USER_PARTS, {"proton": mock.Mock(side_effect=OSError("no network"))}):
            self.assertEqual(upc.update("proton"), upc.FAILED)

    def test_cli(self):
        self.assertEqual(upc.main(["kernel"]), 2)
        with mock.patch("builtins.print") as p:
            self.assertEqual(upc.main(["--list"]), 0)
        listed = json.loads(p.call_args[0][0])
        self.assertIn("bios", listed)

    def test_wine_update_without_prefixes(self):
        with tempfile.TemporaryDirectory() as d, mock.patch.object(upc, "WINE_PREFIXES", Path(d) / "none"):
            self.assertEqual(upc.update_wine(None), upc.NOT_AVAILABLE)


class Recipes(unittest.TestCase):
    def test_nvidia_recipe_matches_updater_naming(self):
        text = (Path(__file__).resolve().parent.parent / "recipes/recipe-desktop-nvidia.yml").read_text()
        self.assertIn("name: gill-osaab-desktop-nvidia", text)
        self.assertIn("bazzite-nvidia-open", text)


if __name__ == "__main__":
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    unittest.main()
