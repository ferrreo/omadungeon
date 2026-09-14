"""Item icons: assets/sprites/items/weapons.png (20 cells) and armor.png (6 cells), 16x16.

Weapons: rusty_sword, longsword, axe, spear, dagger, shortbow, crossbow, wand, staff,
         throwing_knives, golden_cane, fists, greatsword, executioner_axe, glaive, stiletto,
         longbow, archmage_staff, runed_staff, chakrams

Every shipped weapon gets a cell of its own. The eight after `fists` were added because their
families shared a cell with a cheaper sibling - a greatsword drew the longsword, an
executioner's axe the axe, all three staves the same staff - so the inventory, the chest card
and the floor pickup all said "you already have this".
Armor:   leather_jerkin, shadow_weave, chain_mail, scale_hauberk, iron_plate, adamant_plate
         — this is the cell order the item resources already point at
         (``data/items/<id>.tres`` sets ``region = Rect2(cell * 16, 0, 16, 16)``), so the
         tuple below must stay in sync with them.
"""
from __future__ import annotations

import json
import pathlib

from toolkit import OUTLINE, WHITE, Canvas, Sheet, hex_color

T = 16
WEAPONS = (
    "rusty_sword", "longsword", "axe", "spear", "dagger", "shortbow",
    "crossbow", "wand", "staff", "throwing_knives", "golden_cane", "fists",
    "greatsword", "executioner_axe", "glaive", "stiletto", "longbow",
    "archmage_staff", "runed_staff", "chakrams",
)
ARMOR = (
    "leather_jerkin", "shadow_weave", "chain_mail", "scale_hauberk", "iron_plate",
    "adamant_plate",
)

STEEL = hex_color("#c8ccd8")
STEEL_L = hex_color("#f0f4ff")
STEEL_D = hex_color("#7c8298")
RUST = hex_color("#9a6a4a")
RUST_D = hex_color("#6a4a30")
WOOD = hex_color("#8b5a2b")
WOOD_D = hex_color("#5a3a1a")
GOLD = hex_color("#f2c94c")
GOLD_D = hex_color("#b58b1e")
GOLD_L = hex_color("#fff0a0")
LEATHER = hex_color("#a0642e")
LEATHER_D = hex_color("#6a4020")
ARCANE = hex_color("#8a5ae8")
ARCANE_L = hex_color("#e0d0ff")
RUNE = hex_color("#7ef07e")
RUNE_D = hex_color("#3fa03f")
INK = hex_color("#2a2a32")
STRING = hex_color("#e8d0a0")


def _blade(c: Canvas, x0: int, y0: int, x1: int, y1: int, light: tuple, mid: tuple, dark: tuple) -> None:
    """A diagonal blade drawn as three parallel lines from (x0,y0) -> (x1,y1)."""
    c.line(x0, y0, x1, y1, mid)
    c.line(x0 - 1, y0, x1 - 1, y1, light)
    c.line(x0 + 1, y0, x1 + 1, y1, dark)


