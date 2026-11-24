"""Smart TDP and graphics switching: what the device is doing, how much power to give it, and which
graphics chip apps should use. Pure logic here (tested); gosaab-smart-power applies it.

Modes, from least to most power:  idle → video → desktop → game
"""
import glob
import os
import re
from pathlib import Path

MODES = ["idle", "video", "desktop", "game"]
LABELS = {"idle": "Idle", "video": "Video", "desktop": "Everyday", "game": "Gaming"}

# --------------------------------------------------------------------------- device class and TDP
HANDHELD_CPU = re.compile(r"Z1|Z2|Extreme|7840U|8840U|7640U|8640U|6800U|7735U|HX 370|AI 9 HX|Van Gogh|"
                          r"Core Ultra 7 258V|Lunar Lake|Custom APU", re.I)


def device_class(cpu, chassis, has_battery):
    """handheld / laptop / desktop (decides the default watts)."""
    if HANDHELD_CPU.search(cpu or "") and has_battery and chassis in ("30", "31", "32", "8", "10", "1", ""):
        return "handheld"
    if has_battery or chassis in ("8", "9", "10", "14", "31", "32"):
        return "laptop"
    return "desktop"


DEFAULT_WATTS = {  # (idle, video, desktop, game)
    "handheld": (5, 7, 12, 25),
    "laptop": (8, 10, 18, 45),
    "desktop": (0, 0, 0, 0),  # desktops: power profiles only (no package limits)
}


def watts_for(device, conf):
    defaults = dict(zip(MODES, DEFAULT_WATTS[device]))
    out = {}
    for m in MODES:
        v = conf.get(f"tdp_{m}", "")
        out[m] = int(v) if str(v).isdigit() and int(v) > 0 else defaults[m]
    return out


PROFILE = {"idle": "power-saver", "video": "power-saver", "desktop": "balanced", "game": "performance"}

# --------------------------------------------------------------------------- what is the device doing?
GAME_PATTERNS = re.compile(
    r"SteamLaunch AppId=|steam_app_\d|/proton |\bwine64-preloader\b|\bwine-preloader\b|gamescope.*--|"
    r"\b(retroarch|dolphin-emu|pcsx2|PCSX2|rpcs3|yuzu|suyu|citron|ryujinx|Ryujinx|azahar|citra|lime3ds|"
    r"duckstation|ppsspp|PPSSPP|cemu|Cemu|xemu|melonDS|mgba|shadps4|vita3k|xenia|eden)\b", re.I)
NOT_GAMES = re.compile(r"steamwebhelper|steam-runtime-launcher|winedevice|explorer\.exe|services\.exe|"
                       r"rpcss|plugplay|winedbg|steamerrorreporter", re.I)


def game_running(cmdlines):
    for cmd in cmdlines:
        if GAME_PATTERNS.search(cmd) and not NOT_GAMES.search(cmd):
            return True
    return False


def decide(signals, previous="desktop", since_change=0.0, hold=15.0):
    """Pick the mode. Going up is instant; going down waits `hold` seconds so it doesn't flicker."""
    if signals.get("game") or signals.get("gpu_busy", 0) >= 70:
        want = "game"
    elif signals.get("idle"):
        want = "idle"
    elif signals.get("video"):
        want = "video"
    else:
        want = "desktop"
    if MODES.index(want) < MODES.index(previous) and since_change < hold:
        return previous
    return want


# --------------------------------------------------------------------------- backends
def tdp_backends(root=Path("/")):
    """Ways this device lets us set its power limit, best first."""
    out = []
    fa = root / "sys/class/firmware-attributes"
    for attr in ("ppt_pl1_spl", "ppt_pl1_stapm"):
        hits = sorted(fa.glob(f"*/attributes/{attr}/current_value"))
        if hits:
            out.append(("firmware-attributes", str(hits[0].parent.parent)))  # ROG Ally, Legion Go, …
            break
    for f in ("sys/devices/platform/asus-nb-wmi/ppt_pl1_spl",):
        if (root / f).exists():
            out.append(("asus-wmi", str((root / f).parent)))
    rapl = sorted(root.glob("sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw"))
    cpuinfo = (root / "proc/cpuinfo").read_text(errors="ignore")[:4000] if (root / "proc/cpuinfo").exists() else ""
    if rapl and "GenuineIntel" in cpuinfo:  # Intel processors take limits through RAPL
        out.append(("intel-rapl", str(rapl[0].parent)))
    if "AuthenticAMD" in cpuinfo and any((root / d / "ryzenadj").exists() for d in ("usr/bin", "usr/local/bin")):
        out.append(("ryzenadj", "ryzenadj"))
    out.append(("power-profile", ""))  # every PC
    return out


