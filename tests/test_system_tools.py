import os
import tempfile
import time
import unittest
from pathlib import Path

from helpers import load, which_only

import gosaab_common as common

upd_run = load("usr/libexec/gill-osaab/gosaab-update-run")
upd_cli = load("usr/bin/gosaab-updates")
cfg = load("usr/bin/gosaab-config")
so = load("usr/bin/gosaab-screen-off")


class Conf(unittest.TestCase):
    def test_read_and_write_keep_comments(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "x.conf"
            p.write_text("# top comment\nall=on\nos=on # trailing\n\napps=off\n")
            c = common.read_conf(p)
            self.assertEqual(c, {"all": "on", "os": "on", "apps": "off"})
            common.write_conf_value(p, "os", "off")
            common.write_conf_value(p, "containers", "on")
            text = p.read_text()
            self.assertIn("# top comment", text)
            self.assertIn("os=off", text)
            self.assertTrue(text.rstrip().endswith("containers=on"))
            self.assertEqual(common.read_conf(p)["os"], "off")

    def test_missing_file_and_is_on(self):
        self.assertEqual(common.read_conf("/nonexistent/x.conf"), {})
        self.assertTrue(common.is_on({}, "k", default=True))
        self.assertFalse(common.is_on({"k": "off"}, "k", default=True))
        self.assertTrue(common.is_on({"k": "Yes"}, "k"))

    def test_shipped_conf_files_parse(self):
        etc = Path(__file__).resolve().parent.parent / "files/system/etc/gill-osaab"
        u = common.read_conf(etc / "updates.conf")
        self.assertEqual(set(u), {"all", "os", "apps", "containers"})
        f = common.read_conf(etc / "features.conf")
        for key in ("vpn", "cloud_drives", "phone_link", "night_light", "shared_game_library"):
            self.assertEqual(f[key], "off", f"{key} must be off by default")
        self.assertEqual(f["sandbox_windows_apps"], "on")
        for key in f:
            self.assertTrue(cfg.validate("features.conf", key, f[key]), f"settings can't change {key}")


class Updates(unittest.TestCase):
    tools = staticmethod(which_only("rpm-ostree", "flatpak", "distrobox"))

    def test_all_on(self):
        steps = upd_run.plan_updates({}, which=self.tools, users=["jas"])
        self.assertEqual(steps[0], ["rpm-ostree", "upgrade"])
        self.assertIn(["flatpak", "update", "--system", "-y", "--noninteractive"], steps)
        self.assertIn(["runuser", "-u", "jas", "--", "distrobox", "upgrade", "--all"], steps)

    def test_master_off_beats_everything(self):
        conf = {"all": "off", "os": "on", "apps": "on", "containers": "on"}
        self.assertEqual(upd_run.plan_updates(conf, which=self.tools, users=["jas"]), [])

    def test_os_off_only(self):
        steps = upd_run.plan_updates({"os": "off"}, which=self.tools, users=["jas"])
        self.assertFalse(any(s[0] in ("rpm-ostree", "bootc") for s in steps))
        self.assertTrue(any("flatpak" in s for s in steps))

    def test_bootc_fallback(self):
        steps = upd_run.plan_updates({"apps": "off", "containers": "off"}, which=which_only("bootc"), users=[])
        self.assertEqual(steps, [["bootc", "upgrade"]])

    def test_status_shows_blocked(self):
        lines = upd_cli.status_lines({"all": "off", "os": "on"})
        self.assertIn("off", lines[0])
        self.assertIn("blocked", lines[1])

    def test_cli_rejects_bad_args(self):
        self.assertEqual(upd_cli.main(["os", "maybe"]), 2)
        self.assertEqual(upd_cli.main(["kernel", "off"]), 2)


class Config(unittest.TestCase):
    def test_validation(self):
        self.assertTrue(cfg.validate("updates.conf", "all", "off"))
        self.assertFalse(cfg.validate("updates.conf", "all", "maybe"))
        self.assertFalse(cfg.validate("updates.conf", "rm -rf", "on"))
        self.assertFalse(cfg.validate("../../etc/passwd", "root", "on"))
        self.assertTrue(cfg.validate("features.conf", "screen_off_idle_seconds", "30"))
        self.assertFalse(cfg.validate("features.conf", "screen_off_idle_seconds", "1"))
        self.assertFalse(cfg.validate("features.conf", "screen_off_idle_seconds", "abc"))

    def test_set_writes_file(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "updates.conf").write_text("all=on\nos=on\n")
            old = cfg.ETC
            cfg.ETC = Path(d)
            os.environ["GOSAAB_ETC"] = d
            try:
                self.assertEqual(cfg.main(["set", "updates.conf", "os", "off"]), 0)
                self.assertEqual(common.read_conf(Path(d) / "updates.conf")["os"], "off")
                self.assertEqual(cfg.main(["set", "updates.conf", "os", "bad"]), 2)
            finally:
                cfg.ETC = old
                del os.environ["GOSAAB_ETC"]


class ScreenOff(unittest.TestCase):
    def test_partial_downloads(self):
        with tempfile.TemporaryDirectory() as d:
            dl = Path(d) / "Downloads"
            dl.mkdir()
            (dl / "movie.mkv").write_text("done")
            self.assertEqual(so.partial_downloads([dl]), [])
            part = dl / "game.zip.part"
            part.write_text("x")
            self.assertEqual(so.partial_downloads([dl]), [part])
            old = time.time() - 600
            os.utime(part, (old, old))
            self.assertEqual(so.partial_downloads([dl]), [], "stale partial files are ignored")

    def test_steam_downloading_folder(self):
        with tempfile.TemporaryDirectory() as d:
            steam = Path(d) / "downloading"
            (steam / "12345").mkdir(parents=True)
            (steam / "12345" / "chunk").write_text("x")
            self.assertEqual(len(so.partial_downloads([steam])), 1)

    def test_busy_processes_with_fake_proc(self):
        with tempfile.TemporaryDirectory() as d:
            for pid, comm in (("100", "rsync"), ("101", "bash"), ("102", "firefox")):
                (Path(d) / pid).mkdir()
                (Path(d) / pid / "comm").write_text(comm + "\n")
            (Path(d) / "self").mkdir()
            self.assertEqual(so.busy_processes(Path(d), uid=os.getuid()), ["rsync"])

    def test_io_monitor(self):
        with tempfile.TemporaryDirectory() as d:
            proc = Path(d)
            (proc / "200").mkdir()
            io = proc / "200" / "io"
            io.write_text("rchar: 1\nwrite_bytes: 1000\n")
            mon = so.IoMonitor(proc, threshold=1024 * 1024)
            self.assertEqual(mon.busy(), [])
            io.write_text("rchar: 1\nwrite_bytes: 5000000\n")
            self.assertEqual(mon.busy(), ["200"])
            self.assertEqual(mon.busy(), [], "no new writes means idle")

    def test_pid_alive(self):
        self.assertTrue(so.pid_alive(os.getpid()))
        self.assertFalse(so.pid_alive(None))
        self.assertFalse(so.pid_alive(2 ** 22 + 12345))

    def test_nothing_running_keeps_screen_on(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertFalse(so.tasks_running([Path(d)], None, proc=Path(d)))


if __name__ == "__main__":
    unittest.main()
