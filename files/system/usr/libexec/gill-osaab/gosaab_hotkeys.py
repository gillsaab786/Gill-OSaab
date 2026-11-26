"""Button and key-combo shortcuts: parsing, matching and the list of things a button can do.

A shortcut is one line in hotkeys.conf:   META+R = mode
Keys use Linux input names (KEY_R, BTN_MODE...) without the KEY_ prefix; modifiers are META (Windows/
Super key), CTRL, ALT, SHIFT. Handheld buttons are whatever the device sends (record them in Settings).
"""
import os
import re
import stat
from pathlib import Path

SYSTEM_CONF = Path("/etc/gill-osaab/hotkeys.conf")
USER_CONF_NAME = ".config/gill-osaab/hotkeys.conf"
SOCKET = "/run/gosaab-hotkeyd.sock"

MODIFIERS = ["META", "CTRL", "ALT", "SHIFT"]
ALIASES = {"LEFTMETA": "META", "RIGHTMETA": "META", "SUPER": "META", "WIN": "META", "WINDOWS": "META",
           "LOGO": "META", "LEFTCTRL": "CTRL", "RIGHTCTRL": "CTRL", "CONTROL": "CTRL", "LEFTALT": "ALT",
           "RIGHTALT": "ALT", "LEFTSHIFT": "SHIFT", "RIGHTSHIFT": "SHIFT"}
FRIENDLY = {"META": "Windows", "CTRL": "Ctrl", "ALT": "Alt", "SHIFT": "Shift", "BTN_MODE": "Home button",
            "BTN_SELECT": "View button", "BTN_START": "Menu button", "BTN_SOUTH": "A", "BTN_EAST": "B",
            "BTN_NORTH": "X", "BTN_WEST": "Y", "BTN_TL": "LB", "BTN_TR": "RB", "BTN_TL2": "LT", "BTN_TR2": "RT",
            "BTN_THUMBL": "Left stick press", "BTN_THUMBR": "Right stick press", "BTN_TRIGGER_HAPPY1": "Back paddle 1",
            "BTN_TRIGGER_HAPPY2": "Back paddle 2", "BTN_TRIGGER_HAPPY3": "Back paddle 3",
            "BTN_TRIGGER_HAPPY4": "Back paddle 4"}

ACTIONS = {
    "mode": "Switch between Game Mode and Desktop",
    "game": "Go to Game Mode",
    "desktop": "Go to Desktop",
    "launchpad": "Open Launchpad (all apps)",
    "spotlight": "Search (Spotlight)",
    "controlcenter": "Control Centre",
    "notifications": "Notification Centre",
    "screenshot": "Take a screenshot",
    "lock": "Lock the screen",
    "settings": "Open Settings",
    "none": "Nothing (turn this shortcut off)",
}


def key_token(name):
    """evdev name (KEY_LEFTMETA, KEY_R, BTN_MODE) or typed name (Win, r) -> canonical token."""
    n = name.strip().upper()
    if n.startswith("KEY_"):
        n = n[4:]
    n = ALIASES.get(n, n)
    return n


def canonical(keys):
    """A set of key tokens -> 'META+CTRL+R' (modifiers first in a fixed order, then the rest sorted)."""
    toks = {key_token(k) for k in keys if k}
    mods = [m for m in MODIFIERS if m in toks]
    rest = sorted(toks - set(MODIFIERS))
    return "+".join(mods + rest)


def parse_combo(text):
    parts = [p for p in re.split(r"\s*\+\s*", text.strip()) if p]
    if not parts or any(not re.fullmatch(r"[A-Za-z0-9_]+", p) for p in parts):
        return ""
    return canonical(parts)


TYPING = re.compile(r"^([A-Z0-9]|MINUS|EQUAL|SPACE|ENTER|TAB|BACKSPACE|COMMA|DOT|SLASH|SEMICOLON|APOSTROPHE|"
                    r"GRAVE|BACKSLASH|LEFTBRACE|RIGHTBRACE|ESC|UP|DOWN|LEFT|RIGHT|KP\w*)$")


