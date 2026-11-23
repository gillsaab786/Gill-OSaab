import filecmp
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from helpers import ROOT, SYSTEM

spec = importlib.util.spec_from_file_location("decky_main", ROOT / "decky/gill-osaab-notify/main.py")
dm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dm)

HUB = SYSTEM / "usr/libexec/gill-osaab/gosaab-notify-hub"
GI_PYTHON = next((p for p in ("/usr/bin/python3.12", "/usr/bin/python3") if os.path.exists(p) and subprocess.run(
    [p, "-c", "import gi; gi.require_version('Gio','2.0'); from gi.repository import Gio"],
    capture_output=True).returncode == 0), None)


class DeckyBackend(unittest.TestCase):
    def test_read_state_good_and_bad(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "s.json"
            self.assertEqual(dm.read_state(p)["items"], [])
            p.write_text("{not json")
            self.assertEqual(dm.read_state(p)["items"], [])
            p.write_text(json.dumps({"version": 1, "items": [{"id": 1}]}))
            self.assertEqual(dm.read_state(p)["items"], [{"id": 1}])

    def test_state_path(self):
        self.assertEqual(dm.state_path(1000), "/run/user/1000/gill-osaab/notifications.json")

    def test_hub_command(self):
        cmd = dm.hub_command("Dismiss", 5, uid=os.getuid())
        self.assertIn("org.gillosaab.NotifyHub.Dismiss", cmd)
        self.assertEqual(cmd[-1], "5")

    def test_clean_env_drops_bundled_libs(self):
        os.environ["LD_LIBRARY_PATH"] = "/tmp/_MEI123"
        try:
            env = dm.clean_env(1000)
            self.assertNotIn("LD_LIBRARY_PATH", env)
            self.assertEqual(env["DBUS_SESSION_BUS_ADDRESS"], "unix:path=/run/user/1000/bus")
        finally:
            del os.environ["LD_LIBRARY_PATH"]

    def test_image_copy_matches_source(self):
        src, img = ROOT / "decky/gill-osaab-notify", SYSTEM / "usr/share/gill-osaab/decky/gill-osaab-notify"
        for name in ("plugin.json", "main.py", "package.json", "dist/index.js"):
            self.assertTrue(filecmp.cmp(src / name, img / name, shallow=False), f"{name} out of sync")


@unittest.skipUnless(GI_PYTHON and shutil.which("dbus-run-session") and shutil.which("gdbus"),
                     "needs PyGObject + dbus")
class HubLive(unittest.TestCase):
    def test_notify_job_and_launcher_progress(self):
        script = f"""
set -e
export XDG_RUNTIME_DIR=$(mktemp -d)
{GI_PYTHON} {HUB} --force & HUB=$!
for i in $(seq 1 30); do gdbus introspect --session --dest org.gillosaab.NotifyHub --object-path / >/dev/null 2>&1 && break; sleep 0.2; done
gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \\
  --method org.freedesktop.Notifications.Notify "App" 0 "" "Copying" "x" "[]" "{{'value': <int32 40>}}" 0 >/dev/null
P=$(gdbus call --session --dest org.kde.JobViewServer --object-path /JobViewServer \\
  --method org.kde.JobViewServerV2.requestView "dolphin" 1 "{{}}" | grep -o "/JobView/[0-9]*")
gdbus call --session --dest org.kde.JobViewServer --object-path $P --method org.kde.JobViewV3.update \\
  "{{'title': <'Copy'>, 'percent': <uint32 70>}}" >/dev/null
gdbus emit --session --object-path /x --signal com.canonical.Unity.LauncherEntry.Update \\
  "application://chromium.desktop" "{{'progress': <0.25>, 'progress-visible': <true>}}"
sleep 0.8
cat $XDG_RUNTIME_DIR/gill-osaab/notifications.json
kill $HUB
"""
        out = subprocess.run(["dbus-run-session", "--", "bash", "-c", script], capture_output=True, text=True,
                             timeout=30)
        data = json.loads(out.stdout.strip().splitlines()[-1])
        got = {(i["kind"], i["percent"]) for i in data["items"]}
        self.assertEqual(got, {("notification", 40), ("job", 70), ("launcher", 25)})


if __name__ == "__main__":
    unittest.main()
