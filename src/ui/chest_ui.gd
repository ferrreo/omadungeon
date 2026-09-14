## Chest reward picker: 3 (or 4) big cards, gamepad-navigable, with comparison deltas,
## reroll / skip and a replace flow drawn as one table (`CompareView`). Purely presentational:
## emits `chosen`, `rerolled`, `skipped` and lets the RunManager resolve them. The cards are
## built by `OfferCard`; the board owns what is on them (`describe_offer`).
##
## The picker is **modal**, but it does not pause the tree itself: `RunManager` freezes the run
## around the offer (see `_hold_pause`) because it is the thing that knows when the offer is
## really over. The picker's own scene is PROCESS_MODE_ALWAYS so it keeps animating and taking
## input while the run behind it is stopped.
##
## Rarity is a border colour by default. With `colorblind_glyphs` on every card also carries
## its rarity as a shape plus a pip count in the subtitle ("*** Epic Ring"), so the four
## rarities are told apart by counting rather than by hue. Opening, the selection pop and the
## "you cannot afford this" shake all go through `Accessibility.motion`.
class_name ChestUi
extends Control

## Emitted when the player has answered everything a taken offer asks. `replace_index` is what
## the offer itself displaces (which ring, which ability slot) and `price_index` what its price
## displaces (which passive a cursed board's Curse takes); -1 each when nothing was given up.
signal chosen(offer: Variant, replace_index: int, price_index: int)
signal rerolled
signal skipped

enum Kind { STAT, ITEM, ABILITY, GOLD, CURSED }
enum Row { OFFERS, REPLACE, BUTTONS }
## Which question the trade view is putting. A cursed board asks both: the prize can cost a
## worn ring *and* a passive slot, and neither may be taken without being asked for.
enum Step { OFFER, PRICE }

const KIND_TITLES: PackedStringArray = [
	"Stat chest", "Item chest", "Ability chest", "Gold chest", "Cursed chest"
]
## Smallest a card may be. Cards grow taller (up to `MAX_CARD_HEIGHT`) when their content asks
## for it: an item card carries the weapon block, the affixes and the comparison, and the
## affixes of a Legendary are the reason you are choosing it - they may not be cut away.
const CARD_SIZE := Vector2(140, 96)
## Tallest a card may grow before its tail rows collapse into "+N more". This is what the
## 480x270 frame can give a card once the dialog's own chrome (title, subtitle, button row,
## hint, padding) is paid for; 192 was tried and pushed the title off the top of the screen.
const MAX_CARD_HEIGHT := 176.0
## Room the compare screen gets inside the dialog: `MAX_PANEL_HEIGHT` less the title, the
## subtitle, the button row, the hint and the padding. The table inside it never cuts a row:
## past this it closes its row gap and then scrolls (`CompareView`).
const COMPARE_HEIGHT := 168.0
const CARD_GAP := 8
const PANEL_PAD := 14
const OPEN_TIME := 0.18
## Widest the dialog may grow at the 480x270 internal resolution.
const MAX_PANEL_WIDTH := 464.0
## The dialog is sized to its content between these two heights, so a one-card gold chest is
## not a screen-high box with a card floating in the middle of it.
const MIN_PANEL_HEIGHT := 150.0
const MAX_PANEL_HEIGHT := 264.0
# There is deliberately no cap on how many description rows an offer may hand over. There used
# to be three (8 lines, 4 stat deltas, 6 swap rows) and they cut the list before the card had
# run out of room: a card is grown to its content by `card_height_for` and then filled by
# `fit_rows`, which measures the space that is actually left and spends it, so the only honest
# place to stop is where the pixels stop - and the full comparison is one press away.

var kind: int = Kind.STAT
var offers: Array = []
var context: Dictionary = {}

var _row: int = Row.OFFERS
var _col: int = 0
var _cards: Array[PanelContainer] = []
var _replace_options: Array = []
var _pending_offer: Variant = null
## The card on the right of the trade: the offer itself, or the price once the offer's own
## slot question has been answered.
var _replace_incoming: Variant = null
var _step: int = Step.OFFER
## The offer step's answer, held while the price step is on screen; -1 until it is given.
var _offer_index: int = -1
var _retint_left: float = 0.0
var _is_open: bool = false
var _card_w: float = CARD_SIZE.x
var _head_h: float = 0.0
var _last_selection: Vector2i = Vector2i(-1, -1)
var _card_tweens: Dictionary = {}
var _card_h: float = CARD_SIZE.y
var _compare: CompareView
## The hint line and the one-off notices that borrow it (see `answer_pause`).
var _hint_line: UiHintLine

@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _cards_row: HBoxContainer = %Cards
@onready var _replace_box: VBoxContainer = %ReplaceBox
@onready var _reroll: Button = %Reroll
@onready var _skip: Button = %Skip
@onready var _swap_button: Button = %Swap
@onready var _keep: Button = %Keep
@onready var _hint: UiPrompt = %Hint


