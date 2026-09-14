## Slices `assets/sprites/projectiles.png` (horizontal strip of square frames) into textures.
## Indices: 0 arrow, 1 bolt, 2 pin, 3 tome, 4 fireball, 5 ice shard, 6 spark, 7 knife,
## 8 confetti, 9 laser dot.
class_name ProjectileSprites
extends RefCounted

const SHEET_PATH := "res://assets/sprites/projectiles.png"
const ARROW := 0
const BOLT := 1
const PIN := 2
const TOME := 3
const FIREBALL := 4
const ICE_SHARD := 5
const SPARK := 6
const KNIFE := 7
const CONFETTI := 8
const LASER_DOT := 9


## Returns an AtlasTexture for frame `index` (the sheet itself is cached by ResourceLoader).
static func frame(index: int) -> Texture2D:
	var sheet := load(SHEET_PATH) as Texture2D
	if sheet == null:
		return null
	var size := maxi(1, sheet.get_height())
	var cols := maxi(1, sheet.get_width() / size)
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2((index % cols) * size, 0, size, size)
	return atlas