def weapon(name: str) -> Canvas:
    c = Canvas(T, T)
    if name == "rusty_sword":
        _blade(c, 12, 2, 6, 8, STEEL, STEEL_D, RUST_D)
        for px, py in ((10, 5), (8, 7), (11, 4), (7, 8)):
            c.set(px, py, RUST)
        c.set(9, 5, (0, 0, 0, 0))  # notch out of the edge
        c.line(3, 9, 7, 5, RUST_D)  # crossguard, perpendicular to the blade
        c.line(4, 10, 8, 6, RUST)
        c.line(3, 11, 5, 13, WOOD_D)  # grip
        c.line(4, 10, 6, 12, WOOD)
        c.rect(4, 12, 3, 3, WOOD_D)
        c.set(5, 13, RUST)
        return c.outline()
    if name == "longsword":
        _blade(c, 12, 1, 5, 9, STEEL_L, STEEL, STEEL_D)
        c.set(12, 1, WHITE)
        c.line(3, 8, 7, 12, GOLD_D)
        c.line(2, 11, 6, 7, GOLD)
        c.rect(1, 12, 3, 3, WOOD_D)
        c.set(2, 13, WOOD)
        return c.outline()
    if name == "axe":
        c.line(2, 14, 10, 4, WOOD)
        c.line(3, 14, 11, 4, WOOD_D)
        c.rect(1, 12, 3, 3, WOOD_D)
        for y in range(2, 11):
            reach = int(4.5 - 4.5 * ((y - 6.0) / 4.5) ** 2)
            for x in range(9, 10 + reach):
                c.set(x, y, STEEL)
            c.set(9 + reach, y, STEEL_L)
            if reach > 1:
                c.set(9 + reach - 1, y, STEEL_L)
        c.vline(9, 3, 9, STEEL_D)
        c.vline(10, 5, 7, STEEL_D)
        return c.outline()
    if name == "spear":
        c.line(2, 14, 11, 5, WOOD)
        c.line(3, 14, 12, 5, WOOD_D)
        c.line(11, 5, 14, 2, STEEL)
        c.line(10, 5, 13, 2, STEEL_L)
        c.line(12, 6, 14, 4, STEEL_D)
        c.set(14, 2, WHITE)
        c.rect(9, 6, 2, 2, hex_color("#e04040"))
        return c.outline()
    if name == "dagger":
        _blade(c, 11, 3, 7, 8, STEEL_L, STEEL, STEEL_D)
        c.set(11, 3, WHITE)
        c.line(5, 7, 8, 10, STEEL_D)
        c.line(4, 10, 6, 8, WOOD_D)
        c.rect(3, 11, 2, 2, WOOD)
        return c.outline()
    if name == "shortbow":
        for y in range(2, 14):
            x = 6 + int(3.0 * (1 - ((y - 7.5) / 5.5) ** 2))
            c.set(x, y, WOOD)
            c.set(x - 1, y, WOOD_D)
        c.line(5, 2, 5, 13, hex_color("#e8d0a0"))
        c.rect(5, 2, 1, 1, WOOD_D)
        c.rect(5, 13, 1, 1, WOOD_D)
        c.hline(2, 12, 8, WOOD_D)
        c.rect(12, 7, 3, 3, STEEL)
        c.set(14, 8, WHITE)
        c.rect(1, 7, 2, 1, hex_color("#e04040"))
        c.rect(1, 9, 2, 1, hex_color("#e04040"))
        return c.outline()
    if name == "crossbow":
        c.rect(2, 7, 11, 3, WOOD)
        c.hline(3, 12, 8, WOOD_D)
        c.rect(1, 9, 4, 3, WOOD_D)
        c.rect(6, 2, 2, 12, STEEL)
        c.vline(7, 3, 12, STEEL_D)
        c.line(7, 2, 12, 8, hex_color("#e8d0a0"))
        c.line(7, 13, 12, 8, hex_color("#e8d0a0"))
        c.rect(12, 7, 3, 3, STEEL_L)
        c.set(14, 8, WHITE)
        return c.outline()
    if name == "wand":
        c.line(3, 13, 10, 6, WOOD)
        c.line(4, 13, 11, 6, WOOD_D)
        c.circle(11.5, 4.5, 2, hex_color("#8a5ae8"))
        c.set(11, 4, hex_color("#e0d0ff"))
        c.set(13, 2, hex_color("#c0a0ff"))
        c.set(9, 1, hex_color("#c0a0ff"))
        c.set(14, 6, hex_color("#c0a0ff"))
        return c.outline()
    if name == "staff":
        c.line(3, 14, 9, 6, WOOD)
        c.line(4, 14, 10, 6, WOOD_D)
        c.rect(9, 2, 4, 4, hex_color("#4ee0ff"))
        c.rect(10, 3, 2, 2, hex_color("#d0f8ff"))
        c.set(8, 3, WOOD_D)
        c.set(13, 6, WOOD_D)
        c.set(8, 6, WOOD_D)
        c.set(13, 2, WOOD_D)
        c.set(11, 1, WHITE)
        return c.outline()
    if name == "throwing_knives":
        for x0, tip in ((2, 2), (7, 4), (12, 3)):  # three blades stood side by side
            c.vline(x0, tip + 1, tip + 7, STEEL)
            c.vline(x0 - 1, tip + 2, tip + 7, STEEL_D)
            c.set(x0, tip, STEEL_L)
            c.set(x0, tip + 1, STEEL_L)
            c.hline(x0 - 1, x0 + 1, tip + 8, STEEL_D)
            c.vline(x0, tip + 9, tip + 11, WOOD_D)
            c.set(x0 - 1, tip + 10, WOOD)
        return c.outline()
    if name == "golden_cane":
        c.line(6, 14, 11, 5, GOLD)
        c.line(7, 14, 12, 5, GOLD_D)
        c.rect(8, 2, 5, 3, GOLD)
        c.rect(9, 3, 3, 1, GOLD_L)
        c.set(12, 4, GOLD_D)
        c.set(13, 3, GOLD_D)
        c.rect(5, 13, 3, 2, STEEL_D)
        c.set(9, 2, WHITE)
        return c.outline()
    if name == "greatsword":
        # Two-handed: a broad blade straight up the cell with a long bar guard, where the
        # longsword is a slim diagonal. Shape and stance differ, not just size.
        for y in range(2, 10):
            if y == 2:
                c.rect(7, y, 2, 1, STEEL_L)
            else:
                c.rect(6, y, 4, 1, STEEL)
        c.vline(6, 3, 9, STEEL_L)
        c.vline(9, 3, 9, STEEL_D)
        c.set(7, 2, WHITE)
        c.hline(2, 13, 10, GOLD_D)
        c.hline(3, 12, 11, GOLD)
        c.rect(7, 12, 2, 2, WOOD_D)
        c.rect(6, 14, 4, 1, GOLD)
        return c.outline()
    if name == "executioner_axe":
        # One enormous crescent bit on an upright haft, with a spike on the back. The axe cell
        # is a small single bit on a diagonal handle, so the two never read as the same tool.
        c.vline(5, 1, 14, WOOD)
        c.vline(6, 1, 14, WOOD_D)
        for y in range(2, 13):
            t = (y - 7.0) / 5.5
            outer = int(8.0 * (1.0 - t * t))
            inner = int(2.0 * (1.0 - t * t))
            if outer - inner < 1:
                continue
            for x in range(7 + inner, 7 + outer):
                c.set(x, y, STEEL)
            c.set(7 + outer - 1, y, STEEL_L)
            c.set(7 + inner, y, STEEL_D)
        c.hline(2, 4, 6, STEEL_D)
        c.set(1, 6, STEEL_L)
        c.rect(4, 13, 3, 2, STEEL_D)
        return c.outline()
    if name == "glaive":
        # Polearm: a long haft with a curved single-edged blade, where the spear is a straight
        # point on a shorter shaft.
        c.line(1, 14, 8, 7, WOOD)
        c.line(2, 14, 9, 7, WOOD_D)
        c.rect(7, 6, 3, 2, GOLD_D)
        c.line(9, 5, 14, 1, STEEL_L)
        c.line(9, 6, 14, 2, STEEL)
        c.line(9, 7, 13, 3, STEEL)
        c.line(9, 8, 12, 5, STEEL_D)
        c.set(14, 1, WHITE)
        return c.outline()
    if name == "stiletto":
        # A needle: one-pixel blade, no crossguard, a black wire-wound grip. The dagger is a
        # wide leaf blade on wood.
        c.line(13, 1, 6, 8, STEEL_L)
        c.line(12, 1, 5, 8, STEEL)
        c.set(13, 1, WHITE)
        c.set(5, 8, STEEL_D)
        c.set(6, 8, STEEL_D)
        c.line(4, 9, 6, 11, INK)
        c.line(3, 10, 5, 12, INK)
        c.set(4, 10, hex_color("#6a6a76"))
        c.rect(2, 12, 3, 2, STEEL_D)
        return c.outline()
    if name == "longbow":
        # Full-height stave, straight string, leather-wrapped grip - and no nocked arrow, which
        # is what the shortbow cell carries.
        for y in range(1, 15):
            x = 5 + int(3.4 * (1 - ((y - 8.0) / 7.0) ** 2))
            c.set(x, y, WOOD)
            c.set(x - 1, y, WOOD_D)
        c.vline(5, 1, 14, STRING)
        c.rect(6, 7, 3, 3, LEATHER)
        c.hline(6, 8, 8, LEATHER_D)
        c.set(5, 1, WOOD_D)
        c.set(5, 14, WOOD_D)
        return c.outline()
    if name == "archmage_staff":
        # A floating arcane ring above the shaft; the plain staff carries a solid cyan gem.
        c.line(2, 14, 9, 7, WOOD)
        c.line(3, 14, 10, 7, WOOD_D)
        c.circle(11, 4, 3.4, ARCANE, filled=False)
        c.circle(11, 4, 1.4, ARCANE_L)
        c.set(11, 1, WHITE)
        c.set(7, 2, ARCANE_L)
        c.set(14, 8, ARCANE_L)
        return c.outline()
    if name == "runed_staff":
        # Carved runes glowing down a dark shaft, capped by a knot instead of a gem.
        c.line(2, 14, 10, 4, WOOD_D)
        c.line(3, 14, 11, 4, WOOD)
        for x, y in ((4, 12), (6, 9), (8, 7)):
            c.set(x, y, RUNE)
            c.set(x + 1, y - 1, RUNE_D)
        c.rect(9, 1, 4, 4, RUNE_D)
        c.rect(10, 2, 2, 2, RUNE)
        c.set(10, 2, hex_color("#d0ffd0"))
        return c.outline()
    if name == "chakrams":
        # Two thrown rings; the knives cell is three straight blades stood side by side.
        c.circle(5, 5, 3.6, STEEL, filled=False)
        c.circle(5, 5, 1.8, STEEL_D, filled=False)
        c.circle(10, 10, 4.0, STEEL_L, filled=False)
        c.circle(10, 10, 2.2, STEEL_D, filled=False)
        c.set(5, 1, WHITE)
        c.set(14, 10, WHITE)
        return c.outline()
    # fists
    skin = hex_color("#f0c8a0")
    skin_d = hex_color("#c88c64")
    skin_l = hex_color("#ffe2c4")
    wrap = hex_color("#e04040")
    wrap_d = hex_color("#a02020")
    for x0, y0 in ((1, 7), (8, 3)):
        c.rect(x0 + 1, y0, 5, 6, skin)  # hand back
        c.rect(x0, y0 + 1, 1, 4, skin_d)  # thumb side
        c.hline(x0 + 1, x0 + 5, y0, skin_l)
        for fy in (y0 + 1, y0 + 3):  # knuckle grooves between fingers
            c.hline(x0 + 2, x0 + 5, fy, skin_d)
        c.set(x0 + 6, y0 + 2, skin)
        c.set(x0 + 6, y0 + 3, skin_d)
        c.rect(x0 + 1, y0 + 6, 5, 2, wrap)  # wrist wrap
        c.hline(x0 + 1, x0 + 5, y0 + 7, wrap_d)
        c.set(x0 + 3, y0 + 6, wrap_d)
    return c.outline()