func _ready() -> void:
	UiTheme.apply(self)
	# The board draws its own selection and focuses nothing, so the stick has to be served.
	UiStickNav.serve(self)
	_hint_line = UiHintLine.new(_hint, UiNavProfile.load_default().notice_seconds)
	for button: Button in [_reroll, _skip, _swap_button, _keep]:
		button.focus_mode = Control.FOCUS_NONE
	_reroll.pressed.connect(_on_reroll)
	_skip.pressed.connect(_on_skip)
	_swap_button.pressed.connect(_confirm_replace)
	_keep.pressed.connect(_cancel_replace)
	_replace_box.visible = false
	_swap_button.visible = false
	_keep.visible = false
	_compare = CompareView.new()
	_replace_box.add_child(_compare)
	EventBus.palette_changed.connect(func(_p: ThemePalette) -> void: _retint_left = 0.7)
	EventBus.input_device_changed.connect(func(_d: int) -> void: _refresh_hint())
	if not _is_open:
		visible = false


## Safety net: a chest freed or hidden while open must not leave the music ducked.
func _exit_tree() -> void:
	if not _is_open:
		return
	_is_open = false
	EventBus.music_duck.emit(0.5, false)


func _process(delta: float) -> void:
	if _retint_left > 0.0:
		_retint_left -= delta
		_refresh_selection(false)
	if _hint_line != null and _hint_line.tick(delta):
		_refresh_hint()


func _input(event: InputEvent) -> void:
	InputGlyphs.observe(event)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _is_open:
		return
	if event.is_action_pressed(&"ui_right"):
		_move(1)
	elif event.is_action_pressed(&"ui_left"):
		_move(-1)
	elif event.is_action_pressed(&"ui_down"):
		if _row == Row.REPLACE and _compare.is_scrollable():
			_compare.scroll_by(1)
		else:
			_move_row(1)
	elif event.is_action_pressed(&"ui_up"):
		if _row == Row.REPLACE and _compare.is_scrollable():
			_compare.scroll_by(-1)
		else:
			_move_row(-1)
	elif event.is_action_pressed(&"ui_accept"):
		activate()
	elif event.is_action_pressed(&"ui_cancel"):
		if _row == Row.REPLACE:
			_cancel_replace()
		elif not _back_out():
			return
	elif event.is_action_pressed(&"pause"):
		answer_pause()
	else:
		return
	get_viewport().set_input_as_handled()


## Shows the chest with `offers` (ItemInstance / Ability / {stat, points} / int gold).
## Context keys: extra_option, current_stats, compare(Callable), equipped(Callable), reroll_cost,
## free_reroll, can_reroll, skip_gold, skip_keeps, needs_replace(Callable), gold, title,
## curse_text, weapon (the worn WeaponBase, for the inert-card note), sold_out,
## no_skip (a mandatory pick, e.g. the starting passive: the Skip button is hidden).
func show_offers(new_kind: int, new_offers: Array, new_context: Dictionary) -> void:
	kind = new_kind
	offers = new_offers
	context = new_context
	_pending_offer = null
	_replace_incoming = null
	_step = Step.OFFER
	_offer_index = -1
	_replace_box.visible = false
	_cards_row.visible = true
	_replace_options = []
	_title.text = str(context.get("title", _default_title()))
	_subtitle.text = _default_subtitle()
	var n := maxi(1, offers.size())
	_card_w = card_width(n)
	_build_cards(_cards_row, _cards, offers)
	_set_panel_width(n * _card_w + (n - 1) * CARD_GAP + PANEL_PAD * 2)
	_refresh_buttons()
	_fit_panel()
	# An empty board (a bought-out counter) has nothing to select: the selection starts on the
	# buttons, so the first press restocks or leaves instead of landing on nothing.
	_row = Row.BUTTONS if _cards.is_empty() else Row.OFFERS
	_col = mini(_col, maxi(0, _row_size() - 1))
	_last_selection = Vector2i(-1, -1)
	_refresh_selection()
	_refresh_hint()
	if not _is_open:
		open()


func open() -> void:
	_is_open = true
	visible = true
	_panel.pivot_offset = _panel.size * 0.5
	if not Accessibility.animates():
		_panel.scale = Vector2.ONE
		modulate.a = 1.0
		EventBus.music_duck.emit(0.5, true)
		return
	_panel.scale = Vector2(0.9, 0.9)
	modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 1.0, OPEN_TIME)
	(
		tween
		. tween_property(_panel, "scale", Vector2.ONE, OPEN_TIME)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	EventBus.music_duck.emit(0.5, true)


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	EventBus.music_duck.emit(0.5, false)
	if not Accessibility.animates():
		modulate.a = 0.0
		visible = false
		return
	var tween := create_tween().set_parallel(true)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 0.0, OPEN_TIME * 0.7)
	tween.tween_property(_panel, "scale", Vector2(0.94, 0.94), OPEN_TIME * 0.7)
	tween.chain().tween_callback(func() -> void: visible = _is_open)


