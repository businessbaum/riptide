#!/usr/bin/env python3
"""The emoji and symbols for "Emoji & Symbole" (⌃⌘Space), as JSON:
[{"e": "😀", "n": "grinsendes Gesicht", "k": "grinning face …", "g": "Smileys"}, …].

Names in German from python-emoji (the Unicode CLDR names); without it the English
Unicode names. Skin tone variants are left out (the base emoji stays), like the first
page of the macOS picker. Symbols (⌘ ⇧ → € ° …) come with German names from here.
Written once to ~/.cache/riptide/emoji.json; the picker reads that.
"""

import json
import sys
import unicodedata
from pathlib import Path

OUT = Path.home() / ".cache/riptide/emoji.json"
SKIN = {chr(c) for c in range(0x1F3FB, 0x1F400)}

SYMBOLS = [
    ("⌘", "Befehlstaste Command"), ("⌥", "Wahltaste Option Alt"), ("⌃", "Control Steuerung"), ("⇧", "Umschalttaste Shift"),
    ("⏎", "Zeilenschalter Return Enter"), ("⌫", "Rückschritt Löschen Backspace"), ("⎋", "Escape"), ("⇥", "Tabulator Tab"),
    ("→", "Pfeil rechts"), ("←", "Pfeil links"), ("↑", "Pfeil hoch"), ("↓", "Pfeil runter"), ("↔", "Doppelpfeil"),
    ("⇒", "Doppelpfeil rechts folgt"), ("•", "Aufzählungspunkt"), ("…", "Auslassungspunkte"), ("–", "Halbgeviertstrich Gedankenstrich"),
    ("—", "Geviertstrich"), ("„", "Anführungszeichen unten"), ("“", "Anführungszeichen oben"), ("«", "Guillemet links"),
    ("»", "Guillemet rechts"), ("©", "Copyright"), ("®", "eingetragene Marke"), ("™", "Trademark Marke"), ("€", "Euro"),
    ("£", "Pfund"), ("$", "Dollar"), ("¥", "Yen"), ("°", "Grad"), ("±", "plus minus"), ("×", "mal multiplizieren"),
    ("÷", "geteilt dividieren"), ("≈", "ungefähr gleich"), ("≠", "ungleich"), ("≤", "kleiner gleich"), ("≥", "größer gleich"),
    ("∞", "unendlich"), ("√", "Wurzel"), ("∑", "Summe"), ("π", "Pi"), ("µ", "Mikro"), ("Ω", "Ohm Omega"), ("∆", "Delta"),
    ("§", "Paragraf"), ("¶", "Absatz"), ("†", "Kreuz gestorben"), ("✓", "Haken erledigt"), ("✗", "Kreuz falsch"),
    ("★", "Stern"), ("☆", "Stern leer"), ("♥", "Herz"), ("½", "ein halb"), ("¼", "ein viertel"), ("²", "hoch zwei"),
    ("³", "hoch drei"), ("‰", "Promille"), ("ß", "Eszett"), ("ẞ", "großes Eszett"),
]


def clean(name):
    return name.strip(":").replace("_", " ")


def from_emoji_package():
    import emoji  # python-emoji
    found = []
    for e, data in emoji.EMOJI_DATA.items():
        if data.get("status") != emoji.STATUS["fully_qualified"] or SKIN & set(e):
            continue
        en = clean(data.get("en", ""))
        de = clean(data.get("de", "")) or en
        found.append({"e": e, "n": de, "k": " ".join([en] + [clean(a) for a in data.get("alias", [])])})
    return found


def from_unicode():
    found = []
    for start, end in ((0x1F600, 0x1F64F), (0x1F300, 0x1F5FF), (0x1F680, 0x1F6FF), (0x1F900, 0x1F9FF),
                       (0x1FA70, 0x1FAFF), (0x2600, 0x26FF), (0x2700, 0x27BF)):
        for c in range(start, end + 1):
            ch = chr(c)
            name = unicodedata.name(ch, "")
            if name and not (0x1F3FB <= c <= 0x1F3FF):
                found.append({"e": ch, "n": name.lower(), "k": name.lower()})
    return found


def main():
    try:
        items = from_emoji_package()
    except ImportError:
        items = from_unicode()
    items += [{"e": s, "n": n, "k": n.lower(), "g": "Symbole"} for s, n in SYMBOLS]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(items, ensure_ascii=False))
    if "--print" in sys.argv:
        print(len(items))


if __name__ == "__main__":
    main()
