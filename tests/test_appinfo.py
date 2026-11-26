import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from helpers import load


class AppInfo(unittest.TestCase):
    def setUp(self):
        self.ai = load("usr/libexec/gill-osaab/gosaab-appinfo")
        self.home = Path(tempfile.mkdtemp())
        for name in ("HOME",):
            setattr(self.ai, name, self.home)
        self.ai.DATA = self.home / ".local/share"
        self.ai.CACHE = self.home / ".cache"
        self.ai.CONFIG = self.home / ".config"
        self.ai.WINE_PREFIXES = self.ai.DATA / "gill-osaab/wine"
        self.ai.APPIMAGES = self.home / "Applications"
        self.apps = self.ai.DATA / "applications"
        self.apps.mkdir(parents=True)

    def desktop(self, app_id, text, sub=None):
        d = self.apps / sub if sub else self.apps
        d.mkdir(parents=True, exist_ok=True)
        f = d / f"{app_id.split('-')[-1] if sub else app_id}.desktop"
        f.write_text("[Desktop Entry]\nType=Application\n" + text)
        return f

    def classify(self, app_id, text):
        f = self.desktop(app_id, text)
        return self.ai.classify(app_id, f, self.ai.read_entry(f))

    def test_tells_android_windows_and_linux_apps_apart(self):
        self.assertEqual(self.classify("waydroid.com.whatsapp", "Name=WhatsApp\nExec=waydroid app launch com.whatsapp\n")[:2],
                         ("Android", "waydroid"))
        k, s, d = self.classify("itunes", 'Name=iTunes\nExec=gosaab-open --wine-run "/p/itunes" C:\\\\Program Files\\\\iTunes\\\\iTunes.exe\n')
        self.assertEqual((k, s, d["prefix"]), ("Windows", "wine", "/p/itunes"))
        self.assertEqual(self.classify("org.videolan.VLC", "Name=VLC\nExec=flatpak run org.videolan.VLC\nX-Flatpak=org.videolan.VLC\n")[:2],
                         ("Linux", "flatpak"))
        self.assertEqual(self.classify("cool", f"Name=Cool\nExec={self.home}/Applications/Cool-1.2.3.AppImage\n")[1], "appimage")
        self.assertEqual(self.classify("box", "Name=Gimp\nExec=/usr/bin/distrobox-enter -n gosaab-ubuntu -- gimp\n")[1], "container")
        f = Path(tempfile.mkdtemp()) / "nautilus.desktop"
        f.write_text("[Desktop Entry]\nName=Files\nExec=nautilus\n")
        self.assertEqual(self.ai.classify("nautilus", f, self.ai.read_entry(f))[1], "system")

    def test_rejects_bad_ids_and_finds_subfolder_entries(self):
        self.assertIsNone(self.ai.load("../../etc/passwd"))
        self.assertIsNone(self.ai.load("x;rm -rf ~"))
        with mock.patch.object(self.ai, "app_dirs", return_value=[self.apps]):
            self.desktop("wine-Programs-iTunes", "Name=iTunes\nExec=wine x.exe\n", sub="wine/Programs")
            self.assertEqual(self.ai.find_desktop("wine-Programs-iTunes").name, "iTunes.desktop")

    def test_reads_windows_exe_version(self):
        exe = self.home / "app.exe"
        exe.write_bytes(b"MZ" + b"\0" * 100 + "ProductVersion".encode("utf-16-le") + b"\0\0" + "12.13.1.3".encode("utf-16-le") + b"\0\0\0\0")
        self.assertEqual(self.ai.pe_version(exe), "12.13.1.3")
        self.assertEqual(self.ai.pe_version(self.home / "missing.exe"), "")

    def test_clear_data_stays_inside_the_apps_own_folders(self):
        (self.ai.CONFIG / "vlc").mkdir(parents=True)
        (self.ai.CONFIG / "vlc/vlcrc").write_text("x")
        (self.ai.CACHE / "vlc").mkdir(parents=True)
        (self.ai.CACHE / "vlc/art").write_text("x")
        (self.ai.CONFIG / "other").mkdir()
        (self.ai.CONFIG / "other/keep").write_text("x")
        outside = Path(tempfile.mkdtemp())
        (outside / "precious").write_text("x")
        os.symlink(outside, self.ai.CACHE / "evil")
        entry = {"Exec": "vlc %U", "StartupWMClass": "evil"}
        cache, data = self.ai.folders("system", {}, "vlc", entry)
        self.ai.empty(cache + data, self.ai.roots_for("system", {}))
        self.assertFalse((self.ai.CONFIG / "vlc/vlcrc").exists())
        self.assertFalse((self.ai.CACHE / "vlc/art").exists())
        self.assertTrue((self.ai.CONFIG / "other/keep").exists())
        self.assertTrue((outside / "precious").exists())  # symlinked folder isn't followed
        # shared names (steam, flatpak, ...) are never an app's own folder
        self.assertNotIn("steam", self.ai.name_candidates("steam", {"Exec": "steam"}))
        self.assertEqual(self.ai.empty([self.ai.CONFIG], [self.ai.CONFIG]), 0)  # never a whole root

    def test_uninstall_windows_app_removes_only_its_own_prefix(self):
        prefix = self.ai.WINE_PREFIXES / "itunes"
        (prefix / "drive_c").mkdir(parents=True)
        other = self.ai.WINE_PREFIXES / "sideloadly"
        other.mkdir(parents=True)
        f = self.desktop("itunes", f'Name=iTunes\nExec=gosaab-open --wine-run "{prefix}" C:\\\\iTunes.exe\n')
        app = {"id": "itunes", "path": f, "entry": self.ai.read_entry(f), "kind": "Windows", "source": "wine",
               "details": {"prefix": str(prefix), "exec": ""}}
        with mock.patch.object(self.ai, "force_close"):
            ok, _ = self.ai.uninstall(app)
        self.assertTrue(ok)
        self.assertFalse(prefix.exists())
        self.assertFalse(f.exists())
        self.assertTrue(other.exists())
        shared = dict(app, details={"prefix": str(self.home / ".wine"), "exec": ""})
        with mock.patch.object(self.ai, "force_close"):
            self.assertFalse(self.ai.uninstall(shared)[0])

    def test_system_apps_cant_be_uninstalled(self):
        app = {"id": "nautilus", "path": Path("/usr/share/applications/nautilus.desktop"), "entry": {}, "kind": "Linux",
               "source": "system", "details": {}}
        with mock.patch.object(self.ai, "force_close"):
            ok, msg = self.ai.uninstall(app)
        self.assertFalse(ok)
        self.assertIn("hide", msg)

    def test_info_json(self):
        self.desktop("org.videolan.VLC", "Name=VLC\nExec=flatpak run org.videolan.VLC\nX-Flatpak=org.videolan.VLC\n")
        with mock.patch.object(self.ai, "app_dirs", return_value=[self.apps]), \
             mock.patch.object(self.ai, "run", return_value=(0, "      Version: 3.0.21\n")), \
             mock.patch("builtins.print") as p:
            self.ai.main(["info", "org.videolan.VLC"])
        data = json.loads(p.call_args[0][0])
        self.assertEqual((data["kind"], data["source"], data["version"]), ("Linux", "flatpak", "3.0.21"))
        self.assertTrue(data["canUninstall"])


if __name__ == "__main__":
    unittest.main()
