"""Gill(OS) Notifications: Decky backend.

Watches the hub's live state file and pushes changes to the Quick Access tab;
forwards Dismiss/Cancel/Clear to the hub over D-Bus.
"""
import asyncio
import json
import os
import pwd
import subprocess

try:
    import decky
except ImportError:  # unit tests
    decky = None


def user_uid():
    name = getattr(decky, "DECKY_USER", None) if decky else None
    if name:
        try:
            return pwd.getpwnam(name).pw_uid
        except KeyError:
            pass
    return os.getuid()


def state_path(uid=None):
    uid = user_uid() if uid is None else uid
    return f"/run/user/{uid}/gill-osaab/notifications.json"


def read_state(path):
    try:
        with open(path) as fh:
            data = json.load(fh)
        if isinstance(data, dict) and isinstance(data.get("items"), list):
            return data
    except (OSError, ValueError):
        pass
    return {"version": 1, "items": []}


def hub_command(method, *args, uid=None):
    uid = user_uid() if uid is None else uid
    cmd = ["gdbus", "call", "--session", "--dest", "org.gillosaab.NotifyHub",
           "--object-path", "/org/gillosaab/NotifyHub", "--method", f"org.gillosaab.NotifyHub.{method}",
           *[str(a) for a in args]]
    if os.getuid() == 0 and uid != 0:
        cmd = ["runuser", "-u", pwd.getpwuid(uid).pw_name, "--"] + cmd
    return cmd


def clean_env(uid):
    env = dict(os.environ)
    # Decky is a bundled app; its library path breaks system tools like gdbus
    env.pop("LD_LIBRARY_PATH", None)
    if "LD_LIBRARY_PATH_ORIG" in env:
        env["LD_LIBRARY_PATH"] = env.pop("LD_LIBRARY_PATH_ORIG")
    env["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path=/run/user/{uid}/bus"
    return env


def run_hub(method, *args):
    uid = user_uid()
    try:
        subprocess.run(hub_command(method, *args, uid=uid), env=clean_env(uid),
                       capture_output=True, timeout=5, check=False)
    except (OSError, subprocess.TimeoutExpired):
        pass


def user_env(uid):
    env = clean_env(uid)
    env["XDG_RUNTIME_DIR"] = f"/run/user/{uid}"
    return env


def run_user(cmd, timeout=5):
    """Run a tool as the person signed in (Decky may run as admin)."""
    uid = user_uid()
    if os.getuid() == 0 and uid != 0:
        cmd = ["runuser", "-u", pwd.getpwuid(uid).pw_name, "--"] + cmd
    try:
        return subprocess.run(cmd, env=user_env(uid), capture_output=True, text=True, timeout=timeout,
                              check=False).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def parse_volume(text):
    """wpctl get-volume -> (0-100, muted)."""
    parts = text.split()
    try:
        vol = round(float(parts[1]) * 100)
    except (IndexError, ValueError):
        vol = 50
    return max(0, min(100, vol)), "MUTED" in text


def parse_brightness(text):
    """brightnessctl -m -> 0-100 (None when the screen has no adjustable backlight)."""
    parts = text.strip().split(",")
    if len(parts) >= 4 and parts[3].endswith("%"):
        return int(parts[3][:-1])
    return None


def read_power(path="/run/gill-osaab/power.json"):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


class Plugin:
    async def get_device(self):
        vol, muted = parse_volume(await asyncio.to_thread(run_user, ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]))
        bright = parse_brightness(await asyncio.to_thread(run_user, ["brightnessctl", "-m"]))
        power = read_power()
        return {"volume": vol, "muted": muted, "brightness": bright, "battery": power.get("battery"),
                "mode": power.get("label", ""), "watts": power.get("watts", 0)}

    async def set_volume(self, value):
        v = max(0, min(100, int(value)))
        await asyncio.to_thread(run_user, ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{v}%"])
        await asyncio.to_thread(run_user, ["/usr/libexec/gill-osaab/gosaab-haptic", "tick"])

    async def set_brightness(self, value):
        v = max(1, min(100, int(value)))
        await asyncio.to_thread(run_user, ["brightnessctl", "-q", "set", f"{v}%"])
        await asyncio.to_thread(run_user, ["/usr/libexec/gill-osaab/gosaab-haptic", "tick"])

    async def get_state(self):
        return read_state(state_path())

    async def dismiss(self, item_id):
        await asyncio.to_thread(run_hub, "Dismiss", int(item_id))

    async def cancel(self, item_id):
        await asyncio.to_thread(run_hub, "Cancel", int(item_id))

    async def clear(self):
        await asyncio.to_thread(run_hub, "Clear")

    async def _main(self):
        last = None
        while True:
            path = state_path()
            try:
                mtime = os.stat(path).st_mtime_ns
            except OSError:
                mtime = None
            if mtime != last:
                last = mtime
                if decky:
                    await decky.emit("gosaab_state", read_state(path))
            await asyncio.sleep(0.5)

    async def _unload(self):
        pass

    async def _uninstall(self):
        pass
