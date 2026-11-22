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


def notify(title, body="", urgency="normal"):
    """Desktop notification; silently skipped when notify-send is missing."""
    if shutil.which("notify-send"):
        subprocess.run(["notify-send", "-a", "Gill-OSaab", "-u", urgency, title, body], check=False)
    else:
        print(f"{title}: {body}")
