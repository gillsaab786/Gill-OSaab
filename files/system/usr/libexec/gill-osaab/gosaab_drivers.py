"""Every part of this device, the driver it uses, what's missing, and what can be updated.

Pure parsing lives here (tested); gosaab-drivers is the command that runs it.
"""
import json
import re
import shutil
import subprocess
from pathlib import Path

import gosaab_hw

STATE_FILE = Path("/var/lib/gill-osaab/drivers.json")

CATEGORIES = ["Graphics", "Wi-Fi", "Ethernet", "Bluetooth", "Audio", "Storage", "USB & Thunderbolt",
              "Input & Touch", "Camera", "Controllers & accessories", "Sensors"]
KEYS = {c: re.sub(r"[^a-z]+", "-", c.lower()).strip("-") for c in CATEGORIES}  # "Wi-Fi" -> "wi-fi"
BY_KEY = {v: k for k, v in KEYS.items()}

PCI_CATEGORY = {
    "VGA compatible controller": "Graphics", "3D controller": "Graphics", "Display controller": "Graphics",
    "Network controller": "Wi-Fi", "Ethernet controller": "Ethernet",
    "Audio device": "Audio", "Multimedia audio controller": "Audio",
    "Non-Volatile memory controller": "Storage", "SATA controller": "Storage", "RAID bus controller": "Storage",
    "SD Host controller": "Storage", "USB controller": "USB & Thunderbolt",
    "Multimedia controller": "Camera", "Multimedia video controller": "Camera",
    "Serial bus controller": "Input & Touch",
}
# Parts that don't work at all without a driver (a missing one is reported as a problem)
NEEDS_DRIVER = {"Graphics", "Wi-Fi", "Ethernet", "Audio", "Storage", "USB & Thunderbolt", "Camera", "Bluetooth"}


# ------------------------------------------------------------------ parts and drivers
def pci_parts(devices):
    parts = []
    for d in devices:
        cls = d.get("Class", "")
        cat = PCI_CATEGORY.get(cls)
        name = f"{d.get('Vendor', '')} {d.get('Device', '')}".strip()
        if cls == "System peripheral" and re.search(r"thunderbolt|usb4", name, re.I):
            cat = "USB & Thunderbolt"
        if cat is None:
            continue
        parts.append({"category": cat, "name": name, "driver": d.get("Driver", ""), "bus": "pci",
                      "slot": d.get("Slot", "")})
    return parts


def sys_class_parts(root=Path("/sys/class")):
    """Bluetooth, webcams, touchscreens/pads and sensors seen by the kernel (USB, I2C...)."""
    parts = []

    def driver_of(dev):
        link = dev / "device" / "driver"
        return link.resolve().name if link.exists() else ""

    for hci in sorted((root / "bluetooth").glob("hci*")):
        parts.append({"category": "Bluetooth", "name": f"Bluetooth adapter {hci.name}", "driver": driver_of(hci),
                      "bus": "sys"})
    seen = set()
    for v in sorted((root / "video4linux").glob("video*")):
        name = gosaab_hw.read(v / "name") or v.name
        if name in seen:
            continue
        seen.add(name)
        parts.append({"category": "Camera", "name": name, "driver": driver_of(v), "bus": "sys"})
    for s in sorted((root.parent / "bus" / "iio" / "devices").glob("iio:device*")):
        # screen rotation, light sensor (iio-sensor-proxy reads these)
        parts.append({"category": "Sensors", "name": gosaab_hw.read(s / "name") or s.name, "driver": "iio",
                      "bus": "sys"})
    return parts