def is_allowed(combo):
    """Shortcuts must not fire while typing: plain letters (even with Shift) aren't allowed alone."""
    toks = combo.split("+") if combo else []
    if not toks:
        return False
    if any(t in ("META", "CTRL", "ALT") for t in toks):
        return len(toks) >= 2 or toks == ["META"]
    return not all(TYPING.match(t) or t == "SHIFT" for t in toks)


GROUP_MAX = 12


def group_items(action):
    """'group:app:itunes|open:/home/me/Desktop/iPhone apps' -> [('app', 'itunes'), ('open', '/home/...')]
    or None if any part isn't valid. Opens several apps, folders, files or websites with one shortcut."""
    if not action.startswith("group:"):
        return None
    items = []
    for part in action[6:].split("|"):
        kind, _, value = part.partition(":")
        if "\n" in value or "\0" in value or not value.strip():
            return None
        if kind == "app" and re.fullmatch(r"[\w.\-]+", value):
            items.append(("app", value))
        elif kind == "open" and (value.startswith("/") or re.match(r"https?://[^\s]+$", value)):
            items.append(("open", value))
        else:
            return None
    return items if 0 < len(items) <= GROUP_MAX else None


def valid_action(action):
    if action in ACTIONS:
        return True
    if action.startswith("group:"):
        return group_items(action) is not None
    if action.startswith("app:"):
        return bool(re.fullmatch(r"[\w.\-]+", action[4:]))
    if action.startswith("run:"):
        return bool(action[4:].strip()) and "\n" not in action
    return False


def describe(combo):
    return " + ".join(FRIENDLY.get(t, t.replace("BTN_", "").replace("_", " ").title() if t.startswith("BTN_")
                                   else t.title() if len(t) > 1 else t) for t in combo.split("+"))


def describe_action(action):
    items = group_items(action)
    if items:
        names = [v if k == "app" else (v if v.startswith("http") else Path(v).name or v) for k, v in items]
        return "Open " + ", ".join(names)
    if action.startswith("app:"):
        return f"Open {action[4:]}"
    if action.startswith("run:"):
        return f"Run: {action[4:]}"
    return ACTIONS.get(action, action)


def parse_config(text):
    out = {}
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("#") or "=" not in line:
            continue
        combo, action = (x.strip() for x in line.split("=", 1))
        combo = parse_combo(combo)
        if combo and is_allowed(combo) and valid_action(action):
            out[combo] = action
    return out


def format_config(bindings):
    lines = ["# Gill(OS) button shortcuts (edited by Settings > Buttons & Shortcuts)",
             "# combo = action      e.g.  META+R = mode   BTN_MODE+BTN_SOUTH = app:steam"]
    lines += [f"{c} = {a}" for c, a in sorted(bindings.items())]
    return "\n".join(lines) + "\n"


def effective(system, user):
    """System defaults, then the user's own (an action of 'none' turns a default off)."""
    merged = dict(system)
    merged.update(user)
    return {c: a for c, a in merged.items() if a != "none"}


def read_user_conf(home, uid, limit=65536):
    """Read a user's shortcut file safely (the reader may be root): no symlinks, owned by that user."""
    path = Path(home) / USER_CONF_NAME
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return ""
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != uid or st.st_size > limit:
            return ""
        return os.read(fd, limit).decode(errors="replace")
    finally:
        os.close(fd)


class Matcher:
    """Feed key presses/releases; returns the action when a bound combo is completed."""

    def __init__(self, bindings=None):
        self.bindings = bindings or {}
        self.held = set()
        self.peak = set()  # biggest set held since all keys were up (for recording)

    def press(self, key):
        tok = key_token(key)
        self.held.add(tok)
        self.peak |= self.held
        return self.bindings.get(canonical(self.held))

    def release(self, key):
        """Returns the whole combo once every key is let go (used by Record)."""
        self.held.discard(key_token(key))
        if not self.held and self.peak:
            combo, self.peak = canonical(self.peak), set()
            return combo
        return None
