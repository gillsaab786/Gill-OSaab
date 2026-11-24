"""ROG Ally stick lights: colour maths and the two ways to drive them.

1. The kernel's LED class (multicolour LED with multi_intensity), when the kernel has the Ally
   lights driver.
2. Otherwise the controller's own HID commands (vendor page 0xFF31), the same packets Handheld
   Daemon sends: 0x5A 0xB3 zone mode R G B ..., then "set" (0xB5) and "apply" (0xB4).
"""
import colorsys
import re
from pathlib import Path

DMI = Path("/sys/class/dmi/id")
LEDS = Path("/sys/class/leds")
HIDRAW = Path("/sys/class/hidraw")
ASUS_VID = 0x0B05
ALLY_PIDS = {0x1ABE, 0x1B4C}  # ROG Ally, ROG Ally X
REPORT = 0x5A
MODES = {"solid": 0x00, "breathing": 0x01, "rainbow": 0x02}
SPEED = 0xEB
# colours are stored as six hex digits without "#" ("#" starts a comment in .conf files)
DEFAULTS = {"lights_mode": "gaming", "lights_color": "0a84ff", "lights_game_color": "ff2d55",
            "lights_brightness": "70", "lights_vividness": "100", "lights_effect": "solid"}


def read(path):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return ""


def is_rog_ally(dmi=DMI):
    product, board = read(dmi / "product_name"), read(dmi / "board_name")
    text = f"{product} {board}".upper()
    return "ALLY" in text or bool(re.search(r"\bRC7[123]", text))


def parse_hex(value):
    m = re.fullmatch(r"#?([0-9a-fA-F]{6})", value or "")
    if not m:
        return (10, 132, 255)
    h = m.group(1)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shade(rgb, brightness, vividness):
    """Colour after the brightness (0-100) and vividness (0 grey - 100 full colour) sliders."""
    r, g, b = (c / 255 for c in rgb)
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    s *= max(0, min(100, vividness)) / 100
    v *= max(0, min(100, brightness)) / 100
    return tuple(round(c * 255) for c in colorsys.hsv_to_rgb(h, s, v))


def wanted(settings, gaming):
    """(rgb, effect) for now, or None when the lights should be off."""
    mode = settings.get("lights_mode", DEFAULTS["lights_mode"])
    if mode == "off":
        return None
    key = "lights_game_color" if mode == "gaming" and gaming else "lights_color"
    rgb = parse_hex(settings.get(key, DEFAULTS[key]))
    bright = int(settings.get("lights_brightness", DEFAULTS["lights_brightness"]) or 0)
    vivid = int(settings.get("lights_vividness", DEFAULTS["lights_vividness"]) or 0)
    if bright <= 0:
        return None
    effect = settings.get("lights_effect", "solid")
    return shade(rgb, bright, vivid), effect if effect in MODES else "solid"


# ---- kernel LED class
def find_led(leds=LEDS):
    for d in sorted(leds.glob("*")):
        name = d.name.lower()
        if (d / "multi_intensity").exists() and re.search(r"ally|joystick|asus.*:rgb", name):
            return d
    return None


def led_write(d, rgb):
    """Write a colour to a multicolour LED, matching the colour order in multi_index."""
    order = read(d / "multi_index").split() or ["red", "green", "blue"]
    comp = {"red": rgb[0], "green": rgb[1], "blue": rgb[2]}
    values = [comp.get(c, 0) for c in order]
    (d / "multi_intensity").write_text(" ".join(map(str, values)) + "\n")
    top = int(read(d / "max_brightness") or 255)
    (d / "brightness").write_text(f"{top if any(rgb) else 0}\n")


# ---- controller HID commands
def find_hidraw(hidraw=HIDRAW):
    for d in sorted(hidraw.glob("hidraw*")):
        uevent = read(d / "device/uevent")
        m = re.search(r"HID_ID=\w+:0*([0-9A-Fa-f]+):0*([0-9A-Fa-f]+)", uevent)
        if not m or int(m.group(1), 16) != ASUS_VID:
            continue
        try:
            desc = (d / "device/report_descriptor").read_bytes()
        except OSError:
            continue
        # vendor usage page 0xFF31, usage 0x80: the controller's configuration interface
        if b"\x06\x31\xff" in desc and b"\x09\x80" in desc:
            return Path("/dev") / d.name
    return None


def pad(data, size=64):
    return bytes(data) + bytes(size - len(data))


def hid_packets(rgb, effect):
    """The packets that set both sticks' rings to one colour (or switch them off)."""
    init = pad([REPORT] + list(b"ASUS Tech.Inc."))
    if rgb is None:
        return [init, pad([REPORT, 0xB3, 0, 0, 0, 0, 0]), pad([REPORT, 0xBA, 0xC5, 0xC4, 0x00]),
                pad([REPORT, 0xB5]), pad([REPORT, 0xB4])]
    r, g, b = rgb
    mode = MODES.get(effect, 0)
    speed = 0 if mode == 0 else SPEED
    cmd = pad([REPORT, 0xB3, 0x00, mode, r, g, b, speed, 0x00, 0x00, 0, 0, 0])
    return [init, cmd, pad([REPORT, 0xBA, 0xC5, 0xC4, 0x03]), pad([REPORT, 0xB5]), pad([REPORT, 0xB4])]
