"""Hardware detection for Gill-OSaab: model, BIOS, CPU, GPUs, network chips and their drivers."""
import shutil
import subprocess
from pathlib import Path

DMI = Path("/sys/class/dmi/id")

# Where each maker publishes BIOS updates when they aren't on LVFS (fwupd)
SUPPORT_PAGES = {
    "asus": "https://rog.asus.com/support/",
    "gpd": "https://gpd.hk/",
    "valve": "https://help.steampowered.com/",
    "lenovo": "https://pcsupport.lenovo.com/",
    "msi": "https://www.msi.com/support",
    "ayaneo": "https://www.ayaneo.com/support",
    "dell": "https://www.dell.com/support/",
    "hp": "https://support.hp.com/drivers",
    "framework": "https://knowledgebase.frame.work/",
}


def read(path):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return ""


def device_model(dmi=DMI):
    vendor = read(dmi / "sys_vendor")
    product = read(dmi / "product_name")
    return {
        "vendor": vendor,
        "product": product,
        "board": read(dmi / "board_name"),
        "bios_version": read(dmi / "bios_version"),
        "bios_date": read(dmi / "bios_date"),
        "name": " ".join(p for p in (vendor, product) if p and p.lower() not in ("to be filled by o.e.m.",)),
    }


def cpu_model(cpuinfo="/proc/cpuinfo"):
    for line in read(cpuinfo).splitlines():
        if line.lower().startswith("model name"):
            return line.split(":", 1)[1].strip()
    return ""


def parse_lspci(text):
    """Parse `lspci -vmmk` output into a list of devices."""
    devices, cur = [], {}
    for line in text.splitlines() + [""]:
        if not line.strip():
            if cur:
                devices.append(cur)
                cur = {}
            continue
        if ":" in line:
            key, value = line.split(":", 1)
            cur[key.strip()] = value.strip()
    return devices


def pci_devices(runner=subprocess.run):
    if not shutil.which("lspci"):
        return []
    out = runner(["lspci", "-vmmk"], capture_output=True, text=True, check=False)
    return parse_lspci(out.stdout)


def other_parts(devices):
    """Every other chip (audio, storage, USB, Bluetooth...) with the driver the kernel picked."""
    skip = ("VGA compatible controller", "3D controller", "Display controller", "Network controller",
            "Ethernet controller", "Host bridge", "PCI bridge", "ISA bridge", "SMBus", "Signal processing controller")
    return [{"kind": d.get("Class", ""), "vendor": d.get("Vendor", ""), "device": d.get("Device", ""),
             "driver": d.get("Driver", "")} for d in devices if d.get("Class", "") not in skip]


def usb_devices(runner=subprocess.run):
    """Plugged-in USB things (controllers, dongles, printers, webcams) as 'Vendor Product' names."""
    if not shutil.which("lsusb"):
        return []
    out = runner(["lsusb"], capture_output=True, text=True, check=False).stdout
    names = []
    for line in out.splitlines():
        name = line.split(" ID ", 1)[-1][10:].strip() if " ID " in line else ""
        if name and "root hub" not in name.lower() and name not in names:
            names.append(name)
    return names


def classify(devices):
    gpus, network = [], []
    for d in devices:
        cls = d.get("Class", "")
        entry = {"vendor": d.get("Vendor", ""), "device": d.get("Device", ""),
                 "driver": d.get("Driver", ""), "slot": d.get("Slot", "")}
        if cls in ("VGA compatible controller", "3D controller", "Display controller"):
            gpus.append(entry)
        elif cls in ("Network controller", "Ethernet controller"):
            entry["kind"] = "Wi-Fi" if cls == "Network controller" else "Ethernet"
            network.append(entry)
    return gpus, network


def has_nvidia(gpus):
    return any("nvidia" in g["vendor"].lower() for g in gpus)


def support_page(vendor):
    v = vendor.lower()
    for key, url in SUPPORT_PAGES.items():
        if key in v:
            return url
    return ""


def summary(dmi=DMI, runner=subprocess.run, cpuinfo="/proc/cpuinfo"):
    devices = pci_devices(runner)
    gpus, network = classify(devices)
    model = device_model(dmi)
    return {"model": model, "cpu": cpu_model(cpuinfo), "gpus": gpus, "network": network,
            "parts": other_parts(devices), "usb": usb_devices(runner),
            "nvidia": has_nvidia(gpus), "support_page": support_page(model["vendor"])}