def input_parts(text):
    """Touchscreens, touchpads, pens and controllers from /proc/bus/input/devices."""
    parts, name, handlers = [], "", ""
    for line in (text + "\n\n").splitlines():
        if line.startswith("N: Name="):
            name = line.split("=", 1)[1].strip().strip('"')
        elif line.startswith("H: Handlers="):
            handlers = line
        elif not line.strip() and name:
            low = name.lower()
            if name.startswith("gosaab"):
                pass  # our own virtual devices
            elif re.search(r"touchscreen|touchpad|trackpad|stylus|pen\b|elan|goodix|wacom", low):
                parts.append({"category": "Input & Touch", "name": name, "driver": "built in", "bus": "input"})
            elif re.search(r"controller|gamepad|x-box|xbox|dualsense|joy-con|handheld daemon", low) and "js" in handlers:
                parts.append({"category": "Controllers & accessories", "name": name, "driver": "built in",
                              "bus": "input"})
            name, handlers = "", ""
    seen, out = set(), []
    for p in parts:
        if p["name"] not in seen:
            seen.add(p["name"])
            out.append(p)
    return out


def usb_bluetooth_without_adapter(usb_names, parts):
    """A Bluetooth dongle/chip is plugged in but no adapter came up: its driver/firmware is missing."""
    has_adapter = any(p["category"] == "Bluetooth" for p in parts)
    return [n for n in usb_names if "bluetooth" in n.lower()] if not has_adapter else []


# ------------------------------------------------------------------ firmware that failed to load
FW_PATTERNS = [
    re.compile(r"(?P<drv>[\w-]+)(?: [\w:.]+)?: Direct firmware load for (?P<fw>\S+) failed"),
    re.compile(r"(?P<drv>[\w-]+)(?: [\w:.]+)?: firmware: failed to load (?P<fw>\S+)"),
    re.compile(r"firmware: failed to load (?P<fw>\S+)"),
]


def firmware_failures(kernel_log):
    """Firmware files drivers asked for but didn't get. Probing older versions (iwlwifi tries several)
    isn't a problem when the driver loaded one in the end."""
    loaded = set()
    failed = {}
    for line in kernel_log.splitlines():
        m = re.search(r"([\w-]+)(?: [\w:.]+)?: loaded firmware version", line)
        if m:
            loaded.add(m.group(1))
        for pat in FW_PATTERNS:
            m = pat.search(line)
            if m:
                drv = m.groupdict().get("drv") or ""
                failed.setdefault(m.group("fw"), drv)
                break
    return [{"firmware": fw, "driver": drv} for fw, drv in sorted(failed.items())
            if drv not in loaded and not fw.endswith(".sig")]


# ------------------------------------------------------------------ problems
def problems(parts, fw_failures, bt_missing, nvidia_on_core=False):
    out = []
    for p in parts:
        if p["category"] in NEEDS_DRIVER and not p["driver"]:
            out.append({"kind": "missing-driver", "category": p["category"], "name": p["name"],
                        "detail": f"{p['name']} ({p['category']}) has no driver, so it won't work.",
                        "hint": "Send this report to get a driver added to Gill-OSaab."})
    for name in bt_missing:
        out.append({"kind": "missing-driver", "category": "Bluetooth", "name": name,
                    "detail": f"{name} is plugged in but Bluetooth didn't start (driver or firmware missing).",
                    "hint": "Check Bluetooth firmware for this chip."})
    for f in fw_failures:
        out.append({"kind": "missing-firmware", "category": "Firmware", "name": f["firmware"],
                    "detail": f"The {f['driver'] or 'kernel'} driver couldn't load firmware file {f['firmware']}.",
                    "hint": "The part may not work fully until this firmware file is added."})
    if nvidia_on_core:
        out.append({"kind": "limited-driver", "category": "Graphics", "name": "Nvidia",
                    "detail": "Nvidia graphics use the open NVK/nouveau driver here (no Nvidia proprietary driver "
                              "in Gill-OSaab Core). Older Nvidia cards may be slow.",
                    "hint": "Ask for a Core Nvidia edition if games run slowly."})
    return out


# ------------------------------------------------------------------ updates
FWUPD_CATEGORY = [
    (r"nvme|ata|scsi|emmc", "Storage"), (r"thunderbolt|usb4|mst|dock|hub|ccgx", "USB & Thunderbolt"),
    (r"wacom|elan|pixart|goodix|synaptics_(rmi|prometheus)|touch", "Input & Touch"),
    (r"amd_gpu|nvidia|intel_gsc|gpu", "Graphics"), (r"bluez|bluetooth", "Bluetooth"),
    (r"wifi|iwl|wireless|modem|mm\b", "Wi-Fi"), (r"logitech|8bitdo|steelseries|hidpp|controller|gamepad|ebitdo",
                                                  "Controllers & accessories"),
    (r"camera|webcam", "Camera"), (r"audio|headset|jabra", "Audio"),
]


