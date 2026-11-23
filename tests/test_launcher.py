import os
import tempfile
import unittest
import zipfile
from pathlib import Path

from helpers import load, which_only

go = load("usr/bin/gosaab-open")


def make(dirpath, name, data):
    p = Path(dirpath) / name
    p.write_bytes(data)
    return p


class Detect(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def test_exe_by_magic_even_without_extension(self):
        self.assertEqual(go.detect(make(self.d, "setup", b"MZ\x90\x00" + b"\0" * 100)), "exe")

    def test_msi(self):
        self.assertEqual(go.detect(make(self.d, "a.msi", b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1" + b"\0" * 50)), "msi")

    def test_apk_needs_manifest(self):
        apk = Path(self.d) / "app.apk"
        with zipfile.ZipFile(apk, "w") as z:
            z.writestr("AndroidManifest.xml", "x")
            z.writestr("classes.dex", "x")
        self.assertEqual(go.detect(apk), "apk")

    def test_plain_zip_is_not_apk(self):
        z = Path(self.d) / "photos.zip"
        with zipfile.ZipFile(z, "w") as zf:
            zf.writestr("a.jpg", "x")
        self.assertEqual(go.detect(z), "unknown")

    def test_appimage_magic(self):
        self.assertEqual(go.detect(make(self.d, "tool", b"\x7fELF\x02\x01\x01\x00AI\x02" + b"\0" * 50)), "appimage")

    def test_plain_elf(self):
        self.assertEqual(go.detect(make(self.d, "bin", b"\x7fELF\x02\x01\x01\x00\x00\x00\x00" + b"\0" * 50)), "elf")

    def test_deb_and_rpm(self):
        self.assertEqual(go.detect(make(self.d, "p.deb", b"!<arch>\ndebian-binary   " + b" " * 60)), "deb")
        self.assertEqual(go.detect(make(self.d, "p.rpm", b"\xed\xab\xee\xdb" + b"\0" * 60)), "rpm")

    def test_flatpakref_by_extension(self):
        self.assertEqual(go.detect(make(self.d, "app.flatpakref", b"[Flatpak Ref]\n")), "flatpakref")

    def test_text_file_unknown(self):
        self.assertEqual(go.detect(make(self.d, "notes.txt", b"hello")), "unknown")


class Slug(unittest.TestCase):
    def test_slug(self):
        self.assertEqual(go.slug("Setup Foo 1.2.exe"), "setup-foo-1-2")
        self.assertEqual(go.slug("ÄÖ.msi"), "app")


class Plan(unittest.TestCase):
    def test_exe_sandboxed_uses_bwrap_and_stages_file(self):
        steps = go.plan("/tmp/My App.exe", "exe", {"sandbox_windows_apps": "on"}, which=which_only("bwrap"))
        kinds = [s[1] if s[0] == "call" else "run" for s in steps]
        self.assertEqual(kinds, ["prepare_prefix", "stage_file", "run", "fix_menu_entries"])
        cmd = steps[2][1]
        self.assertEqual(cmd[0], "bwrap")
        self.assertIn("--tmpfs", cmd)
        staged = steps[1][2][1]
        self.assertTrue(staged.endswith("drive_c/gosaab-files/My App.exe"))
        self.assertEqual(cmd[-1], staged)
        self.assertEqual(cmd[-2], "wine")

    def test_exe_unsandboxed_runs_wine_directly(self):
        steps = go.plan("/tmp/a.exe", "exe", {"sandbox_windows_apps": "off"}, which=which_only("bwrap"))
        run = [s for s in steps if s[0] == "run"][0]
        self.assertEqual(run[1], ["wine", str(Path("/tmp/a.exe").resolve())])
        self.assertFalse(any(s[0] == "call" and s[1] == "stage_file" for s in steps))

    def test_sandbox_default_is_on(self):
        steps = go.plan("/tmp/a.exe", "exe", {}, which=which_only("bwrap"))
        self.assertTrue(any(s[0] == "call" and s[1] == "stage_file" for s in steps))

    def test_msi_uses_msiexec(self):
        steps = go.plan("/tmp/x.msi", "msi", {"sandbox_windows_apps": "off"}, which=which_only())
        run = [s for s in steps if s[0] == "run"][0][1]
        self.assertEqual(run[:3], ["wine", "msiexec", "/i"])

    def test_apk(self):
        steps = go.plan("/tmp/a.apk", "apk", {})
        self.assertEqual(steps[0], ("call", "require_waydroid", []))
        self.assertEqual(steps[1][1][:3], ["waydroid", "app", "install"])

    def test_deb_goes_to_ubuntu_box(self):
        steps = go.plan("/tmp/a.deb", "deb", {})
        self.assertEqual(steps[0][2][0], "gosaab-ubuntu")
        self.assertIn("apt-get", steps[1][1])
        self.assertEqual(steps[2][1], "export_apps")

    def test_rpm_goes_to_fedora_box(self):
        steps = go.plan("/tmp/a.rpm", "rpm", {})
        self.assertEqual(steps[0][2][0], "gosaab-fedora")
        self.assertIn("dnf", steps[1][1])

    def test_every_call_step_has_an_action(self):
        for kind in ("exe", "msi", "apk", "appimage", "deb", "rpm", "flatpakref", "flatpak", "elf"):
            for step in go.plan("/tmp/f", kind, {}, which=which_only("bwrap")):
                if step[0] == "call":
                    self.assertIn(step[1], go.ACTIONS, f"{kind}: {step[1]}")


class Sandbox(unittest.TestCase):
    def test_home_root(self):
        self.assertEqual(go.home_root("/var/home/jas"), "/var/home")
        self.assertEqual(go.home_root("/home/jas"), "/home")

    def test_sandbox_prefix_removes_z_drive_and_home_links(self):
        with tempfile.TemporaryDirectory() as d:
            prefix = Path(d) / "pfx"
            (prefix / "dosdevices").mkdir(parents=True)
            os.symlink("/", prefix / "dosdevices" / "z:")
            os.symlink("../drive_c", prefix / "dosdevices" / "c:")
            user = prefix / "drive_c" / "users" / "jas"
            user.mkdir(parents=True)
            os.symlink(d, user / "Documents")
            (user / "AppData").mkdir()
            go.sandbox_prefix(prefix)
            self.assertFalse(os.path.lexists(prefix / "dosdevices" / "z:"))
            self.assertTrue(os.path.lexists(prefix / "dosdevices" / "c:"))
            self.assertTrue((user / "Documents").is_dir())
            self.assertFalse((user / "Documents").is_symlink())
            self.assertTrue((user / "AppData").is_dir())

    def test_rewrite_exec(self):
        text = ('[Desktop Entry]\nName=Foo\n'
                'Exec=env WINEPREFIX="/var/home/j/.local/share/gill-osaab/wine/foo" wine '
                'C:\\\\ProgramData\\\\Foo.lnk\nType=Application\n')
        out = go.rewrite_exec(text)
        self.assertIn('Exec=gosaab-open --wine-run "/var/home/j/.local/share/gill-osaab/wine/foo" '
                      'C:\\\\ProgramData\\\\Foo.lnk', out)
        self.assertIn("Name=Foo", out)
        self.assertEqual(go.rewrite_exec(out), out)  # idempotent

    def test_fix_menu_entries_only_touches_its_prefix(self):
        with tempfile.TemporaryDirectory() as d:
            old = go.MENU_DIR
            go.MENU_DIR = Path(d) / "wine"
            try:
                (go.MENU_DIR / "Programs").mkdir(parents=True)
                mine = go.MENU_DIR / "Programs" / "a.desktop"
                other = go.MENU_DIR / "Programs" / "b.desktop"
                mine.write_text('Exec=env WINEPREFIX="/p/a" wine C:\\\\a.lnk\n')
                other.write_text('Exec=env WINEPREFIX="/p/b" wine C:\\\\b.lnk\n')
                go.fix_menu_entries("/p/a", True)
                self.assertIn("gosaab-open --wine-run", mine.read_text())
                self.assertNotIn("gosaab-open", other.read_text())
            finally:
                go.MENU_DIR = old


class Misc(unittest.TestCase):
    def test_desktop_entries(self):
        files = ["/usr/bin/foo", "/usr/share/applications/foo.desktop", "/usr/share/doc/x.desktop"]
        self.assertEqual(go.desktop_entries(files), ["foo"])

    def test_dry_run_and_errors(self):
        with tempfile.TemporaryDirectory() as d:
            exe = make(d, "a.exe", b"MZ" + b"\0" * 64)
            txt = make(d, "a.txt", b"hi")
            self.assertEqual(go.main(["--dry-run", str(exe)]), 0)
            self.assertEqual(go.main(["--dry-run", str(txt)]), 1)
            self.assertEqual(go.main([str(Path(d) / "missing.exe")]), 1)


if __name__ == "__main__":
    unittest.main()
