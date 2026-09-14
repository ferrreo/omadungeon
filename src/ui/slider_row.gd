## One settings slider plus its percentage readout, in a slab that lights up when the slider
## has focus.
##
## Why it is a node and not four more lines in `SettingsPanel._add_row`. `HSlider` has no
## `focus` stylebox: the only thing the engine changes when a slider takes focus is the
## `grabber_area_highlight` stylebox and the `grabber_highlight` icon, and both of those are
## *inside* the 60-pixel track. On the Audio page that is three near-identical rows in a
## column, and a shade change inside a thin bar is not an answer to "which one am I on" - the
## owner's report was that a focused audio slider had no highlight at all. A check row already
## answers it with a slab: the `check_focus` stylebox is a `select` fill with an `accent`
## border, and it is the one cue the whole UI uses for "the controller is here". This wraps the
## slider in the same slab so the two kinds of row answer the question the same way.
##
## The slab is two `PanelContainer` theme variations (`SliderSlab`, `SliderSlabFocus`, built in
## `UiTheme._build_structure`) rather than a stylebox painted here, so a palette change
## repaints it along with everything else and this node owns no colours of its own. Both
## variations carry the same content margin, so taking focus never nudges the layout.
class_name SliderRow
extends PanelContainer

## Emitted when the player moves the slider, with its new value.
signal value_changed(value: float)

## `PanelContainer` variations for the two states; see `UiTheme._build_structure`.
const IDLE_VARIATION := &"SliderSlab"
const FOCUS_VARIATION := &"SliderSlabFocus"
## Step the pad and the arrow keys move the value by.
const STEP := 0.05
## Track size. The readout beside it is sized for "100%".
const TRACK_SIZE := Vector2(60, 10)
const VALUE_WIDTH := 24.0

## The slider itself. Public because the panel registers it in the focus chain and reads it
## back by settings key.
var slider: HSlider

var _value: Label


func _init() -> void:
	theme_type_variation = IDLE_VARIATION
	var box := HBoxContainer.new()
	box.add_theme_constant_override(&"separation", UiTheme.GAP)
	add_child(box)
	slider = HSlider.new()
	slider.step = STEP
	slider.custom_minimum_size = TRACK_SIZE
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(slider)
	_value = Label.new()
	_value.custom_minimum_size = Vector2(VALUE_WIDTH, 0)
	_value.theme_type_variation = &"Dim"
	box.add_child(_value)
	slider.focus_entered.connect(_refresh_focus)
	slider.focus_exited.connect(_refresh_focus)
	_refresh_focus()


## Sets the range and the starting value, then starts reporting the player's moves.
##
## `value_changed` is connected *here*, at the end, rather than in `_init`: raising
## `min_value` past the slider's current value clamps it and emits, so a row with a floor (the
## stick deadzone starts at 0.05) would have written its own setting back while it was still
## being built.
func configure(minimum: float, maximum: float, value: float) -> void:
	slider.min_value = minimum
	slider.max_value = maximum
	slider.set_value_no_signal(value)
	_refresh_value(value)
	if not slider.value_changed.is_connected(_on_slider_value_changed):
		slider.value_changed.connect(_on_slider_value_changed)


## Whether the row is drawing its focus slab. The state the owner's report is about, so it is
## readable rather than inferred from the stylebox by every caller that wants to check.
func is_focus_shown() -> bool:
	return theme_type_variation == FOCUS_VARIATION


func _on_slider_value_changed(value: float) -> void:
	_refresh_value(value)
	value_changed.emit(value)


func _refresh_value(value: float) -> void:
	_value.text = "%d%%" % int(roundf(value * 100.0))


func _refresh_focus() -> void:
	theme_type_variation = FOCUS_VARIATION if slider.has_focus() else IDLE_VARIATION