func is_open() -> bool:
	return _is_open


## Sizes the dialog to what is on it. The cards are the tall part and they grow with their
## content, so the panel cannot be a fixed box: it would either crop an item comparison or
## frame a single gold card in a screen of empty panel.
func _fit_panel() -> void:
	var wanted := clampf(_panel.get_combined_minimum_size().y, MIN_PANEL_HEIGHT, MAX_PANEL_HEIGHT)
	_panel.offset_top = -floorf(wanted * 0.5)
	_panel.offset_bottom = floorf(wanted * 0.5)


func card_count() -> int:
	return _cards.size()


func selected_index() -> int:
	return _col


func selected_row() -> int:
	return _row


## Which question the trade view is on (`Step`). `Step.PRICE` only ever follows a board that
## carries a price, and only once the offer's own slot question has been answered.
func replace_step() -> int:
	return _step


## The compare screen (the replace step's table). Always present; visible only while an
## offer is waiting for the player to say what it displaces.
func compare_view() -> CompareView:
	return _compare


## False while the swap view has the dialog to itself.
func offers_visible() -> bool:
	return _cards_row.visible


func select(col: int) -> void:
	var next := wrapi(col, 0, maxi(1, _row_size()))
	var moved := next != _col
	_col = next
	# The compare screen shows one pair at a time, so moving the selection turns the page.
	if moved and _row == Row.REPLACE:
		_build_compare()
	_refresh_selection()


## Confirms the current selection (ui_accept).
func activate() -> void:
	match _row:
		Row.OFFERS:
			if offers.is_empty():
				return
			if not can_pick(_col):
				UiHintLine.shake(_cards[_col] if _col < _cards.size() else _panel)
				return
			_try_choose(offers[_col])
		Row.REPLACE:
			_confirm_replace()
		Row.BUTTONS:
			var buttons := _buttons()
			if buttons.is_empty():
				return
			buttons[clampi(_col, 0, buttons.size() - 1)].pressed.emit()


## True when RunManager passed `shop: true` (cards carry prices and cost gold).
func is_shop() -> bool:
	return bool(context.get("shop", false)) or context.has("prices")


func current_gold() -> int:
	return int(context.get("gold", 0))


## Gold price of the offer at `index`, or -1 when the offer is free.
func price_for(index: int) -> int:
	var prices: Variant = context.get("prices")
	if prices is Array:
		var list := prices as Array
		return int(list[index]) if index >= 0 and index < list.size() else -1
	if prices is Dictionary:
		var map := prices as Dictionary
		if map.has(index):
			return int(map[index])
	return -1


## False only for a priced offer the player cannot pay for.
func can_afford(index: int) -> bool:
	var price := price_for(index)
	if price <= 0 or not context.has("gold"):
		return true
	return current_gold() >= price


## False when the offer cannot be taken at all: too expensive, or marked `unavailable` by
## whoever built it (a Shrine cleanse with no curse to lift charges 25 HP for nothing, so the
## card says why and refuses instead).
func can_pick(index: int) -> bool:
	return can_afford(index) and not is_unavailable(index)


## True when the offer at `index` carries `unavailable` (offer dictionaries only).
func is_unavailable(index: int) -> bool:
	if index < 0 or index >= offers.size():
		return false
	var offer: Variant = offers[index]
	return offer is Dictionary and bool((offer as Dictionary).get("unavailable", false))


func _default_subtitle() -> String:
	# Kept short on purpose: a sold-out counter lays out as a one-card board (~168 px) and a
	# sentence would run off the panel. The Restock button says the rest.
	if bool(context.get("sold_out", false)):
		return "Sold out"
	if is_shop():
		return "Buy one (you have %dg)" % current_gold()
	if kind == Kind.CURSED:
		return "A curse comes with the prize"
	return "Choose one"


func _default_title() -> String:
	if bool(context.get("shop", false)):
		return "Shop"
	return KIND_TITLES[clampi(kind, 0, KIND_TITLES.size() - 1)]


func _try_choose(offer: Variant) -> void:
	_offer_index = -1
	var current := replace_options_for(offer)
	if not current.is_empty():
		_start_replace(offer, current, Step.OFFER)
		return
	var price := price_options_for(offer)
	if not price.is_empty():
		_start_replace(offer, price, Step.PRICE)
		return
	chosen.emit(offer, -1, -1)
	close()