def tdp_actions(backend, path, watts):
    """Files to write / commands to run for a package limit of `watts` (fast/peak limits a bit higher)."""
    if watts <= 0:
        return []
    sppt, fppt = watts + max(2, watts // 5), watts + max(4, watts // 3)
    if backend == "firmware-attributes":
        return [("write", f"{path}/ppt_pl1_spl/current_value", str(watts)),
                ("write", f"{path}/ppt_pl2_sppt/current_value", str(sppt)),
                ("write", f"{path}/ppt_pl3_fppt/current_value", str(fppt))]
    if backend == "asus-wmi":
        return [("write", f"{path}/ppt_pl1_spl", str(watts)), ("write", f"{path}/ppt_pl2_sppt", str(sppt)),
                ("write", f"{path}/ppt_fppt", str(fppt))]
    if backend == "intel-rapl":
        return [("write", f"{path}/constraint_0_power_limit_uw", str(watts * 1_000_000)),
                ("write", f"{path}/constraint_1_power_limit_uw", str(sppt * 1_000_000))]
    if backend == "ryzenadj":
        return [("run", ["ryzenadj", f"--stapm-limit={watts * 1000}", f"--slow-limit={sppt * 1000}",
                         f"--fast-limit={fppt * 1000}"])]
    return []


def clamp_watts(watts, lo=3, hi=120):
    return max(lo, min(hi, watts))


# --------------------------------------------------------------------------- graphics switching
def hybrid(gpus):
    """(integrated, dedicated) when the PC has both, else None."""
    igpu = next((g for g in gpus if not g["discrete"]), None)
    dgpu = next((g for g in gpus if g["discrete"]), None)
    return (igpu, dgpu) if igpu and dgpu else None


def offload_env(dgpu):
    """Environment that makes an app render on the dedicated chip (the screen stays on the integrated one)."""
    if not dgpu:
        return {}
    if dgpu["vendor"] == "nvidia" and dgpu.get("driver") == "nvidia":
        return {"__NV_PRIME_RENDER_OFFLOAD": "1", "__GLX_VENDOR_LIBRARY_NAME": "nvidia",
                "__VK_LAYER_NV_optimus": "NVIDIA_only", "__EGL_VENDOR_LIBRARY_FILENAMES":
                "/usr/share/glvnd/egl_vendor.d/10_nvidia.json"}
    slot = dgpu.get("slot", "")
    tag = "pci-" + re.sub(r"[:.]", "_", slot if slot.count(":") == 2 else f"0000:{slot}") if slot else "1"
    return {"DRI_PRIME": tag}  # Mesa (AMD, Intel Arc, Nvidia with NVK)


GPU_HEAVY_APPS = re.compile(r"^(steam|com\.valvesoftware\.Steam|net\.lutris\.Lutris|com\.heroicgameslauncher\.hgl|"
                            r"com\.usebottles\.bottles|org\.libretro\.RetroArch|retroarch|gosaab-emudeck|"
                            r"emulationstation|org\.DolphinEmu.*|net\.pcsx2.*|net\.rpcs3.*|org\.ryujinx.*|"
                            r"org\.blender\.Blender|blender|io\.github\.ryubing.*|org\.azahar.*)$", re.I)


def app_wants_dgpu(desktop_id, categories="", prefers_non_default=False):
    return prefers_non_default or bool(GPU_HEAVY_APPS.match(desktop_id)) or "Game" in categories.split(";")


def pci_path(slot):
    s = slot if slot.count(":") == 2 else f"0000:{slot}"
    return f"/sys/bus/pci/devices/{s}"


def dgpu_users(slot, proc="/proc"):
    """Processes using the dedicated chip right now: [(pid, name)] (own processes only; that's enough)."""
    devpath = Path(pci_path(slot)) / "drm"
    nodes = {f"/dev/dri/{p.name}" for p in devpath.glob("*")} if devpath.exists() else set()
    users = []
    for fd_dir in glob.glob(f"{proc}/[0-9]*/fd"):
        pid = fd_dir.split("/")[-2]
        try:
            for fd in os.listdir(fd_dir):
                target = os.readlink(f"{fd_dir}/{fd}")
                if target in nodes or target.startswith("/dev/nvidia") and target[11:12].isdigit():
                    name = Path(f"{proc}/{pid}/comm").read_text().strip()
                    users.append((int(pid), name))
                    break
        except OSError:
            continue
    return users
