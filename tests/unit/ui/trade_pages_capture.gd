## Rendered check for the pages of the trade view that the gallery cannot reach. Runs as its
## own main scene inside the nested headless sway harness (never on the real session):
##
##   OMADUNGEON_OMARCHY_STATE_DIR=tests/fixtures/omarchy/tokyo-night/state \
##   tools/headless-sway.sh godot --path . --rendering-driver opengl3 \
##       res://tests/unit/ui/trade_pages_capture.tscn
##
## `UiGallery`'s `chest_replace_item` always shows page one of a ring trade and the offer step
## of it, which is the half that was already right. The two pages here are the ones that were
## not: the second ring's page, which carried the *first* ring's before/after numbers under it,
## and the cursed board's price step, whose hint offered to keep an item it was about to throw
## away with the prize.
class_name TradePagesCapture
extends Node

const SCENE := "res://src/ui/chest_ui.tscn"
## The ring in `UiFakes.make_offers(ITEM)`: the one family with two slots, so the only offer
## that asks which piece goes.
const RING_OFFER_INDEX := 2
## Real seconds of settling before each screenshot, so the cards have laid out.
const SETTLE := 0.15


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var player := UiFakes.make_player_two_rings()
	add_child(player)
	var chest := _board(player, {})
	chest.select(RING_OFFER_INDEX)
	chest.activate()
	await _shoot("page1")
	chest.select(1)
	await _shoot("page2")
	chest.queue_free()
	await get_tree().process_frame

	# The cursed board asks twice: which ring goes, and then which passive the Curse takes.
	var cursed := _board(player, _curse_context(player))
	cursed.select(RING_OFFER_INDEX)
	cursed.activate()
	cursed.activate()
	await _shoot("price")
	get_tree().quit(0)


## An open item board over `player`'s loadout, with `extra` merged into its context.
func _board(player: UiFakes.FakePlayer, extra: Dictionary) -> ChestUi:
	var layer := CanvasLayer.new()
	add_child(layer)
	var chest := (load(SCENE) as PackedScene).instantiate() as ChestUi
	layer.add_child(chest)
	chest.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var context := UiFakes.chest_context(player)
	for key: Variant in extra.keys():
		context[key] = extra[key]
	var kind := ChestUi.Kind.CURSED if extra.has("price_offer") else ChestUi.Kind.ITEM
	chest.show_offers(kind, UiFakes.make_offers(ChestUi.Kind.ITEM), context)
	return chest


## The second question a cursed board puts: a Curse wanting one of two full passive slots.
static func _curse_context(player: UiFakes.FakePlayer) -> Dictionary:
	var curse := UiFakes.make_passive("kernel_panic", "Kernel Panic", "Every room is darker.")
	var passives: Array = player.ability_slots.passives.duplicate()
	return {
		"curse_text": RewardEffects.curse_card_text(curse, null),
		"price_offer": curse,
		"price_replace": func(_offer: Variant) -> Array: return passives,
	}


func _shoot(name_part: String) -> void:
	await get_tree().create_timer(SETTLE).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(_out_path(name_part))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	print("trade capture -> %s (%s)" % [path, error_string(image.save_png(path))])


## `tests/out/ui_trade_<page>.png`, with `_<theme>` appended for any fixture but the default,
## so a second theme never overwrites the first (docs/TESTING.md tier 2).
static func _out_path(name_part: String) -> String:
	var state := OS.get_environment("OMADUNGEON_OMARCHY_STATE_DIR")
	var theme := state.trim_suffix("/").get_base_dir().get_file() if not state.is_empty() else ""
	if theme.is_empty() or theme == "tokyo-night":
		return "res://tests/out/ui_trade_%s.png" % name_part
	return "res://tests/out/ui_trade_%s_%s.png" % [name_part, theme]