def armor(name: str) -> Canvas:
    """One 16x16 armour icon. ``name`` is the item id, not a generic material."""
    c = Canvas(T, T)
    if name == "leather_jerkin":
        c.rect(5, 2, 6, 3, LEATHER)
        c.rect(3, 4, 10, 4, LEATHER)
        c.rect(4, 8, 8, 5, LEATHER)
        c.rect(6, 3, 4, 1, LEATHER_D)
        c.hline(4, 11, 9, LEATHER_D)
        c.rect(4, 6, 2, 1, LEATHER_D)
        c.rect(10, 6, 2, 1, LEATHER_D)
        c.set(7, 10, STEEL_D)
        c.set(9, 10, STEEL_D)
        c.rect(5, 12, 6, 1, LEATHER_D)
        c.set(4, 5, hex_color("#c98a4a"))
        return c.outline()
    if name == "shadow_weave":
        col, dark = hex_color("#3a2f52"), hex_color("#211a30")
        glow = hex_color("#8a6ce0")
        c.rect(5, 1, 6, 4, col)
        c.rect(4, 5, 8, 4, col)
        c.rect(3, 9, 10, 5, col)
        c.rect(6, 2, 4, 2, dark)
        c.vline(8, 5, 13, dark)
        c.set(6, 7, glow)
        c.set(10, 10, glow)
        c.set(4, 11, glow)
        c.hline(3, 12, 13, dark)
        # ragged hem: the weave frays into shadow
        for x in (3, 6, 9, 12):
            c.set(x, 13, hex_color("#000000", 0))
        return c.outline()
    if name == "chain_mail":
        ring_d = hex_color("#404858")
        ring_l = hex_color("#9aa0b4")
        c.rect(5, 2, 6, 3, STEEL_D)
        c.rect(3, 4, 10, 4, STEEL_D)
        c.rect(4, 8, 8, 5, STEEL_D)
        for y in range(2, 13):
            for x in range(3, 13):
                if not c.get(x, y)[3]:
                    continue
                if y % 2 == 0 and x % 2 == 0:
                    c.set(x, y, ring_l)
                elif y % 2 == 1 and x % 2 == 1:
                    c.set(x, y, ring_d)
        c.rect(6, 2, 4, 2, ring_d)  # collar
        c.hline(4, 11, 8, ring_d)  # belt line
        c.hline(4, 11, 7, ring_l)
        c.set(3, 5, ring_l)
        c.set(12, 5, ring_d)
        return c.outline()
    if name == "scale_hauberk":
        scale, scale_d = hex_color("#7f9a5a"), hex_color("#4c6234")
        scale_l = hex_color("#b6cf86")
        c.rect(5, 2, 6, 3, scale)
        c.rect(3, 4, 10, 4, scale)
        c.rect(4, 8, 8, 5, scale)
        # overlapping scales: staggered 2 px arcs, lit on top, shadowed underneath
        for y in range(4, 13, 2):
            off = 0 if (y // 2) % 2 == 0 else 1
            for x in range(3 + off, 13, 2):
                if not c.get(x, y)[3]:
                    continue
                c.set(x, y, scale_l)
                if c.get(x, y + 1)[3]:
                    c.set(x, y + 1, scale_d)
        c.rect(6, 2, 4, 2, scale_d)
        c.hline(4, 11, 13, scale_d)
        return c.outline()
    if name == "iron_plate":
        c.rect(5, 2, 6, 3, STEEL)
        c.rect(2, 4, 12, 4, STEEL)
        c.rect(4, 8, 8, 5, STEEL)
        c.rect(6, 3, 4, 1, STEEL_D)
        c.rect(2, 4, 3, 3, STEEL_L)  # pauldrons
        c.rect(11, 4, 3, 3, STEEL_L)
        c.vline(8, 5, 12, STEEL_D)
        c.hline(5, 11, 9, STEEL_D)
        c.set(5, 5, WHITE)
        c.rect(7, 11, 3, 1, GOLD)
        return c.outline()
    # adamant_plate: the heavy end of the ramp — dark violet steel with a gold sunburst
    dark = hex_color("#4a3f6a")
    mid = hex_color("#6b5c94")
    light = hex_color("#a695d8")
    c.rect(5, 1, 6, 4, mid)
    c.rect(1, 4, 14, 4, mid)
    c.rect(3, 8, 10, 6, mid)
    c.rect(6, 2, 4, 1, dark)
    c.rect(1, 4, 3, 3, light)  # pauldrons
    c.rect(12, 4, 3, 3, light)
    c.vline(8, 5, 13, dark)
    c.hline(4, 11, 9, dark)
    c.rect(7, 6, 3, 3, GOLD)
    c.set(8, 7, GOLD_L)
    c.set(4, 11, light)
    c.set(11, 11, dark)
    c.hline(4, 11, 13, dark)
    return c.outline()


def generate(root: pathlib.Path) -> list[pathlib.Path]:
    items = root / "assets" / "sprites" / "items"
    # Pin the cell order for the gdUnit test: data/items/<id>.tres already fixes which
    # cell each item points at, so the drawing order must never drift from these names.
    cells = root / "tools" / "art" / "item_cells.json"
    cells.write_text(json.dumps({"weapons": list(WEAPONS), "armor": list(ARMOR)}, indent=2) + "\n")
    w = Sheet(T, T, len(WEAPONS), 1)
    w.put_row(0, [weapon(n) for n in WEAPONS])
    a = Sheet(T, T, len(ARMOR), 1)
    a.put_row(0, [armor(n) for n in ARMOR])
    w.save(items / "weapons.png")
    a.save(items / "armor.png")
    return [items / "weapons.png", items / "armor.png"]
