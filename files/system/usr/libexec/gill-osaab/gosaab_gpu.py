"""Which graphics chip(s) this device has and the best FPS setup for each (tested in tests/)."""
import re

import gosaab_hw

NVIDIA = [(r"\bGB2\d\d|RTX 50\d\d", "rtx50"), (r"\bAD1\d\d|RTX 40\d\d", "rtx40"),
          (r"\bGA1\d\d|RTX 30\d\d|RTX A\d", "rtx30"), (r"\bTU1\d\d|RTX 20\d\d|GTX 16\d\d", "turing")]
AMD = [(r"Navi 4\d|RX 90\d\d", "rdna4"), (r"Navi 3\d|RX 7\d\d\d", "rdna3"),
       (r"Phoenix|Hawk Point|Strix|Krackan|Gorgon|Radeon (7\d0|8\d0)M|Z1|Z2", "rdna3-apu"),
       (r"Navi 2\d|RX 6\d\d\d|Rembrandt|Van Gogh|Mendocino|Radeon 6\d0M", "rdna2")]
INTEL = [(r"DG2|Alchemist|Battlemage|BMG|Arc A\d|Arc B\d", "arc"),
         (r"Meteor Lake|Lunar Lake|Arrow Lake|Panther Lake|Arc Graphics|Arc 1\d0V", "xe-igpu")]


def family(vendor, name):
    table = {"nvidia": NVIDIA, "amd": AMD, "intel": INTEL}.get(vendor, [])
    for pat, fam in table:
        if re.search(pat, name, re.I):
            return fam
    return {"nvidia": "nvidia-old", "amd": "amd-old", "intel": "intel-igpu"}.get(vendor, "other")


def vendor_of(text):
    t = text.lower()
    if "nvidia" in t:
        return "nvidia"
    if "intel" in t:  # before "ati": "corporATIon"
        return "intel"
    if re.search(r"\bamd\b|\bati\b|advanced micro", t):
        return "amd"
    return "other"


def gpus(devices=None, runner=None):
    if devices is None:
        devices = gosaab_hw.pci_devices(runner) if runner else gosaab_hw.pci_devices()
    out = []
    for d in devices:
        if d.get("Class") not in ("VGA compatible controller", "3D controller", "Display controller"):
            continue
        v = vendor_of(d.get("Vendor", ""))
        name = d.get("Device", "")
        fam = family(v, name)
        out.append({"vendor": v, "name": name, "family": fam, "driver": d.get("Driver", ""),
                    "slot": d.get("Slot", ""),
                    "discrete": fam in ("rtx50", "rtx40", "rtx30", "turing", "nvidia-old", "rdna4", "rdna3", "arc")
                    or d.get("Class") == "3D controller"})
    return out


def main_gpu(gs):
    """The chip games run on: a discrete one if there is one."""
    return next((g for g in gs if g["discrete"]), gs[0] if gs else None)


def nvidia_needs_driver(gs):
    """Nvidia's own driver helps (and the open module supports) Turing / RTX 20 and newer."""
    return any(g["vendor"] == "nvidia" and g["family"] in ("rtx50", "rtx40", "rtx30", "turing") for g in gs)


def recommendation(g):
    """Best upscaling / frame generation for this chip. Keys map to environment settings."""
    fam = g["family"] if g else "other"
    rec = {"upgrade": None, "smooth_motion": False, "lsfg": True, "notes": []}
    if fam in ("rtx50", "rtx40", "rtx30", "turing"):
        rec["upgrade"] = "dlss"
        rec["notes"].append("DLSS 4 upscaling and DLSS frame generation in games that offer them (latest DLSS "
                            "is used automatically).")
        if fam in ("rtx50", "rtx40"):
            rec["smooth_motion"] = True
            rec["notes"].append("Nvidia Smooth Motion adds frame generation to games without DLSS frame "
                                "generation.")
    elif fam == "rdna4":
        rec["upgrade"] = "fsr4"
        rec["notes"].append("FSR 4 (AI upscaling + frame generation) in games with FSR 3.1 or newer.")
    elif fam == "rdna3":
        rec["upgrade"] = "fsr4-rdna3"
        rec["notes"].append("FSR 4 on RX 7000 in games with FSR 3.1 or newer.")
    elif fam == "arc":
        rec["upgrade"] = "xess"
        rec["notes"].append("Latest XeSS upscaling and frame generation in games that offer XeSS.")
    else:
        rec["upgrade"] = "fsr3"
        rec["notes"].append("Latest FSR 3 upscaling and frame generation in games that offer FSR.")
    rec["notes"].append("Lossless Scaling frame generation works in every game (Game Mode › Frame generation).")
    if fam in ("rdna3-apu", "rdna2", "intel-igpu", "xe-igpu"):
        rec["notes"].append("Handheld/laptop chip: in Game Mode lower the game resolution and use Steam's FSR "
                            "scaling (… › Performance › Scaling filter) for the biggest FPS gain.")
    return rec


UPGRADE_ENV = {"dlss": {"PROTON_DLSS_UPGRADE": "1", "PROTON_ENABLE_NVAPI": "1"},
               "fsr4": {"PROTON_FSR4_UPGRADE": "1"}, "fsr4-rdna3": {"PROTON_FSR4_RDNA3_UPGRADE": "1"},
               "xess": {"PROTON_XESS_UPGRADE": "1"}, "fsr3": {"PROTON_FSR3_UPGRADE": "1"}}


def environment(rec, upgrade_on=True, smooth_on=False):
    env = {}
    if upgrade_on and rec.get("upgrade"):
        env.update(UPGRADE_ENV[rec["upgrade"]])
    if smooth_on and rec.get("smooth_motion"):
        env["NVPRESENT_ENABLE_SMOOTH_MOTION"] = "1"
    return env
