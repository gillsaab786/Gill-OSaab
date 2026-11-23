"""Gill-OSaab Notifications: Decky backend.

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


class Plugin:
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