## Takes the answer on screen. The offer's own question comes first and is held; if its price
## asks one too, that is put next, on the same dialog, before anything is taken. A cursed
## Legendary ring used to ask only about the passive its Curse wanted and equip itself over a
## worn ring in silence - the one thing the trade view exists to stop.
func _confirm_replace() -> void:
	if _step == Step.PRICE:
		chosen.emit(_pending_offer, _offer_index, _col)
		close()
		return
	_offer_index = _col
	var price := price_options_for(_pending_offer)
	if not price.is_empty():
		_start_replace(_pending_offer, price, Step.PRICE)
		return
	chosen.emit(_pending_offer, _offer_index, -1)
	close()


## What taking `offer` would displace, in the order the replace row shows it. Empty when the
## offer fits as it is, or when the context carries no `needs_replace` lookup.
func replace_options_for(offer: Variant) -> Array:
	return _options_from(context.get("needs_replace"), offer)


## What the *price* of `offer` would displace: a cursed board's Curse takes a passive slot of
## its own, which is a second question about a second slot. Empty for a board with no price
## (`price_offer`), and empty while the price still has a free slot to land in.
func price_options_for(offer: Variant) -> Array:
	if context.get("price_offer") == null:
		return []
	return _options_from(context.get("price_replace"), offer)


## Calls one of the board's `Callable(offer) -> Array` lookups; [] when it has none.
static func _options_from(lookup: Variant, offer: Variant) -> Array:
	if not (lookup is Callable and (lookup as Callable).is_valid()):
		return []
	var current: Variant = (lookup as Callable).call(offer)
	return current as Array if current is Array else []


## Opens the swap view: the offers row stands down and the whole dialog becomes the trade.
## Leaving the cards on screen behind it is what made the old replace step unreadable.
func _start_replace(offer: Variant, current: Array, step: int) -> void:
	_pending_offer = offer
	_step = step
	_replace_incoming = context.get("price_offer") if step == Step.PRICE else offer
	_replace_options = current
	_cards_row.visible = false
	_replace_box.visible = true
	_row = Row.REPLACE
	_col = 0
	_subtitle.text = CompareView.subtitle_for(current)
	_build_compare()
	_sync_step_buttons()
	_fit_panel()
	_refresh_selection()
	_refresh_hint()


## B / Escape on the trade view: the whole trade is off, both questions with it. Backing out
## of the price step to the one before it would leave the player half-committed to a card they
## have just said no to.
func _cancel_replace() -> void:
	_pending_offer = null
	_replace_incoming = null
	_step = Step.OFFER
	_offer_index = -1
	_replace_box.visible = false
	_cards_row.visible = true
	_row = Row.OFFERS
	_col = clampi(_col, 0, maxi(0, _cards.size() - 1))
	var n := maxi(1, _cards.size())
	_set_panel_width(n * _card_w + (n - 1) * CARD_GAP + PANEL_PAD * 2)
	_subtitle.text = _default_subtitle()
	_sync_step_buttons()
	_fit_panel()
	_refresh_selection()
	_refresh_hint()


## Builds (or re-builds) the compare table for the candidate the selection is on.
func _build_compare() -> void:
	if _compare == null or _replace_options.is_empty():
		return
	var index := clampi(_col, 0, maxi(0, _replace_options.size() - 1))
	# A cursed chest's prize is not free: its curse is stated on the trade too, but only on the
	# offer's own step. The price step shows the curse itself on the right.
	var note := str(context.get("curse_text", "")) if _step == Step.OFFER else ""
	_compare.build(
		_replace_options[index],
		_replace_incoming,
		index,
		_replace_options.size(),
		COMPARE_HEIGHT,
		note
	)
	# Clicking either head is the same answer the button gives: this trade, now.
	_compare.out_head.gui_input.connect(_on_card_input.bind(index, true))
	_compare.in_head.gui_input.connect(_on_card_input.bind(index, true))
	_set_panel_width(MAX_PANEL_WIDTH)


## The button row belongs to the step it is on. Reroll and Skip are answers to the board, not
## to "which one goes", so the compare screen swaps them for Swap and Keep mine - the same two
## answers the A and B buttons give, for the hand on a mouse.
func _sync_step_buttons() -> void:
	var trading := _replace_box.visible
	_reroll.visible = bool(context.get("can_reroll", true)) and not trading
	_skip.visible = can_skip() and not trading
	_swap_button.visible = trading
	_keep.visible = trading
	_keep.text = keep_label(_step == Step.PRICE)
	if _row == Row.BUTTONS:
		_col = clampi(_col, 0, maxi(0, _buttons().size() - 1))


## Caption of the back-out button on the compare screen: what the back key does on this step.
static func keep_label(cancels_trade: bool) -> String:
	return (CompareView.CANCEL_ALL_VERB if cancels_trade else CompareView.KEEP_VERB).capitalize()


## The buttons a player can land on right now, in row order.
func _buttons() -> Array[Button]:
	var out: Array[Button] = []
	for button: Button in [_reroll, _skip, _swap_button, _keep]:
		if button.visible:
			out.append(button)
	return out


