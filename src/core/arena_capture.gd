## The boss-arena half of the `floor` capture scenario (docs 7.4, owner report #6), kept out
## of `TestScenarios` for that file's line budget. `--scenario-arena entry` puts the player one
## tile inside the arena's door and points the camera at the arena as a whole - it is wider
## than half the view, so a camera on the player at the door could never show the boss
## waiting across it; `--scenario-arena engaged` walks the player past the deep trigger so the
## seal, the roar and the "awakens" banner are on screen. Anything else leaves the player in
## the start room. Same rules as the driver: every node picked up before an `await` is
## re-validated through `TestScenarios.live_room()` before it is read again.
class_name ArenaCapture
extends RefCounted


static func run(driver: TestScenarios, mode: String) -> void:
	if mode.is_empty():
		return
	var data := RunManager.floor_data
	var root := RunManager.floor_root()
	if not driver.require(data != null and root != null, "no floor to find an arena on"):
		return
	var boss := data.room_by_id(data.boss_room)
	var floor_number := RunManager.floor_index + 1
	if not driver.require(boss != null, "floor %d has no boss arena" % floor_number):
		return
	var door := boss.door_tiles()[0]
	var inward := boss.trap_facing(door)
	var depth := RoomNode.BOSS_TRIGGER_INSET + 1 if mode == "engaged" else 1
	var tile := door + inward * depth
	var room := root.get_room(boss.id)
	if not driver.require(room != null, "the arena has no RoomNode"):
		return
	driver._teleport_player(room.tile_to_local(tile))
	if mode != "engaged":
		var focus := Node2D.new()
		focus.name = "ArenaFocus"
		focus.position = boss.center_world()
		room.add_child(focus)
		var view := RunManager.game as Game
		if view != null:
			view.camera.follow(focus)
	await driver._physics_frames(TestScenarios.SETTLE_FRAMES)
	await driver._settle()
	var standing := TestScenarios.live_room(room)
	if not driver.require(standing != null, "the arena was torn down under the capture"):
		return
	var first: Node2D = standing.enemies[0] if not standing.enemies.is_empty() else null
	print(
		(
			"Scenario arena: room %d door %s player tile %s spawns %s first enemy %s at %s"
			% [
				boss.id,
				door,
				tile,
				boss.enemy_spawns,
				first.name if is_instance_valid(first) else "-",
				first.global_position if is_instance_valid(first) else Vector2.INF,
			]
		)
	)
	if mode == "engaged":
		var fired := false
		for child: Node in standing.get_children():
			var arena := child as BossArena
			if arena != null and arena.fired:
				fired = true
		driver.require(fired, "the arena never engaged")
