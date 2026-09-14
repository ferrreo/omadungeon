"""UI sprites: ability icons, input glyphs, HUD icons, cursor and the logo wordmark.

* assets/sprites/ui/ability_icons.png  64 cells 16x16 (ABILITY_ICONS then WEAPON_SKILL_ICONS;
                                       spare cells blank)
* assets/sprites/ui/glyphs.png         16 cells 16x16 (GLYPHS order)
* assets/sprites/ui/icons.png          16 cells 16x16 (ICONS order)
* assets/sprites/ui/cursor.png         16x16 crosshair (hotspot 8,8)
* assets/sprites/logo.png              OMADUNGEON wordmark, ~200x40
"""
from __future__ import annotations

import pathlib

from props import STAT_ORB_COLORS, coin, heart, projectile
from toolkit import OUTLINE, WHITE, Canvas, Color, Sheet, hex_color, pixel_font_text, shade

T = 16
# Must stay in the same order as AbilityRegistry.ICON_ORDER: the registry slices this sheet
# by index, so appending here and there is the only safe way to add an ability icon.
ABILITY_ICONS = (
    "fireball", "frost_nova", "shadowstep", "whirlwind", "turret", "warcry", "rm_rf", "reboot",
    "bulwark", "volley", "chain_lightning", "hostile_takeover", "contract", "thorns", "glass_cannon",
    "vampiric", "tiling_wm", "dotfiles", "lucky_coin", "ricochet", "adrenaline", "heavy_hands",
    "hotkey", "second_wind", "sure_footed", "overflow", "buyout", "curse_1", "curse_2", "curse_3",
    "kill_9", "fork_bomb", "smoke_bomb", "stack_smash", "siphon", "sudo",
    "close_quarters", "pipeline", "rootkit", "cron_job", "firewall", "bit_shift", "man_page",
    "overclock", "verbose_logging", "kernel_headers", "hardlink", "undervolt",
)
## Weapon skills live on the same sheet, in the cells after the abilities, because they sit
## next to the actives on the HUD and the pause page: a skill that borrows an ability's cell is
## a lunge that shows the Shadowstep icon. `data/items/skills/<id>.tres` pins each one by
## `region = Rect2(cell * 16, 0, 16, 16)`, with `cell = len(ABILITY_ICONS) + index` here.
WEAPON_SKILL_ICONS = (
    "skill_lunge", "skill_cleave", "skill_sweep", "skill_barrier", "skill_bribe",
    "skill_rain", "skill_fan_of_knives",
)
ABILITY_SHEET_CELLS = 64
GLYPHS = (
    "a", "b", "x", "y", "lb", "rb", "lt", "rt", "start", "select", "lstick", "rstick", "dpad",
    "keycap", "mouse_left", "mouse_right",
)
ICONS = (
    "heart", "potion", "gold", "stairs", "die",
    "vitality", "might", "precision", "arcana", "swiftness", "fortune",
    "rarity_common", "rarity_rare", "rarity_epic", "rarity_legendary", "lock",
)

FIRE = hex_color("#ff6020")
FIRE_L = hex_color("#ffd040")
ICE = hex_color("#60d8ff")
ICE_L = hex_color("#d0f8ff")
ARCANE = hex_color("#9a5ae8")
ARCANE_L = hex_color("#d8c0ff")
GOLD = hex_color("#f2c94c")
GOLD_L = hex_color("#fff0a0")
GREEN = hex_color("#40d070")
STEEL = hex_color("#c8ccd8")
STEEL_D = hex_color("#7c8298")
RED = hex_color("#e83030")
PINK = hex_color("#ff3fa8")
CYAN = hex_color("#40e0d0")
DARK = hex_color("#202030")
GOLD_D_UI = hex_color("#b58b1e")


def _plate(color: Color) -> Canvas:
    """Rounded icon backplate in a dark tint of the accent, with a 1px outline."""
    c = Canvas(T, T)
    bg = shade(color, 0.28)
    c.rect(1, 0, 14, 16, bg)
    c.rect(0, 1, 16, 14, bg)
    c.rect(1, 0, 14, 1, OUTLINE)
    c.rect(1, 15, 14, 1, OUTLINE)
    c.rect(0, 1, 1, 14, OUTLINE)
    c.rect(15, 1, 1, 14, OUTLINE)
    c.hline(2, 13, 1, shade(color, 0.5))
    return c