## Centres the dialog on `width`, clamped to what the 480x270 frame can hold.
func _set_panel_width(width: float) -> void:
	var half := floorf(minf(width, MAX_PANEL_WIDTH) * 0.5)
	_panel.offset_left = -half
	_panel.offset_right = half


func _on_reroll() -> void:
	if not _can_reroll():
		UiHintLine.shake(_reroll)
		return
	rerolled.emit()


func _on_skip() -> void:
	if not can_skip():
		return
	skipped.emit()
	close()


## False for a mandatory pick (`no_skip`). The Skip button is then hidden rather than
## disabled: a button that closes the dialog and immediately re-opens the same cards with a
## scolding toast is indistinguishable from a bug.
func can_skip() -> bool:
	return not bool(context.get("no_skip", false))


func _can_reroll() -> bool:
	if bool(context.get("free_reroll", false)):
		return true
	if not context.has("gold"):
		return true
	return int(context.get("gold", 0)) >= int(context.get("reroll_cost", 0))


func _row_size() -> int:
	match _row:
		Row.OFFERS:
			return _cards.size()
		Row.REPLACE:
			return _replace_options.size()
	return maxi(1, _buttons().size())


## B / Escape on an offers board. `ui_cancel` used to fall through unhandled here and `pause`
## is refused by the open guard, so on a pad both of the buttons that mean "get me out of
## here" did nothing at all, with nothing on screen saying that the way out was a d-pad press
## down onto a button row below the cards.
##
## First press moves the selection onto Skip/Leave - which names the consequence ("Leave",
## "Skip (+5g)") before anything happens; a second press takes it. Returns false for a board
## with no way out (a mandatory pick), which is then still unhandled and still says nothing,
## because there is nothing to say.
func _back_out() -> bool:
	if not can_skip() or not _skip.visible:
		return false
	var skip_col := maxi(0, _buttons().find(_skip))
	if _row == Row.BUTTONS and _col == skip_col:
		_on_skip()
		return true
	_row = Row.BUTTONS
	_col = skip_col
	_refresh_selection()
	_refresh_hint()
	return true


## Start, pressed on an open board. `PauseMenu` refuses to stack itself over a board on
## purpose (`_blocked_by_modal`), so the press reached nothing at all - and silence from the
## button every other screen answers is indistinguishable from a hung game. The board points
## at the way out instead of taking it (Start does not mean "leave", and a mis-pressed Start
## that skipped an offer would be worse than the silence) and says so on the hint line.
func answer_pause() -> void:
	if can_skip() and _skip.visible:
		_hint_line.notice(UiHintLine.leave_notice(_skip.text))
		UiHintLine.shake(_skip)
	else:
		_hint_line.notice(UiHintLine.MANDATORY_NOTICE)
		UiHintLine.shake(_panel)


func _move(dir: int) -> void:
	select(_col + dir)


func _move_row(dir: int) -> void:
	var rows: Array[int] = []
	# A bought-out counter has no card row to move back up into.
	if not _cards.is_empty():
		rows.append(Row.OFFERS)
	if _replace_box.visible:
		rows.append(Row.REPLACE)
	rows.append(Row.BUTTONS)
	var idx := maxi(0, rows.find(_row))
	idx = clampi(idx + dir, 0, rows.size() - 1)
	_row = rows[idx]
	_col = clampi(_col, 0, maxi(0, _row_size() - 1))
	_refresh_selection()


func _refresh_buttons() -> void:
	# A board that cannot be rerolled at all (a Shrine's fixed options, a pick the player can
	# never pay for) shows no button: an offer to do something impossible is not an offer.
	_sync_step_buttons()
	_reroll.text = reroll_label(context)
	# Never `disabled`: a disabled Button draws its own stylebox and the gamepad focus
	# highlight would vanish. Refusal is the shake in `_on_reroll` instead.
	_reroll.modulate = Color(1, 1, 1, 1.0 if _can_reroll() else 0.55)
	_skip.text = skip_label(context)


## The reroll button's caption. An unaffordable reroll states the shortfall instead of only
## refusing with a shake: at 0 gold, "Reroll (25g)" reads as a button that does nothing.
## A sold-out counter restocks rather than rerolls, and says so.
static func reroll_label(source: Dictionary) -> String:
	var verb := "Restock" if bool(source.get("sold_out", false)) else "Reroll"
	if bool(source.get("free_reroll", false)):
		return "%s (free)" % verb
	var cost := int(source.get("reroll_cost", 0))
	# A price of nothing is free, and "Reroll (0g)" reads as a button that has lost its number.
	if cost <= 0:
		return "%s (free)" % verb
	if not source.has("gold") or int(source.get("gold", 0)) >= cost:
		return "%s (%dg)" % [verb, cost]
	return "%s %dg - you have %d" % [verb, cost, int(source.get("gold", 0))]