def fwupd_category(dev):
    hay = f"{dev.get('Plugin', '')} {dev.get('Name', '')}".lower()
    for pat, cat in FWUPD_CATEGORY:
        if re.search(pat, hay):
            return cat
    return "Controllers & accessories"


def fwupd_updates(json_text):
    """Device firmware updates (never the BIOS: that has its own careful button)."""
    try:
        devices = json.loads(json_text or "{}").get("Devices", [])
    except ValueError:
        return []
    out = []
    for d in devices:
        if (d.get("Plugin", "")).startswith("uefi") or not d.get("Releases"):
            continue
        dev_id = d.get("DeviceId", "")
        if not re.fullmatch(r"[0-9a-f]{40}", dev_id):
            continue
        out.append({"id": f"fw:{dev_id}", "category": fwupd_category(d), "name": d.get("Name", "Device"),
                    "from": d.get("Version", ""), "to": d["Releases"][0].get("Version", "")})
    return out


def targets_for(categories, fw_updates, builtin=False, have_flatpak_gl=False):
    """What to run when the user ticks some categories (e.g. just Graphics)."""
    cats = set(categories)
    t = []
    if "Graphics" in cats and have_flatpak_gl:
        t.append("gfx-apps")
    t += [u["id"] for u in fw_updates if u["category"] in cats]
    if builtin:
        t.append("builtin")
    return t


def flatpak_gl_refs(runner=subprocess.run):
    """Mesa/Vulkan drivers Flatpak apps and emulators use (updated separately from the system)."""
    if not shutil.which("flatpak"):
        return []
    out = runner(["flatpak", "list", "--runtime", "--columns=application,branch"], capture_output=True,
                 text=True, check=False).stdout
    refs = []
    for line in out.splitlines():
        cols = line.split("\t")
        if cols and cols[0].startswith("org.freedesktop.Platform.GL"):
            refs.append(f"{cols[0]}//{cols[1]}" if len(cols) > 1 and cols[1] else cols[0])
    return refs


# ------------------------------------------------------------------ collecting
def capture(cmd, runner=subprocess.run):
    if not shutil.which(cmd[0]):
        return ""
    try:
        return runner(cmd, capture_output=True, text=True, check=False, timeout=60).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def inventory(runner=subprocess.run, kernel_log=None, sysroot=Path("/sys/class"), input_text=None,
              core=None):
    devices = gosaab_hw.pci_devices(runner)
    parts = pci_parts(devices) + sys_class_parts(sysroot)
    if input_text is None:
        input_text = gosaab_hw.read("/proc/bus/input/devices")
    parts += input_parts(input_text)
    usb = gosaab_hw.usb_devices(runner)
    if kernel_log is None:
        kernel_log = capture(["journalctl", "-k", "-b", "--no-pager", "-o", "cat"], runner)
    fw_fail = firmware_failures(kernel_log)
    bt_missing = usb_bluetooth_without_adapter(usb, parts)
    if core is None:
        core = Path("/usr/share/wayland-sessions/gill-osaab.desktop").exists()
    nvidia = core and any(p["category"] == "Graphics" and "nvidia" in p["name"].lower() for p in parts)
    present = [c for c in CATEGORIES if any(p["category"] == c for p in parts)]
    return {"parts": parts, "categories": present, "usb": usb,
            "problems": problems(parts, fw_fail, bt_missing, nvidia),
            "versions": {"kernel": capture(["uname", "-r"], runner).strip(),
                         "mesa": capture(["rpm", "-q", "--qf", "%{VERSION}", "mesa-dri-drivers"], runner).strip(),
                         "firmware": capture(["rpm", "-q", "--qf", "%{VERSION}", "linux-firmware"], runner).strip()}}


def load_state(path=STATE_FILE):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return {}