def ability_icon(name: str) -> Canvas:
    if name == "fireball":
        c = _plate(FIRE)
        c.circle(9, 8, 4, FIRE)
        c.circle(10, 8, 2, FIRE_L)
        c.rect(2, 7, 4, 3, FIRE)
        c.set(11, 8, WHITE)
    elif name == "frost_nova":
        c = _plate(ICE)
        for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
            c.line(8, 8, 8 + dx * 6, 8 + dy * 6, ICE)
        for dx, dy in ((1, -1), (1, 1), (-1, 1), (-1, -1)):
            c.line(8, 8, 8 + dx * 4, 8 + dy * 4, ICE_L)
        c.circle(8, 8, 1.5, WHITE)
    elif name == "shadowstep":
        c = _plate(ARCANE)
        c.ellipse(5, 8, 3, 5, hex_color("#3a2a5a"))
        c.ellipse(10, 8, 3, 5, ARCANE)
        c.set(9, 6, ARCANE_L)
        c.set(9, 9, ARCANE_L)
        c.hline(3, 5, 12, ARCANE_L)
    elif name == "whirlwind":
        c = _plate(STEEL)
        c.circle(8, 8, 5.5, STEEL, filled=False)
        c.circle(8, 8, 3, STEEL_D, filled=False)
        c.line(11, 3, 14, 2, WHITE)
        c.line(5, 13, 2, 14, WHITE)
        c.set(8, 8, WHITE)
    elif name == "turret":
        c = _plate(CYAN)
        c.rect(4, 9, 8, 4, STEEL)
        c.rect(6, 6, 4, 3, STEEL_D)
        c.rect(9, 5, 5, 2, STEEL)
        c.set(14, 5, RED)
        c.rect(3, 13, 10, 1, STEEL_D)
        c.set(7, 7, CYAN)
    elif name == "warcry":
        c = _plate(RED)
        c.circle(7, 8, 3, hex_color("#f0c8a0"))
        c.rect(7, 8, 2, 2, DARK)
        c.line(11, 5, 14, 3, RED)
        c.line(12, 8, 15, 8, RED)
        c.line(11, 11, 14, 13, RED)
    elif name == "rm_rf":
        c = _plate(RED)
        c.rect(2, 5, 12, 3, STEEL_D)  # a shredder eating a file
        c.rect(2, 5, 12, 3, OUTLINE, filled=False)
        c.rect(5, 1, 6, 4, hex_color("#e8e4d8"))
        c.rect(5, 1, 6, 4, OUTLINE, filled=False)
        for i, x in enumerate((3, 6, 9, 12)):
            c.vline(x, 8, 11 + (i % 2) * 3, RED)
            c.set(x, 8, hex_color("#ff9090"))
    elif name == "reboot":
        c = _plate(GREEN)
        c.circle(8, 8, 4.5, GREEN, filled=False)
        c.rect(7, 2, 2, 5, shade(GREEN, 0.28))
        c.vline(8, 3, 7, GREEN)
        c.set(11, 4, WHITE)
    elif name == "bulwark":
        c = _plate(hex_color("#3a6fd8"))
        c.rect(4, 3, 8, 7, STEEL)
        for i in range(4):
            c.hline(4 + i, 11 - i, 10 + i, STEEL)
        c.rect(6, 4, 4, 6, hex_color("#3a6fd8"))
        c.set(5, 4, WHITE)
    elif name == "volley":
        c = _plate(GREEN)
        for i, (x1, y1) in enumerate(((3, 3), (8, 2), (13, 3))):
            c.line(8, 13, x1, y1, hex_color("#8b5a2b"))
            c.set(x1, y1, STEEL)
    elif name == "chain_lightning":
        c = _plate(hex_color("#60c0ff"))
        c.line(3, 3, 7, 7, hex_color("#fff0a0"))
        c.line(7, 7, 5, 9, hex_color("#fff0a0"))
        c.line(5, 9, 12, 13, hex_color("#fff0a0"))
        c.set(3, 3, WHITE)
        c.set(12, 13, WHITE)
        c.circle(12, 4, 1.5, hex_color("#60c0ff"))
    elif name == "hostile_takeover":
        c = _plate(GOLD)
        c.rect(3, 6, 5, 7, hex_color("#303040"))
        c.rect(9, 6, 4, 7, RED)
        c.rect(9, 6, 4, 7, GOLD, filled=False)
        c.rect(4, 3, 3, 3, hex_color("#f0c8a0"))
        c.rect(10, 3, 2, 3, hex_color("#f0c8a0"))
        c.hline(8, 9, 9, GOLD)
    elif name == "contract":
        c = _plate(GOLD)
        c.rect(4, 2, 8, 12, hex_color("#f0ead0"))
        c.hline(5, 10, 4, STEEL_D)
        c.hline(5, 10, 6, STEEL_D)
        c.hline(5, 8, 8, STEEL_D)
        c.line(5, 12, 10, 10, hex_color("#3060d0"))
        c.rect(10, 11, 2, 2, RED)
    elif name == "thorns":
        c = _plate(GREEN)
        c.line(2, 13, 13, 2, hex_color("#2c6a2c"))  # a barbed vine, not another starburst
        c.line(3, 13, 13, 3, GREEN)
        for x, y, dx, dy in ((5, 10, -2, -1), (8, 7, 2, 1), (10, 5, -1, -2), (6, 9, 1, 2)):
            c.line(x, y, x + dx * 2, y + dy * 2, GREEN)
            c.set(x + dx * 2, y + dy * 2, WHITE)
        c.set(13, 2, WHITE)
    elif name == "glass_cannon":
        c = _plate(ICE)
        for i in range(5):  # a gem about to break, not another barrel on a plate
            c.hline(7 - i, 8 + i, 3 + i, hex_color("#a8e8ff"))
        for i in range(6):
            c.hline(3 + i, 12 - i, 8 + i, hex_color("#a8e8ff"))
        c.line(8, 3, 6, 8, WHITE)
        c.line(6, 8, 9, 13, RED)
        c.line(6, 8, 3, 8, RED)
        c.set(5, 5, WHITE)
    elif name == "vampiric":
        c = _plate(RED)
        c.blit(heart().crop(0, 0, 16, 16).shift(0, -1), 0, 0)
        c.rect(6, 5, 1, 3, WHITE)
        c.rect(9, 5, 1, 3, WHITE)
        c.set(8, 13, RED)
        c.set(8, 14, hex_color("#a01c1c"))
    elif name == "tiling_wm":
        c = _plate(CYAN)
        c.rect(2, 2, 6, 12, hex_color("#1a3a4a"))
        c.rect(9, 2, 5, 5, hex_color("#1a3a4a"))
        c.rect(9, 8, 5, 6, hex_color("#1a3a4a"))
        for r in ((2, 2, 6, 12), (9, 2, 5, 5), (9, 8, 5, 6)):
            c.rect(*r, CYAN, filled=False)
    elif name == "dotfiles":
        c = _plate(hex_color("#d8d0b8"))
        c.rect(2, 5, 12, 9, hex_color("#e8c86a"))  # a folder, not another sheet of paper
        c.rect(2, 3, 6, 3, hex_color("#e8c86a"))
        c.rect(2, 3, 6, 3, hex_color("#8a6a20"), filled=False)
        c.rect(2, 5, 12, 9, hex_color("#8a6a20"), filled=False)
        c.hline(3, 12, 6, hex_color("#f6e2a6"))
        c.rect(6, 8, 4, 4, DARK)  # the leading dot
        c.set(6, 8, hex_color("#8a6a20"))
    elif name == "lucky_coin":
        c = _plate(GOLD)
        c.blit(coin(0), 0, 0)
        c.set(3, 3, GOLD_L)
        c.set(13, 3, GOLD_L)
    elif name == "ricochet":
        c = _plate(STEEL)
        c.line(2, 13, 8, 5, STEEL)
        c.line(8, 5, 13, 11, STEEL)
        c.set(8, 5, WHITE)
        c.set(13, 11, WHITE)
        c.hline(6, 10, 3, STEEL_D)
    elif name == "adrenaline":
        c = _plate(RED)
        c.line(2, 9, 5, 9, hex_color("#ff9090"))
        c.line(5, 9, 7, 4, hex_color("#ff9090"))
        c.line(7, 4, 9, 13, hex_color("#ff9090"))
        c.line(9, 13, 11, 8, hex_color("#ff9090"))
        c.line(11, 8, 14, 8, hex_color("#ff9090"))
        c.set(7, 4, WHITE)
    elif name == "heavy_hands":
        c = _plate(hex_color("#f08030"))
        c.rect(4, 5, 8, 7, hex_color("#f0c8a0"))
        c.rect(4, 7, 8, 1, hex_color("#c88c64"))
        c.rect(12, 6, 2, 3, hex_color("#f0c8a0"))
        c.rect(3, 12, 10, 2, hex_color("#f08030"))
        c.set(2, 3, WHITE)
        c.set(13, 2, WHITE)
    elif name == "hotkey":
        c = _plate(hex_color("#6a8ac0"))
        c.rect(3, 4, 10, 9, hex_color("#e8ecf4"))
        c.rect(3, 12, 10, 2, hex_color("#a0a8b8"))
        c.blit(pixel_font_text("Q", DARK), 6, 6)
    elif name == "second_wind":
        c = _plate(GREEN)
        c.rect(2, 12, 12, 2, shade(GREEN, 0.45))  # getting back up, not another heart
        c.rect(2, 12, 12, 2, OUTLINE, filled=False)
        for i in range(5):  # arrowhead
            c.hline(8 - i, 8 + i, 3 + i, hex_color("#a8ffc8"))
        c.rect(6, 8, 5, 4, hex_color("#a8ffc8"))  # shaft
        c.rect(6, 8, 5, 4, OUTLINE, filled=False)
        c.vline(8, 2, 11, WHITE)
    elif name == "sure_footed":
        c = _plate(GREEN)
        c.rect(4, 4, 4, 8, hex_color("#8b5a2b"))
        c.rect(4, 11, 8, 3, hex_color("#5a3a1a"))
        c.set(9, 5, GREEN)
        c.set(11, 4, GREEN)
        c.set(10, 7, GREEN)
        c.set(13, 7, GREEN)
    elif name == "overflow":
        c = _plate(ARCANE)
        c.rect(4, 6, 8, 8, hex_color("#3a2a5a"))
        c.rect(4, 6, 8, 8, ARCANE, filled=False)
        c.rect(5, 9, 6, 4, ARCANE)
        c.line(6, 5, 5, 2, ARCANE_L)
        c.line(9, 4, 10, 1, ARCANE_L)
        c.set(12, 4, ARCANE_L)
    elif name == "buyout":
        c = _plate(GOLD)
        c.rect(3, 5, 10, 8, hex_color("#8b5a2b"))
        c.rect(3, 5, 10, 8, hex_color("#5a3a1a"), filled=False)
        c.rect(3, 8, 10, 1, GOLD)
        c.rect(7, 7, 2, 3, GOLD)
        c.set(12, 3, GOLD_L)
        c.set(14, 4, GOLD_L)
    else:
        c = _extra_ability_icon(name)
    return c