## The skip button's caption, which has to state the consequence and nothing else.
## "Leave" is the harmless back-out and is only ever printed on a board whose source survives
## being closed (`skip_keeps`): a Shop, an Altar, a Shrine. "Skip (+Ng)" is printed only when
## that gold is actually paid, and a chest already opened but not worth a bonus is a plain
## "Skip". The two used to be swapped - the Altar promised gold it never paid and destroyed
## the floor's one Altar, and the Shrine said "Leave" and spent itself.
static func skip_label(source: Dictionary) -> String:
	if bool(source.get("skip_keeps", false)) or bool(source.get("shop", false)):
		return "Leave"
	var gold := int(source.get("skip_gold", 0))
	return "Skip (+%dg)" % gold if gold > 0 else "Skip"


func _refresh_hint() -> void:
	var pad := InputGlyphs.current_device() == InputGlyphs.Device.GAMEPAD
	if _replace_box.visible:
		# On the price step B is not "keep mine": `_cancel_replace` drops the whole trade,
		# prize included, so the line has to say that instead of promising a half-way out.
		_hint_line.set_text(
			CompareView.hint_text(
				pad, _replace_options.size(), _step == Step.PRICE, _compare.is_scrollable()
			)
		)
		return
	var verb := "buy" if is_shop() else "pick"
	# The way out belongs on the line too: without it the only button that leaves the board was
	# a d-pad press down onto a row the hint never mentioned.
	var leave := ""
	if can_skip() and _skip.visible:
		leave = "   {ui_cancel} %s" % _skip.text.to_lower()
	# The stick as well as the cross: the stick reaches this board too (`UiStickNav`).
	var move := "{#dpad}{#lstick}" if pad else "{ui_left}{ui_right}"
	_hint_line.set_text("%s move   {ui_accept} %s%s" % [move, verb, leave])


func _refresh_selection(animate: bool = true) -> void:
	# Moving the selection is the player moving on, which takes down any answer the board was
	# still holding up (see `answer_pause`). The retint pass asks for no animation and is not
	# the player doing anything, so it leaves the notice alone.
	if animate and _hint_line != null and _hint_line.showing_notice():
		_refresh_hint()
	var selection := Vector2i(_row, _col)
	var moved := animate and selection != _last_selection
	_last_selection = selection
	for i in _cards.size():
		_style_card(_cards[i], offers[i], _row == Row.OFFERS and i == _col, moved)
	if _replace_box.visible and _compare.out_head != null:
		_compare.set_selected(_row == Row.REPLACE)
	var buttons := _buttons()
	for i in buttons.size():
		var focused := _row == Row.BUTTONS and i == _col
		buttons[i].add_theme_stylebox_override(
			"normal", UiTheme.theme().get_stylebox(&"focus" if focused else &"normal", &"Button")
		)


## Recolours one card in place (`OfferCard.restyle`); the scale tween only runs when the
## selection actually moved.
func _style_card(card: PanelContainer, offer: Variant, selected: bool, animate: bool) -> void:
	OfferCard.restyle(card, border_role_for(offer), selected)
	var target := Vector2(1.04, 1.04) if selected else Vector2.ONE
	if not Accessibility.animates():
		card.scale = target
		return
	if not animate:
		return
	var previous: Variant = _card_tweens.get(card.get_instance_id())
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()
	if card.scale.is_equal_approx(target):
		return
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(card, "scale", target, 0.1).set_trans(Tween.TRANS_BACK)
	_card_tweens[card.get_instance_id()] = tween


## Palette role for an offer's border (rarity for items, kind colour otherwise).
static func border_role_for(offer: Variant) -> StringName:
	if offer is ItemInstance:
		return (offer as ItemInstance).rarity_role()
	if offer is PassiveAbility:
		return &"magic"
	if offer is Ability:
		return &"accent"
	if offer is Dictionary:
		return &"heal"
	return &"loot"


