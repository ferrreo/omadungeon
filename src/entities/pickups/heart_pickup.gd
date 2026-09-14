## Heart: heals the player's Health by `amount` (default 15).
class_name HeartPickup
extends PickupBase


func _init() -> void:
	kind = &"heart"
	color_role = &"heal"
	radius = 3.0
	amount = 15


func _collect(player: Node2D) -> void:
	var entity := player as Entity
	if entity != null and entity.health != null:
		entity.health.heal(float(amount))
	else:
		PickupBase.call_player(player, &"heal", [float(amount)])


func _draw() -> void:
	var bob := sin(_age * 6.0 + _bob_phase) * 1.0
	draw_circle(Vector2(0.0, radius * 0.6), radius * 0.9, Color(0, 0, 0, 0.3))
	var y := -radius - bob
	# The halo is the whole heart drawn a pixel larger behind it, so what survives the body on
	# top is a one-pixel rim in the opposite direction from the ink (`LootInk`).
	if LootInk.has_halo(halo):
		_lobes_and_tip(y, LootInk.HALO_WIDTH, halo)
	draw_circle(Vector2(-radius * 0.45, y - radius * 0.3), radius * 0.6, color)
	draw_circle(Vector2(radius * 0.45, y - radius * 0.3), radius * 0.6, color)
	var tip := PackedVector2Array(
		[
			Vector2(-radius * 1.0, y - radius * 0.1),
			Vector2(radius * 1.0, y - radius * 0.1),
			Vector2(0.0, y + radius * 0.9)
		]
	)
	draw_colored_polygon(tip, color)


## The heart's two lobes and its tip, every edge `grow` px out from where the body draws them.
func _lobes_and_tip(y: float, grow: float, ink: Color) -> void:
	var reach := radius + grow * 1.5
	draw_circle(Vector2(-radius * 0.45, y - radius * 0.3), radius * 0.6 + grow, ink)
	draw_circle(Vector2(radius * 0.45, y - radius * 0.3), radius * 0.6 + grow, ink)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-reach, y - radius * 0.1),
				Vector2(reach, y - radius * 0.1),
				Vector2(0.0, y + radius * 0.9 + grow * 1.5)
			]
		),
		ink
	)