def _extra_ability_icon(name: str) -> Canvas:
    """Icons added after the first content pass: the curse pacts and the expanded pool."""
    if name == "curse_1":
        c = _plate(RED)
        for i in range(11):  # a hazard triangle: the pacts warn before they take
            c.hline(8 - i // 2, 8 + i // 2, 2 + i, DARK if i else RED)
        for i in range(11):
            c.hline(8 - (i - 2) // 2, 8 + (i - 2) // 2, 2 + i, RED if i < 2 else DARK)
        c.rect(7, 6, 2, 4, RED)
        c.rect(7, 11, 2, 2, RED)
        c.set(8, 2, WHITE)
    elif name == "curse_2":
        c = _plate(ARCANE)
        c.circle(8, 9, 4, hex_color("#3a2a5a"))
        c.line(8, 2, 8, 5, ARCANE_L)
        c.line(5, 4, 6, 6, ARCANE)
        c.line(11, 4, 10, 6, ARCANE)
        c.set(7, 9, WHITE)
        c.set(10, 9, WHITE)
    elif name == "curse_3":
        c = _plate(STEEL_D)
        c.rect(4, 5, 8, 8, DARK)
        c.rect(4, 5, 8, 8, STEEL_D, filled=False)
        c.line(4, 5, 11, 12, STEEL)
        c.set(6, 3, STEEL)
    elif name == "kill_9":
        c = _plate(RED)
        c.circle(8, 8, 6, RED, filled=False)  # a kill signal's crosshair, not another word
        c.circle(8, 8, 4, hex_color("#ff9090"), filled=False)
        c.vline(8, 0, 3, RED)
        c.vline(8, 12, 15, RED)
        c.hline(0, 3, 8, RED)
        c.hline(12, 15, 8, RED)
        c.rect(7, 7, 2, 2, WHITE)
    elif name == "fork_bomb":
        c = _plate(ARCANE)
        c.rect(7, 1, 2, 2, WHITE)  # one process forking into two, then four
        c.line(8, 3, 4, 6, ARCANE_L)
        c.line(8, 3, 12, 6, ARCANE_L)
        for x in (4, 12):
            c.rect(x - 1, 6, 2, 2, ARCANE_L)
            c.line(x, 8, x - 2, 11, ARCANE)
            c.line(x, 8, x + 2, 11, ARCANE)
        for x in (2, 6, 10, 14):
            c.rect(x - 1, 11, 2, 2, ARCANE)
    elif name == "smoke_bomb":
        c = _plate(STEEL_D)
        c.circle(6, 9, 3.5, STEEL_D)
        c.circle(10, 7, 3, STEEL)
        c.circle(11, 11, 2.5, STEEL_D)
        c.set(4, 4, STEEL)
        c.set(13, 4, STEEL)
    elif name == "stack_smash":
        c = _plate(hex_color("#b07840"))
        c.rect(2, 10, 12, 3, hex_color("#6a4a28"))
        c.line(5, 10, 7, 5, STEEL_D)
        c.line(11, 10, 9, 5, STEEL_D)
        c.hline(4, 12, 4, STEEL)
        c.set(8, 12, WHITE)
    elif name == "siphon":
        c = _plate(GREEN)
        c.circle(4, 11, 2.5, GREEN)
        c.line(5, 10, 11, 4, hex_color("#8ef0b0"))
        c.circle(12, 4, 2.5, hex_color("#8ef0b0"))
        c.set(12, 4, WHITE)
    elif name == "sudo":
        c = _plate(GOLD)
        c.rect(3, 4, 10, 8, DARK)
        c.blit(pixel_font_text("SU", GOLD), 4, 5)
        c.hline(3, 12, 13, GOLD_L)
        c.set(13, 13, WHITE)
    elif name == "close_quarters":
        c = _plate(RED)
        c.rect(3, 6, 5, 5, STEEL)
        c.rect(9, 6, 4, 5, STEEL_D)
        c.line(8, 3, 8, 13, RED)
        c.set(8, 8, WHITE)
    elif name == "pipeline":
        c = _plate(hex_color("#ff8a3c"))
        c.rect(2, 7, 4, 3, hex_color("#ff8a3c"))
        c.rect(7, 7, 3, 3, hex_color("#ffb070"))
        c.rect(11, 7, 3, 3, GOLD_L)
        c.line(6, 8, 7, 8, WHITE)
        c.line(10, 8, 11, 8, WHITE)
    elif name == "rootkit":
        c = _plate(hex_color("#7a3ad8"))
        c.rect(5, 7, 6, 6, STEEL_D)
        c.circle(8, 6, 3, ARCANE)
        c.set(7, 6, WHITE)
        c.set(9, 6, WHITE)
        c.hline(4, 12, 13, ARCANE_L)
    elif name == "cron_job":
        c = _plate(GREEN)
        c.rect(2, 3, 12, 11, hex_color("#e8f4e8"))  # a calendar, not another green ring
        c.rect(2, 3, 12, 3, GREEN)
        c.rect(2, 3, 12, 11, OUTLINE, filled=False)
        c.vline(5, 1, 3, STEEL_D)
        c.vline(10, 1, 3, STEEL_D)
        for row in range(2):
            for col in range(4):
                c.set(4 + col * 3, 8 + row * 3, hex_color("#2c6a2c"))
        c.rect(9, 10, 3, 3, GREEN)
        c.set(10, 11, WHITE)
    elif name == "firewall":
        c = _plate(hex_color("#ff5a2a"))
        for row in range(3):
            y = 5 + row * 3
            offset = 0 if row % 2 == 0 else 3
            for x in range(-1, 4):
                c.rect(2 + offset + x * 5, y, 4, 2, hex_color("#b03a18"))
        c.hline(2, 13, 4, hex_color("#ff9a5a"))
    elif name == "bit_shift":
        c = _plate(CYAN)
        c.line(4, 8, 8, 4, CYAN)
        c.line(4, 8, 8, 12, CYAN)
        c.line(8, 8, 12, 4, hex_color("#a0fff0"))
        c.line(8, 8, 12, 12, hex_color("#a0fff0"))
        c.set(12, 8, WHITE)
    elif name == "man_page":
        c = _plate(hex_color("#c8ccd8"))
        c.rect(1, 4, 7, 9, hex_color("#e8e4d8"))  # an open book, not another single sheet
        c.rect(8, 4, 7, 9, hex_color("#e8e4d8"))
        c.rect(1, 4, 7, 9, STEEL_D, filled=False)
        c.rect(8, 4, 7, 9, STEEL_D, filled=False)
        c.vline(7, 2, 14, DARK)
        c.vline(8, 2, 14, DARK)
        c.hline(1, 6, 4, hex_color("#f8f6ee"))
        c.hline(9, 14, 4, hex_color("#f8f6ee"))
        for i in range(3):
            c.hline(3, 6, 7 + i * 2, STEEL_D)
            c.hline(9, 12, 7 + i * 2, STEEL_D)
        c.set(3, 6, ARCANE)
    elif name == "overclock":
        c = _plate(hex_color("#ffd040"))
        c.rect(4, 4, 8, 8, DARK)
        c.rect(4, 4, 8, 8, GOLD, filled=False)
        c.line(9, 5, 6, 8, GOLD_L)
        c.line(6, 8, 9, 8, GOLD_L)
        c.line(9, 8, 6, 11, GOLD_L)
        c.set(2, 8, GOLD)
        c.set(13, 8, GOLD)
    elif name == "verbose_logging":
        c = _plate(GOLD)
        c.rect(1, 2, 14, 12, DARK)  # a terminal window streaming lines
        c.rect(1, 2, 14, 3, STEEL_D)
        c.rect(1, 2, 14, 12, OUTLINE, filled=False)
        for i, w in enumerate((9, 5, 11, 7)):
            c.hline(3, 3 + w, 6 + i * 2, GOLD_L if i % 2 else GOLD)
        c.set(3, 3, RED)
        c.set(5, 3, GOLD_L)
    elif name == "kernel_headers":
        c = _plate(hex_color("#5ac8e8"))
        c.rect(5, 5, 6, 6, DARK)
        c.rect(5, 5, 6, 6, hex_color("#a0e8ff"), filled=False)
        for x in (3, 12):
            c.vline(x, 6, 9, hex_color("#5ac8e8"))
        for y in (3, 12):
            c.hline(6, 9, y, hex_color("#5ac8e8"))
        c.set(8, 8, WHITE)
    elif name == "hardlink":
        c = _plate(hex_color("#8ea0c0"))
        c.ellipse(5, 10, 4, 2.6, STEEL)  # two chain links, one flat, one upright
        c.ellipse(5, 10, 2.6, 1.2, shade(hex_color("#8ea0c0"), 0.28))
        c.ellipse(10, 6, 2.6, 4, STEEL)
        c.ellipse(10, 6, 1.2, 2.6, shade(hex_color("#8ea0c0"), 0.28))
        c.set(8, 8, WHITE)
        c.set(3, 10, WHITE)
    elif name == "undervolt":
        c = _plate(hex_color("#60d8ff"))
        c.rect(6, 1, 4, 9, hex_color("#e8f8ff"))  # a thermometer coming down
        c.circle(8, 12, 3, hex_color("#e8f8ff"))
        c.rect(6, 1, 4, 9, OUTLINE, filled=False)
        c.circle(8, 12, 3, OUTLINE, filled=False)
        c.rect(7, 6, 2, 6, ICE)
        c.circle(8, 12, 2, ICE)
        for y in (3, 5, 7):
            c.hline(10, 12, y, ICE_L)
    else:
        c = _plate(STEEL_D)
    return c


# ------------------------------------------------------------------------------- glyphs
def _button(letter: str, color: Color) -> Canvas:
    c = Canvas(T, T)
    c.circle(8, 8, 6.5, OUTLINE)
    c.circle(8, 8, 5.5, color)
    c.circle(8, 8, 4, shade(color, 0.85))
    c.set(5, 5, shade(color, 1.4))
    c.blit(pixel_font_text(letter, WHITE), 7, 6)
    return c


# Shoulder glyphs. The label is two characters of the 3x5 micro font, so it needs seven
# columns and five rows of *face* - body colour on all four sides of every stroke. The old
# bumper was a 12x6 bar: the label's bottom row landed on the bar's own bottom border and its
# right edge touched the right one, so the strokes fused with the outline and LB and RB read
# as one smear at the 480x270 internal resolution. They are the HUD's two ability prompts
# (`active_1` and `active_2` are LB and RB), which made them the two most-looked-at glyphs in
# the game. Both silhouettes are drawn as explicit pixel maps now, so the face around the
# label is a property of the picture rather than of the order the rectangles were stacked in.
BUMPER_ROWS = (
    "................",
    "................",
    "................",
    "...oooooooooo...",
    "..ohhhhhhhhhho..",
    ".obbbbbbbbbbbbo.",
    ".obbbbbbbbbbbbo.",
    ".obbbbbbbbbbbbo.",
    ".obbbbbbbbbbbbo.",
    ".obbbbbbbbbbbbo.",
    ".obbbbbbbbbbbbo.",
    ".obbbbbbbbbbbbo.",
    "..osssssssssso..",
    "...oooooooooo...",
    "................",
    "................",
)
TRIGGER_ROWS = (
    "................",
    "..oooooooooooo..",
    "..ohhhhhhhhhho..",
    "..obbbbbbbbbbo..",
    "..obbbbbbbbbbo..",
    "..obbbbbbbbbbo..",
    "..obbbbbbbbbbo..",
    "..obbbbbbbbbbo..",
    "..obbbbbbbbbbo..",
    "..obbbbbbbbbbo..",
    "..obbbbbbbbbbo..",
    "..osssssssssso..",
    "..oooooooooooo..",
    "...osssssssso...",
    "...oooooooooo...",
    "................",
)
BUMPER_PALETTE = {
    "o": OUTLINE,
    "b": hex_color("#4a4a58"),
    "h": hex_color("#7a7a88"),
    "s": hex_color("#31313d"),
}
## Top-left corner of the two-character label inside each silhouette. Both put the 7x5 block
## in the middle of the face with a pixel of body colour on every side.
BUMPER_LABEL = (5, 6)
TRIGGER_LABEL = (4, 4)


def _bumper(label: str, trigger: bool = False) -> Canvas:
    """One shoulder glyph: a wide low bumper bar, or a taller trigger pedal on its base."""
    rows = TRIGGER_ROWS if trigger else BUMPER_ROWS
    at = TRIGGER_LABEL if trigger else BUMPER_LABEL
    c = Canvas.from_map(rows, BUMPER_PALETTE, T, T)
    c.blit(pixel_font_text(label, WHITE), at[0], at[1])
    return c


def glyph(name: str) -> Canvas:
    if name == "a":
        return _button("A", hex_color("#3cb043"))
    if name == "b":
        return _button("B", hex_color("#e04040"))
    if name == "x":
        return _button("X", hex_color("#3a80e0"))
    if name == "y":
        return _button("Y", hex_color("#f0c030"))
    if name in ("lb", "rb"):
        return _bumper(name.upper())
    if name in ("lt", "rt"):
        return _bumper(name.upper(), trigger=True)
    c = Canvas(T, T)
    if name in ("start", "select"):
        c.ellipse(8, 8, 6, 3.5, OUTLINE)
        c.ellipse(8, 8, 5, 2.5, hex_color("#4a4a58"))
        if name == "start":
            for y in (7, 8, 9):
                c.hline(5, 11, y, WHITE if y == 8 else hex_color("#c0c0c8"))
        else:  # "view"/select: two small panels side by side
            c.rect(4, 7, 3, 3, WHITE)
            c.rect(9, 7, 3, 3, WHITE)
            c.set(5, 8, hex_color("#4a4a58"))
            c.set(10, 8, hex_color("#4a4a58"))
        return c
    if name in ("lstick", "rstick"):
        c.circle(8, 8, 6.5, OUTLINE)
        c.circle(8, 8, 5.5, hex_color("#3a3a48"))
        c.circle(8, 8, 3.5, hex_color("#6a6a78"))
        c.circle(7, 7, 1.5, hex_color("#9a9aa8"))
        c.blit(pixel_font_text("L" if name == "lstick" else "R", WHITE), 7, 6)
        return c
    if name == "dpad":
        c.rect(6, 1, 4, 14, hex_color("#4a4a58"))
        c.rect(1, 6, 14, 4, hex_color("#4a4a58"))
        c = c.outline()
        c.set(8, 3, WHITE)
        c.set(8, 12, WHITE)
        c.set(3, 8, WHITE)
        c.set(12, 8, WHITE)
        return c
    if name == "keycap":
        c.rect(2, 2, 12, 11, hex_color("#e8ecf4"))
        c.rect(2, 2, 12, 11, OUTLINE, filled=False)
        c.rect(2, 12, 12, 2, hex_color("#a0a8b8"))
        c.rect(2, 12, 12, 2, OUTLINE, filled=False)
        c.hline(3, 12, 3, WHITE)
        return c
    # mouse: rounded body, two buttons, the pressed one lit
    rows = (
        "................",
        "....ooooooo.....",
        "...oLLLoRRRo....",
        "...oLLLoRRRo....",
        "...oLLLoRRRo....",
        "...oLLLoRRRo....",
        "...ooooooooo....",
        "...owwwwwwwo....",
        "...owwwwwsso....",
        "...owwwwwsso....",
        "...owwwwwsso....",
        "...owwwwwsso....",
        "...owwwwwsso....",
        "...owwwwwsso....",
        "....ooooooo.....",
        "................",
    )
    lit = hex_color("#3a80e0")
    body, shade_c = hex_color("#e8ecf4"), hex_color("#a0a8b8")
    pressed_left = name == "mouse_left"
    palette = {
        "o": OUTLINE,
        "w": body,
        "s": shade_c,
        "L": lit if pressed_left else body,
        "R": body if pressed_left else lit,
    }
    return Canvas.from_map(rows, palette, T, T)


# -------------------------------------------------------------------------------- icons
def icon(name: str) -> Canvas:
    c = Canvas(T, T)
    if name == "heart":
        return heart()
    if name == "potion":
        c.rect(6, 2, 4, 3, hex_color("#8b5a2b"))
        c.rect(5, 5, 6, 3, hex_color("#c8f0ff", 200))
        c.circle(8, 10.5, 4, hex_color("#e03060"))
        c.circle(8, 11, 3, hex_color("#ff5080"))
        c.set(6, 9, hex_color("#ffb0c0"))
        return c.outline()
    if name == "gold":
        return coin(0)
    if name == "stairs":
        for i in range(4):
            c.rect(2 + i * 3, 11 - i * 3, 12 - i * 3, 3, hex_color("#9a9aa4"))
            c.hline(2 + i * 3, 13, 11 - i * 3, hex_color("#c8c8d0"))
        return c.outline()
    if name == "die":
        c.rect(3, 3, 10, 10, hex_color("#f4f4f8"))
        c.rect(3, 3, 10, 10, OUTLINE, filled=False)
        for x, y in ((5, 5), (10, 5), (5, 10), (10, 10), (7, 7), (8, 8)):
            c.set(x, y, DARK)
        return c
    if name in STAT_ORB_COLORS:
        col = STAT_ORB_COLORS[name]
        c.circle(8, 8, 5, col)
        c.circle(8, 8, 3.5, shade(col, 0.7))
        c = c.outline()
        sym = {
            "vitality": "V", "might": "M", "precision": "P", "arcana": "A", "swiftness": "S", "fortune": "F",
        }
        c.blit(pixel_font_text(sym[name], WHITE), 7, 6)
        return c
    if name.startswith("rarity_"):
        col = {
            "rarity_common": hex_color("#8ab0e0"),
            "rarity_rare": hex_color("#40d070"),
            "rarity_epic": hex_color("#b060ff"),
            "rarity_legendary": hex_color("#ffb020"),
        }[name]
        for i in range(6):
            w = 1 + i * 2 if i < 3 else 5 - (i - 3) * 2
            c.hline(8 - w // 2 - (0 if w % 2 else 1), 8 + w // 2, 4 + i * 1, col)
        c.rect(4, 6, 8, 4, col)
        c.hline(5, 10, 7, shade(col, 1.5))
        for i in range(4):
            c.hline(5 + i, 10 - i, 10 + i, col)
        c.set(8, 14, col)
        return c.outline()
    # lock
    c.rect(4, 7, 8, 7, GOLD)
    c.rect(4, 7, 8, 7, OUTLINE, filled=False)
    c.rect(5, 3, 6, 5, OUTLINE, filled=False)
    c.rect(6, 4, 4, 3, (0, 0, 0, 0))
    c.rect(7, 9, 2, 3, OUTLINE)
    c.set(5, 8, GOLD_L)
    return c


def cursor() -> Canvas:
    c = Canvas(T, T)
    c.vline(8, 1, 5, WHITE)
    c.vline(8, 11, 15, WHITE)
    c.hline(1, 5, 8, WHITE)
    c.hline(11, 15, 8, WHITE)
    c.circle(8, 8, 3, WHITE, filled=False)
    c.set(8, 8, WHITE)
    return c.outline(diagonal=True)


# ------------------------------------------------------------------------------- logo
# The wordmark is baked as explicit pixel maps: rasterising a TTF would make logo.png
# depend on the installed FreeType/Pillow build (and silently change when the fonts have
# not been fetched), which breaks the "re-running the generator is byte-identical" rule.
LOGO_GLYPHS: dict[str, list[str]] = {
    "O": [
        "..#######..",
        ".#########.",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        ".#########.",
        "..#######..",
    ],
    "M": [
        "###.....###",
        "####...####",
        "#####.#####",
        "###.###.###",
        "###..#..###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
    ],
    "A": [
        "...#####...",
        "..#######..",
        ".###...###.",
        "###.....###",
        "###.....###",
        "###.....###",
        "###########",
        "###########",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
    ],
    "D": [
        "#########..",
        "##########.",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "##########.",
        "#########..",
    ],
    "U": [
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        ".#########.",
        "..#######..",
    ],
    "N": [
        "###.....###",
        "####....###",
        "#####...###",
        "###.##..###",
        "###..##.###",
        "###...#####",
        "###....####",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
    ],
    "G": [
        "..#######..",
        ".#########.",
        "###.....###",
        "###........",
        "###........",
        "###..######",
        "###..######",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        ".#########.",
        "..#######..",
    ],
    "E": [
        "###########",
        "###########",
        "###........",
        "###........",
        "###........",
        "#########..",
        "#########..",
        "###........",
        "###........",
        "###........",
        "###........",
        "###########",
        "###########",
    ],
}
LOGO_TEXT = "OMADUNGEON"
LOGO_GLYPH_W = 11
LOGO_GLYPH_H = 13
LOGO_TRACKING = 2


def wordmark(text: str = LOGO_TEXT) -> Canvas:
    """The OMADUNGEON wordmark as solid white pixels (pure function, no font files)."""
    step = LOGO_GLYPH_W + LOGO_TRACKING
    c = Canvas(step * len(text) - LOGO_TRACKING, LOGO_GLYPH_H)
    for i, ch in enumerate(text):
        rows = LOGO_GLYPHS[ch]
        for y, row in enumerate(rows):
            for x, px in enumerate(row):
                if px == "#":
                    c.set(i * step + x, y, WHITE)
    return c


def logo(root: pathlib.Path) -> Canvas:
    """200x40 wordmark plate: two-tone fill, outline, drop shadow and an accent underline."""
    del root  # kept for the generator's uniform module signature
    glyphs = wordmark()
    box = glyphs.bbox()
    assert box is not None
    x0, y0, x1, y1 = box
    glyphs = glyphs.crop(x0, y0, x1 - x0, y1 - y0)
    # two-tone fill: warm highlight top, deeper bottom, then outline + drop shadow.
    top, bottom = hex_color("#ffe08a"), hex_color("#f08a30")
    h = glyphs.height
    filled = glyphs.map_pixels(lambda p: p)
    for y in range(h):
        col = top if y < h * 0.45 else (hex_color("#f6b45a") if y < h * 0.7 else bottom)
        for x in range(glyphs.width):
            if glyphs.get(x, y)[3]:
                filled.set(x, y, col)
    outlined = filled.outline(OUTLINE, diagonal=True)
    ow, oh = outlined.width, outlined.height
    out = Canvas(max(200, ow + 8), 40)
    ox = (out.width - ow) // 2
    oy = (out.height - oh) // 2 - 1
    shadow = outlined.map_pixels(lambda p: hex_color("#3a1c08", 200))
    out.blit(shadow, ox + 2, oy + 3)
    out.blit(outlined, ox, oy)
    # tiny underline sparkle in the void accent
    out.hline(ox + 4, ox + ow - 5, oy + oh + 3, hex_color("#40e0d0"))
    out.set(ox + 2, oy + oh + 3, hex_color("#40e0d0", 120))
    out.set(ox + ow - 3, oy + oh + 3, hex_color("#40e0d0", 120))
    return out


# ------------------------------------------------------------------- icon separation guard
## Two icons collide when they have nearly the same *shape* and nearly the same *colours*.
## Either alone is fine - a red bolt and a blue bolt are told apart instantly, and so are two
## gold icons of different things - but both together is one icon wearing two names, which is
## what the owner reported as "too many shared icons for abilities".
ICON_SHAPE_OVERLAP = 0.85
## Mean per-channel difference (0-255) below which two icons are the same colour to the eye.
ICON_COLOUR_DISTANCE = 40.0


def icon_motif(cell: Canvas) -> list[bool]:
    """Mask of the drawn motif: interior pixels that are not the shared backplate."""
    counts: dict[Color, int] = {}
    for p in cell.pixels:
        counts[p] = counts.get(p, 0) + 1
    plate = max(counts.items(), key=lambda kv: kv[1])[0]
    out = []
    for y in range(cell.height):
        for x in range(cell.width):
            p = cell.get(x, y)
            inside = 1 <= x <= cell.width - 2 and 1 <= y <= cell.height - 2
            out.append(bool(inside and p[3] and p != plate))
    return out


def icon_shape_overlap(a: Canvas, b: Canvas) -> float:
    """Jaccard overlap of two icons' motifs: 1.0 means the same silhouette."""
    ma, mb = icon_motif(a), icon_motif(b)
    both = sum(1 for x, y in zip(ma, mb) if x and y)
    either = sum(1 for x, y in zip(ma, mb) if x or y)
    return both / either if either else 1.0


def icon_colour_distance(a: Canvas, b: Canvas) -> float:
    """Mean per-channel difference between two icons, 0 (identical) to 255."""
    total = sum(abs(p[i] - q[i]) for p, q in zip(a.pixels, b.pixels) for i in range(3))
    return total / (len(a.pixels) * 3)


def weapon_skill_icon(name: str) -> Canvas:
    """One 16x16 weapon-skill icon. Same plate grammar as `ability_icon`, own drawings."""
    if name == "skill_lunge":
        c = _plate(STEEL)
        c.line(3, 12, 13, 2, STEEL)  # a thrust: blade driving up-right, speed lines behind
        c.line(4, 13, 14, 3, STEEL_D)
        c.set(13, 2, WHITE)
        c.set(12, 2, WHITE)
        c.rect(2, 11, 3, 3, hex_color("#8b5a2b"))
        for y in (5, 8, 11):
            c.hline(1, 3, y, STEEL_D)
    elif name == "skill_cleave":
        c = _plate(RED)
        for i in range(5):  # a downward crescent, thick in the middle
            c.line(2 + i, 2 + i, 13, 6 + i, RED if i % 2 else hex_color("#ff8080"))
        c.line(2, 2, 13, 6, WHITE)
        c.rect(11, 11, 4, 3, STEEL_D)
        c.set(12, 12, STEEL)
    elif name == "skill_sweep":
        c = _plate(CYAN)
        for x in range(1, 15):  # a low horizontal arc at ankle height
            y = 11 - int(3.0 * (1.0 - ((x - 8.0) / 7.0) ** 2))
            c.set(x, y, CYAN)
            c.set(x, y + 1, hex_color("#1d8fb0"))
        c.set(1, 11, WHITE)
        c.set(14, 11, WHITE)
        c.rect(7, 2, 2, 5, STEEL_D)
        c.rect(7, 2, 2, 2, STEEL)
    elif name == "skill_barrier":
        c = _plate(ICE)
        c.rect(4, 1, 8, 14, hex_color("#1d4a6a"))  # a standing pane of force, not a shield
        c.rect(4, 1, 8, 14, ICE, filled=False)
        for y in (4, 8, 12):
            c.hline(5, 10, y, ICE)
        c.vline(8, 2, 13, ICE_L)
        c.set(5, 2, WHITE)
    elif name == "skill_bribe":
        c = _plate(GOLD)
        c.rect(2, 6, 7, 8, hex_color("#7a5a20"))  # a purse changing hands
        c.rect(2, 6, 7, 8, GOLD_D_UI, filled=False)
        c.hline(3, 7, 8, GOLD)
        c.set(5, 5, GOLD_D_UI)
        c.set(5, 4, GOLD_D_UI)
        for x, y in ((12, 2), (13, 7), (11, 11)):
            c.circle(x, y, 1.4, GOLD)
            c.set(x, y - 1, GOLD_L)
    elif name == "skill_rain":
        c = _plate(GREEN)
        c.ellipse(7, 3, 6, 2, hex_color("#2c6a2c"))  # arrows falling out of a cloud
        c.ellipse(6, 2, 3, 1, GREEN)
        for x in (3, 7, 11, 14):
            c.vline(x, 6, 12, hex_color("#8b5a2b"))
            c.set(x, 13, STEEL)
            c.set(x, 12, STEEL)
            c.set(x - 1, 6, GREEN)
    else:  # skill_fan_of_knives
        c = _plate(PINK)
        for dx, dy in ((-5, -3), (-3, -5), (0, -6), (3, -5), (5, -3)):
            c.line(8, 13, 8 + dx, 13 + dy, STEEL)
            c.set(8 + dx, 13 + dy, WHITE)
        c.rect(7, 12, 3, 3, PINK)
        c.set(8, 13, WHITE)
    return c


def icon_collisions(cells: dict[str, Canvas]) -> list[tuple[str, str, float, float]]:
    """Every pair of icons a player could mistake for each other."""
    names = list(cells)
    out = []
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            shape = icon_shape_overlap(cells[a], cells[b])
            colour = icon_colour_distance(cells[a], cells[b])
            if shape >= ICON_SHAPE_OVERLAP and colour <= ICON_COLOUR_DISTANCE:
                out.append((a, b, shape, colour))
    return out


def generate(root: pathlib.Path) -> list[pathlib.Path]:
    ui = root / "assets" / "sprites" / "ui"
    out = []
    s = Sheet(T, T, ABILITY_SHEET_CELLS, 1)
    cells = {n: ability_icon(n) for n in ABILITY_ICONS}
    cells.update({n: weapon_skill_icon(n) for n in WEAPON_SKILL_ICONS})
    # Abilities and weapon skills share the HUD row and the pause page, so they are checked
    # against each other, not each within their own group.
    clashes = icon_collisions(cells)
    if clashes:
        raise ValueError(
            "ability icons a player cannot tell apart: "
            + ", ".join(f"{a}~{b} (shape {s_:.2f}, colour {c:.1f})" for a, b, s_, c in clashes)
        )
    s.put_row(0, [cells[n] for n in ABILITY_ICONS + WEAPON_SKILL_ICONS])
    s.save(ui / "ability_icons.png")
    out.append(ui / "ability_icons.png")
    s = Sheet(T, T, 16, 1)
    s.put_row(0, [glyph(n) for n in GLYPHS])
    s.save(ui / "glyphs.png")
    out.append(ui / "glyphs.png")
    s = Sheet(T, T, 16, 1)
    s.put_row(0, [icon(n) for n in ICONS])
    s.save(ui / "icons.png")
    out.append(ui / "icons.png")
    cursor().save(ui / "cursor.png")
    out.append(ui / "cursor.png")
    logo(root).save(root / "assets" / "sprites" / "logo.png")
    out.append(root / "assets" / "sprites" / "logo.png")
    return out