## Card content for an offer: {title, subtitle, icon, lines, notes, deltas, rows, hidden}.
##
## The three text blocks are kept apart on purpose. `lines` is what the offer *is* (an item's
## weapon block and affixes), `notes` are the strings attached to taking it (a curse, a shrine
## price, a reason it cannot be taken) and `deltas` is the vs-equipped comparison. `rows` is
## the render order with the rule and the "vs equipped" heading already in it, so the same
## "+2 Might" can never appear twice with nothing saying which is which.
##
## `against` is the thing this offer would displace, when the caller already knows it: the swap
## view hands in the card on the other side of the arrow, so the incoming ability prints its
## cooldown and damage before-and-after against the one being given up instead of leaving the
## player to subtract two subtitles. Null means "ask the board" (`context["equipped"]`), which
## is what an offer card on the three-card board does.
##
## `outgoing` marks the half of a trade the player is giving up, and it is the one card that
## must be described on its own terms: it is already worn, so it has no price to state and
## nothing to be compared against. Asking the board instead answers a question about the
## *incoming* item's slot - `Equipment.worn_for()` names Ring 1 whichever ring is on screen -
## which is how the trade view's second page came to print Ring 1's trade under Ring 2.
func describe_offer(offer: Variant, against: Variant = null, outgoing: bool = false) -> Dictionary:
	var out := {
		"title": "?",
		"subtitle": "",
		"icon": null,
		"lines": [],
		"notes": [],
		"deltas": [],
		"rows": [],
		"hidden": 0,
		"shape": -1,
		"replaces": ""
	}
	if offer is ItemInstance:
		var item := offer as ItemInstance
		out["title"] = item.display_name
		var pips := Accessibility.rarity_mark(item.rarity)
		out["subtitle"] = (
			"%s %s"
			% [ItemInstance.RARITY_NAMES[item.rarity], String(item.base.slot_name()).capitalize()]
		)
		if not pips.is_empty():
			out["subtitle"] = "%s %s" % [pips, out["subtitle"]]
		out["shape"] = Accessibility.rarity_shape(item.rarity)
		# Never `item.base.icon`: rings and trinkets author none and drew as an empty square.
		out["icon"] = ProcSprite.for_item(item)
		var lines: Array = []
		for line: String in ItemCard.item_lines(item):
			lines.append(line)
		out["lines"] = lines
		if against is ItemInstance:
			_fill_item_swap(item, against as ItemInstance, out)
		elif not outgoing:
			_describe_item_compare(item, out)
		# A cursed chest's prize is not free: the curse it attaches is stated on the card. The
		# price belongs to the prize, never to the gear the player is handing over for it.
		var curse_text := str(context.get("curse_text", ""))
		if not outgoing and not curse_text.is_empty():
			(out["notes"] as Array).push_front({"text": curse_text, "role": &"danger"})
	elif offer is Ability:
		var ability := offer as Ability
		out["title"] = ability.display_name
		if ability.tier > 1:
			out["title"] += " %s" % ["I", "II", "III"][clampi(ability.tier - 1, 0, 2)]
		out["subtitle"] = AbilityCard.subtitle_for(ability)
		out["icon"] = ability.icon
		out["lines"] = [ability.describe()]
		_describe_ability_compare(ability, against as Ability, out)
	elif offer is Dictionary:
		var d := offer as Dictionary
		var stat := StringName(str(d.get("stat", "might")))
		var points := int(d.get("points", 1))
		var stat_name := String(stat).capitalize()
		out["title"] = "+%d %s" % [points, stat_name]
		out["subtitle"] = "Stat orb"
		out["icon"] = UiTheme.icon(int(UiTheme.STAT_ICONS.get(stat, UiTheme.Icon.MIGHT)))
		var current: Dictionary = context.get("current_stats", {})
		if current.has(stat):
			var now := int(current[stat])
			out["lines"] = ["%s %d -> %d" % [stat_name, now, now + points]]
		else:
			out["lines"] = [ChestOffers.stat_blurb(stat)]
		# Shrine options (docs §8 "buff-for-a-cost") carry their own wording and a cost that
		# may be paid in HP or max HP; without this the card would render them as free.
		var label := str(d.get("label", ""))
		if not label.is_empty():
			out["title"] = label
			out["subtitle"] = "+%d %s" % [points, stat_name]
		var cost_text := str(d.get("cost_text", ""))
		if not cost_text.is_empty():
			(out["notes"] as Array).append({"text": cost_text, "role": &"danger"})
		# An option that cannot do anything (cleansing with no curse) says so on the card
		# rather than charging for nothing.
		var note := str(d.get("note", ""))
		if not note.is_empty():
			(out["notes"] as Array).append({"text": note, "role": &"danger"})
	elif offer is int or offer is float:
		out["title"] = "+%d gold" % int(offer)
		out["subtitle"] = "Gold"
		out["icon"] = UiTheme.icon(UiTheme.Icon.GOLD)
		out["lines"] = ["Straight to your purse."]
	# A card whose whole payload is inert for the worn weapon says so rather than looking like
	# a reward ("+1 projectile" on a sword). `weapon` is supplied by RunManager; without it no
	# card is ever judged inert.
	var inert := ChestOffers.inert_note(offer, context.get("weapon") as WeaponBase)
	if not inert.is_empty():
		(out["notes"] as Array).append({"text": inert, "role": &"dim"})
	_fill_rows(out)
	return out


