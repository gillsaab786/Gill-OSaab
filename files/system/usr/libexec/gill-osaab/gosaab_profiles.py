"""Per-game profiles: TDP, graphics chip, FPS cap and stick-light colour for one game.

Stored (as admin) in /etc/gill-osaab/game-profiles.json:
  {"steam:1245620": {"name": "ELDEN RING", "tdp": 15, "gpu": "auto", "fps": 40, "lights": "ff2d55"}}
A game is known by its Steam app id ("steam:<id>"), its Windows .exe ("exe:<name.exe>") or the
emulator running it ("app:<name>").
"""
import json
import os
import re
from pathlib import Path

PATH = Path(os.environ.get("GOSAAB_ETC", "/etc/gill-osaab")) / "game-profiles.json"
KEY_RE = re.compile(r"(steam:\d{1,10}|exe:[\w .()+\-]{1,80}\.exe|app:[a-z0-9_.\-]{1,40})")
FIELDS = {
    "name": lambda v: isinstance(v, str) and 0 < len(v) <= 80 and "\n" not in v,
    "tdp": lambda v: isinstance(v, int) and 0 <= v <= 120,       # 0 = Smart TDP decides
    "gpu": lambda v: v in ("auto", "dedicated", "integrated"),
    "fps": lambda v: isinstance(v, int) and (v == 0 or 15 <= v <= 240),  # 0 = no cap
    "lights": lambda v: v == "" or (isinstance(v, str) and re.fullmatch(r"[0-9a-fA-F]{6}", v) is not None),
}
EMULATORS = re.compile(r"\b(retroarch|dolphin-emu|pcsx2|rpcs3|yuzu|suyu|citron|ryujinx|azahar|citra|lime3ds|"
                       r"duckstation|ppsspp|cemu|xemu|melonds|mgba|shadps4|vita3k|xenia|eden)\b", re.I)
NOT_GAME_EXES = {"explorer.exe", "services.exe", "winedevice.exe", "rpcss.exe", "plugplay.exe", "svchost.exe",
                 "steam.exe", "steamwebhelper.exe", "start.exe", "conhost.exe", "winedbg.exe", "wineboot.exe",
                 "tabtip.exe", "crashpad_handler.exe", "unitycrashhandler64.exe", "easyanticheat.exe"}


def valid_key(key):
    return bool(KEY_RE.fullmatch(key or ""))


def clean(profile):
    """Only known fields with valid values."""
    out = {}
    for k, v in (profile or {}).items():
        if k in FIELDS and FIELDS[k](v):
            out[k] = v
    return out


def load(path=None):
    try:
        data = json.loads((path or PATH).read_text())
    except (OSError, ValueError):
        return {}
    return {k: clean(v) for k, v in data.items() if valid_key(k) and isinstance(v, dict)} if isinstance(data, dict) else {}


def save(profiles, path=None):
    path = path or PATH
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(profiles, indent=1, sort_keys=True))
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def current_game(cmdlines):
    """(key, name) of the game being played, from the running programs' command lines."""
    for cmd in cmdlines:
        m = re.search(r"SteamLaunch AppId=(\d+)", cmd)
        if m:
            return f"steam:{m.group(1)}", ""
    for cmd in cmdlines:
        for name in re.findall(r"(?:^|[/\\\s\"'])([\w(+\-][\w .()+\-]*?\.exe)\b", cmd, re.I):
            name = name.strip()
            if name.lower() not in NOT_GAME_EXES:
                return f"exe:{name.lower()}", name
    for cmd in cmdlines:
        m = EMULATORS.search(cmd)
        if m:
            return f"app:{m.group(1).lower()}", m.group(1)
    return "", ""


def steam_games(home):
    """Installed Steam games: [(key, name)] from Steam's library manifests."""
    out = {}
    roots = [Path(home) / ".local/share/Steam/steamapps"]
    lib = roots[0] / "libraryfolders.vdf"
    try:
        for p in re.findall(r'"path"\s+"([^"]+)"', lib.read_text(errors="replace")):
            roots.append(Path(p) / "steamapps")
    except OSError:
        pass
    for r in roots:
        for f in r.glob("appmanifest_*.acf"):
            try:
                text = f.read_text(errors="replace")
            except OSError:
                continue
            appid = re.search(r'"appid"\s+"(\d+)"', text)
            name = re.search(r'"name"\s+"([^"]+)"', text)
            if appid and name and not re.search(r"Proton|Steam Linux Runtime|Steamworks", name.group(1)):
                out[f"steam:{appid.group(1)}"] = name.group(1)
    return sorted(out.items(), key=lambda kv: kv[1].lower())
