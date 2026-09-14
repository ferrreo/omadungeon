## Stat orb: grants +`amount` to a primary stat via `player.add_stat(stat, amount)`.
class_name StatOrbPickup
extends PickupBase

var stat: StringName = &"might"


func _init() -> void:
	kind = &"stat_orb"
	color_role = &"magic"
	radius = 3.5
	amount = 1


## Picks the stat by index into Stats.PRIMARY (used by the spawn_pickup signal).
func set_stat_index(index: int) -> void:
	stat = Stats.PRIMARY[clampi(index, 0, Stats.PRIMARY.size() - 1)]


## Which primary the orb grants, so a resume hands back the stat the elite actually dropped
## rather than the `might` default. `amount` is carried by the base entry.
func save_extra(out: Dictionary) -> void:
	out["stat"] = String(stat)


## Reads `save_extra()` back. An unknown name keeps the current stat: a save from a build whose
## primaries were spelled differently restores a working orb instead of a dud that grants
## nothing.
func load_extra(data: Dictionary) -> void:
	var saved := StringName(str(data.get("stat", stat)))
	if Stats.PRIMARY.has(saved):
		stat = saved


func _collect(player: Node2D) -> void:
	if not PickupBase.call_player(player, &"add_stat", [stat, amount]):
		push_warning("StatOrbPickup: player has no add_stat(stat, amount)")


func _draw() -> void:
	var bob := sin(_age * 6.0 + _bob_phase) * 1.0
	draw_circle(Vector2(0.0, radius * 0.6), radius * 0.9, Color(0, 0, 0, 0.3))
	var y := -radius - bob
	var glow := color
	glow.a = 0.25 + 0.15 * sin(_age * 9.0)
	draw_circle(Vector2(0.0, y), radius * 1.8, glow)
	# Over the soft glow and under the body, so the rim is solid rather than a composite of a
	# translucent wash and whatever is behind it (`LootInk`).
	if LootInk.has_halo(halo):
		draw_circle(Vector2(0.0, y), radius + LootInk.HALO_WIDTH, halo)
	draw_circle(Vector2(0.0, y), radius, color)
	draw_circle(Vector2(-radius * 0.3, y - radius * 0.3), radius * 0.35, color.lightened(0.6))
