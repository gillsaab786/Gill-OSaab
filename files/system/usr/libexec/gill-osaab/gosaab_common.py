"""Shared helpers for Gill-OSaab tools."""
import os
import shutil
import subprocess
import time
from pathlib import Path

ETC = Path(os.environ.get("GOSAAB_ETC", "/etc/gill-osaab"))
STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "gill-osaab"

ON_VALUES = {"on", "true", "yes", "1"}


def read_conf(path):
    """Parse a key=value file. Comments (#) and blank lines are ignored."""
    conf = {}
    try:
        text = Path(path).read_text()
    except FileNotFoundError:
        return conf
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        conf[key.strip()] = value.split("#", 1)[0].strip()
    return conf


def is_on(conf, key, default=False):
    if key not in conf:
        return default
    return conf[key].lower() in ON_VALUES


def write_conf_value(path, key, value):
    """Set key=value in place, keeping comments and order; append if missing."""
    path = Path(path)
    lines = path.read_text().splitlines() if path.exists() else []
    out, found = [], False
    for line in lines:
        stripped = line.strip()
        if not stripped.startswith("#") and "=" in stripped and stripped.split("=", 1)[0].strip() == key:
            out.append(f"{key}={value}")
            found = True
        else:
            out.append(line)
    if not found:
        out.append(f"{key}={value}")
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text("\n".join(out) + "\n")
    os.replace(tmp, path)


def log(tool, message):
    try:
        STATE.mkdir(parents=True, exist_ok=True)
        with open(STATE / f"{tool}.log", "a") as fh:
            fh.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}\n")
    except OSError:
        pass


class Progress:
    """A progress item in the notification area (percentage, message, done/failed).

    Uses the KDE job protocol, which KDE Plasma shows in desktop mode and the
    Gill-OSaab hub shows in Game Mode. Falls back to plain notifications.
    """

    def __init__(self, title, app="gosaab-settings"):
        self.title, self.app = title, app
        self.path = None
        self.bus = None
        self.notify_id = None

    def _call(self, path, iface, method, args):
        return self.bus.call_sync("org.kde.JobViewServer", path, iface, method, args, None, 0, 2000, None)

    def start(self, message=""):
        try:
            import gi
            gi.require_version("Gio", "2.0")
            from gi.repository import Gio, GLib
            self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            reply = self._call("/JobViewServer", "org.kde.JobViewServerV2", "requestView",
                               GLib.Variant("(sia{sv})", (self.app, 0, {})))
            self.path = reply.unpack()[0]
            self.update(message=message)
        except Exception:  # no session bus, no job server or no PyGObject
            self.path = None
            self._fallback(message or "Starting…", None)
        return self

    def update(self, percent=None, message=None):
        if self.path:
            from gi.repository import GLib
            props = {"title": GLib.Variant("s", self.title)}
            if message is not None:
                props["infoMessage"] = GLib.Variant("s", message)
            if percent is not None:
                props["percent"] = GLib.Variant("u", max(0, min(100, int(percent))))
            try:
                self._call(self.path, "org.kde.JobViewV3", "update", GLib.Variant("(a{sv})", (props,)))
            except Exception:
                pass
        elif percent is not None:
            self._fallback(message or self.title, percent)

    def finish(self, ok=True, message=""):
        if self.path:
            from gi.repository import GLib
            try:
                self._call(self.path, "org.kde.JobViewV3", "terminate",
                           GLib.Variant("(usa{sv})", (0 if ok else 1, "" if ok else (message or "Failed"), {})))
            except Exception:
                pass
        if message:
            notify(self.title, message, "normal" if ok else "critical")

    def _fallback(self, body, percent):
        if not shutil.which("notify-send"):
            return
        cmd = ["notify-send", "-a", "Gill-OSaab", "-p", self.title, body]
        if percent is not None:
            cmd[1:1] = ["-h", f"int:value:{int(percent)}"]
        if self.notify_id:
            cmd[1:1] = ["-r", self.notify_id]
        out = subprocess.run(cmd, capture_output=True, text=True, check=False)
        self.notify_id = out.stdout.strip() or self.notify_id


def notify(title, body="", urgency="normal"):
    """Desktop notification; silently skipped when notify-send is missing."""
    if shutil.which("notify-send"):
        subprocess.run(["notify-send", "-a", "Gill-OSaab", "-u", urgency, title, body], check=False)
    else:
        print(f"{title}: {body}")
