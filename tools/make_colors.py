#!/usr/bin/env python3
"""Writes the Gill-OSaab KDE colour schemes (dark + light) into a folder."""
import sys
from pathlib import Path

ACCENT = (31, 182, 201)  # Gill-OSaab teal


def rgb(c):
    return ",".join(str(v) for v in c)


SCHEMES = {
    "GillOSaabDark": dict(
        name="Gill-OSaab Dark", window=(30, 30, 33), view=(22, 22, 25), alt=(28, 28, 32), button=(48, 48, 53),
        header=(38, 38, 42), tooltip=(44, 44, 49), fg=(236, 236, 241), inactive=(146, 146, 156),
        complementary=(18, 18, 21), link=(90, 200, 250), visited=(176, 140, 255),
        negative=(255, 99, 92), neutral=(255, 196, 64), positive=(52, 211, 120),
    ),
    "GillOSaabLight": dict(
        name="Gill-OSaab Light", window=(242, 242, 246), view=(255, 255, 255), alt=(246, 246, 250),
        button=(255, 255, 255), header=(234, 234, 239), tooltip=(250, 250, 252), fg=(28, 28, 32),
        inactive=(110, 110, 120), complementary=(30, 30, 33), link=(0, 122, 204), visited=(120, 80, 210),
        negative=(215, 45, 40), neutral=(196, 130, 0), positive=(30, 150, 80),
    ),
}


def section(bg, alt, s, fg=None):
    fg = fg or s["fg"]
    return {
        "BackgroundAlternate": alt, "BackgroundNormal": bg, "DecorationFocus": ACCENT,
        "DecorationHover": ACCENT, "ForegroundActive": ACCENT, "ForegroundInactive": s["inactive"],
        "ForegroundLink": s["link"], "ForegroundNegative": s["negative"], "ForegroundNeutral": s["neutral"],
        "ForegroundNormal": fg, "ForegroundPositive": s["positive"], "ForegroundVisited": s["visited"],
    }


def build(key, s):
    sections = {
        "Colors:Window": section(s["window"], s["alt"], s),
        "Colors:View": section(s["view"], s["alt"], s),
        "Colors:Button": section(s["button"], s["alt"], s),
        "Colors:Header": section(s["header"], s["window"], s),
        "Colors:Header][Inactive": section(s["window"], s["window"], s),
        "Colors:Tooltip": section(s["tooltip"], s["alt"], s),
        "Colors:Complementary": section(s["complementary"], s["complementary"], s, fg=(236, 236, 241)),
        "Colors:Selection": section(ACCENT, ACCENT, s, fg=(255, 255, 255)),
    }
    lines = [
        "[ColorEffects:Disabled]", "Color=56,56,56", "ColorAmount=0", "ColorEffect=0",
        "ContrastAmount=0.65", "ContrastEffect=1", "IntensityAmount=0.1", "IntensityEffect=2", "",
        "[ColorEffects:Inactive]", "ChangeSelectionColor=true", "Color=112,111,110", "ColorAmount=0.025",
        "ColorEffect=2", "ContrastAmount=0.1", "ContrastEffect=2", "Enable=false", "IntensityAmount=0",
        "IntensityEffect=0", "",
    ]
    for name, values in sections.items():
        lines.append(f"[{name}]")
        lines += [f"{k}={rgb(v)}" for k, v in values.items()]
        lines.append("")
    lines += [
        "[General]", f"ColorScheme={key}", f"Name={s['name']}", "shadeSortColumn=true", "",
        "[KDE]", "contrast=4", "",
        "[WM]", f"activeBackground={rgb(s['header'])}", f"activeBlend={rgb(s['fg'])}",
        f"activeForeground={rgb(s['fg'])}", f"inactiveBackground={rgb(s['window'])}",
        f"inactiveBlend={rgb(s['inactive'])}", f"inactiveForeground={rgb(s['inactive'])}", "",
    ]
    return "\n".join(lines)


def main(dest):
    dest = Path(dest)
    dest.mkdir(parents=True, exist_ok=True)
    for key, s in SCHEMES.items():
        (dest / f"{key}.colors").write_text(build(key, s))
    print("colour schemes written to", dest)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build/color-schemes")