## The vs-equipped block for an item card. With `context["equipped"]` the card knows whether
## the slot is empty — an empty slot has nothing to compare against, and printing the item's
## own affixes again as "deltas" is exactly the duplication that made the card unreadable.
func _describe_item_compare(item: ItemInstance, out: Dictionary) -> void:
	var lookup: Variant = context.get("equipped")
	if not (lookup is Callable and (lookup as Callable).is_valid()):
		# No lookup: the board cannot name what the item would displace, so it falls back to
		# the signed deltas and heads them with the old unnamed caption.
		var compare: Variant = context.get("compare")
		var raw: Variant = (compare as Callable).call(item) if compare is Callable else null
		var deltas := raw as Dictionary if raw is Dictionary else {}
		# No cap: `fit_rows` cuts the list where the card actually runs out of room.
		out["deltas"] = ItemCard.compare_rows(item, null, deltas, ItemCard.ALL_ROWS)
		return
	var current := (lookup as Callable).call(item) as ItemInstance
	if current == null:
		(out["notes"] as Array).append({"text": ItemCard.EMPTY_SLOT_NOTE, "role": &"dim"})
		return
	_fill_item_swap(item, current, out)


## The before/after block for an item trade: every row there is, headed by the name of the
## gear that comes off. The cut happens in `fit_rows`, against the space the card really has.
func _fill_item_swap(item: ItemInstance, current: ItemInstance, out: Dictionary) -> void:
	# The worn item described against itself is not a comparison: the swap view shows it on the
	# left with its own numbers, and "Replaces Rusty Sword: Damage 8 -> 8" is noise.
	if current == null or current == item:
		return
	out["replaces"] = ItemCard.worn_name(current)
	var rows: Array = []
	for row: Dictionary in ItemCard.all_swap_rows(item, current):
		rows.append({"text": ItemCard.swap_text(row), "role": StringName(str(row["role"]))})
	out["deltas"] = rows


## The before/after block for an ability trade. Only ever filled when the caller knows what is
## being given up (the swap view): an ability card on the board displaces nothing yet, and a
## comparison against a slot the player has not chosen would be a guess.
func _describe_ability_compare(ability: Ability, current: Ability, out: Dictionary) -> void:
	if current == null or current == ability:
		return
	var rows: Array = []
	for row: Dictionary in AbilityCard.all_swap_rows(ability, current):
		rows.append({"text": ItemCard.swap_text(row), "role": StringName(str(row["role"]))})
	if rows.is_empty():
		return
	out["replaces"] = current.display_name
	out["deltas"] = rows


## Renders `lines` + `notes` + (rule, "vs equipped", `deltas`) into `rows`, the exact order the
## card draws, and records in `hidden` how many rows were dropped before it got here.
func _fill_rows(out: Dictionary) -> void:
	var rows: Array[Dictionary] = []
	var lines: Array = out["lines"]
	for line: Variant in lines:
		rows.append({"text": str(line), "role": &""})
	for note: Dictionary in out["notes"] as Array:
		rows.append(note)
	# Rows above the rule are the offer's own; the card's tail row says where the rest of the
	# comparison is when the cut lands below it (`OfferCard.fill_body`).
	out["own_rows"] = rows.size()
	var deltas: Array = out["deltas"]
	if not deltas.is_empty():
		rows.append({"text": "", "role": &"rule"})
		rows.append({"text": ItemCard.compare_header(str(out["replaces"])), "role": &"dim"})
		for delta: Dictionary in deltas:
			rows.append(delta)
	out["rows"] = rows


func _build_cards(row: HBoxContainer, store: Array[PanelContainer], items: Array) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	store.clear()
	_card_tweens.clear()
	var infos := describe_all(items)
	_head_h = CardFit.head_height_for(infos, _card_w, MAX_CARD_HEIGHT)
	_card_h = CardFit.card_height_for(infos, _card_w, _head_h, CARD_SIZE.y, MAX_CARD_HEIGHT)
	for i in items.size():
		var price := price_for(i)
		var card := OfferCard.make(
			infos[i],
			border_role_for(items[i]),
			_card_w,
			_card_h,
			_head_h,
			"%dg" % price if price > 0 else "",
			&"loot" if can_pick(i) else &"danger"
		)
		card.gui_input.connect(_on_card_input.bind(i, false))
		row.add_child(card)
		OfferCard.fill_body(card, _head_h)
		store.append(card)


## Card width for `count` offers; shrinks so four cards still fit the screen.
static func card_width(count: int) -> float:
	var n := maxi(1, count)
	var room := (MAX_PANEL_WIDTH - PANEL_PAD * 2.0 - (n - 1) * CARD_GAP) / float(n)
	return minf(CARD_SIZE.x, floorf(room))


## One description per offer, in board order.
func describe_all(items: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for offer: Variant in items:
		out.append(describe_offer(offer))
	return out


func _on_card_input(event: InputEvent, index: int, replace_row: bool) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	var row: int = Row.REPLACE if replace_row else Row.OFFERS
	if _row == row and _col == index:
		activate()
	else:
		_row = row
		select(index)
