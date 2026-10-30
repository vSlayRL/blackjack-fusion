extends PanelContainer
## Compact personal economy/actions; card totals and individual stakes stay on the table.

signal focus_requested
signal dealer_requested
signal info_requested
signal hide_requested
signal seat_requested

var balance_label: Label
var net_label: Label
var status_label: Label
var betting_row: HBoxContainer
var bet_spin: SpinBox
var ready_button: Button
var action_row: HBoxContainer
var actions: Dictionary = {}
var lift_button: Button
var info_button: Button
var hand_selector: OptionButton
var dealer_button: Button
var rules_label: Label
var rule_row: HBoxContainer
var reroll_selector: OptionButton
var reroll_button: Button
var second_chance_button: Button
var mystery_row: HBoxContainer
var keep_button: Button
var replace_button: Button
var seat_button: Button
var replace_selected_button: Button
var selection_row: HBoxContainer
var _selecting_reroll: bool = false
var _selected_card: int = -1
var _bet_session: int = -1
var _reroll_context: String = ""
var _catalog: RuleManager = RuleManager.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 16
	offset_right = -16
	offset_top = -260
	offset_bottom = -16
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 5)
	add_child(layout)
	# Flow wraps complete controls instead of squeezing button labels in small windows.
	var stats := HFlowContainer.new()
	stats.add_theme_constant_override("h_separation", 6)
	stats.add_theme_constant_override("v_separation", 5)
	layout.add_child(stats)
	var money := HBoxContainer.new()
	money.add_theme_constant_override("separation", 16)
	money.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(money)
	balance_label = _label("Balance $100.00", 22)
	balance_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	balance_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money.add_child(balance_label)
	net_label = _label("", 22)
	net_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	money.add_child(net_label)
	var focus := _button("Table [C]", func(): focus_requested.emit())
	stats.add_child(focus)
	dealer_button = _button("Raise Dealer Cards [D]", func(): dealer_requested.emit())
	stats.add_child(dealer_button)
	lift_button = _button("Lift My Cards [V]", TableNetwork.toggle_lift)
	stats.add_child(lift_button)
	hand_selector = OptionButton.new()
	hand_selector.focus_mode = Control.FOCUS_NONE
	hand_selector.item_selected.connect(func(index: int): TableNetwork.request_lift(true, index))
	stats.add_child(hand_selector)
	info_button = _button("Info: Faint [L]", func(): info_requested.emit())
	stats.add_child(info_button)
	stats.add_child(_button("HUD [H]", func(): hide_requested.emit()))
	seat_button = _button("Leave Seat [G]", func(): seat_requested.emit())
	stats.add_child(seat_button)
	status_label = _label("Classic · Sit to play", 16)
	status_label.max_lines_visible = 2
	layout.add_child(status_label)
	rules_label = _label("", 15)
	rules_label.max_lines_visible = 2
	layout.add_child(rules_label)
	betting_row = HBoxContainer.new()
	layout.add_child(betting_row)
	var bet_caption := _label("Bet $", 18)
	bet_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	betting_row.add_child(bet_caption)
	bet_spin = SpinBox.new()
	bet_spin.min_value = 1.0
	bet_spin.max_value = 1000000.0
	bet_spin.step = 0.01
	bet_spin.value = 10
	bet_spin.custom_minimum_size.x = 120
	bet_spin.get_line_edit().focus_mode = Control.FOCUS_CLICK
	# SpinBox evaluates submitted expressions first; release only after its deferred commit.
	bet_spin.get_line_edit().text_submitted.connect(_bet_submitted, CONNECT_DEFERRED)
	betting_row.add_child(bet_spin)
	ready_button = _button("Ready", _ready_pressed)
	ready_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	betting_row.add_child(ready_button)
	action_row = HBoxContainer.new()
	layout.add_child(action_row)
	var captions := {"hit": "Hit [Q]", "stand": "Stand [E]", "double": "Double [Z]", "split": "Split [X]"}
	for action in captions:
		var button := _button(captions[action], TableNetwork.request.bind(action, 0.0))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_row.add_child(button)
		actions[action] = button
	rule_row = HBoxContainer.new()
	layout.add_child(rule_row)
	reroll_button = _button("Reroll [R]", _reroll_pressed)
	reroll_button.custom_minimum_size = Vector2(180, 44)
	reroll_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule_row.add_child(reroll_button)
	second_chance_button = _button("Second Chance [T]", TableNetwork.request.bind("second_chance", 0.0))
	second_chance_button.custom_minimum_size.y = 44
	second_chance_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule_row.add_child(second_chance_button)
	selection_row = HBoxContainer.new()
	layout.add_child(selection_row)
	reroll_selector = OptionButton.new()
	reroll_selector.focus_mode = Control.FOCUS_NONE
	reroll_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reroll_selector.custom_minimum_size.x = 1
	reroll_selector.clip_text = true
	reroll_selector.item_selected.connect(_select_dropdown_card)
	selection_row.add_child(reroll_selector)
	replace_selected_button = _button("Replace Selected", _replace_selected)
	replace_selected_button.custom_minimum_size = Vector2(160, 44)
	selection_row.add_child(replace_selected_button)
	mystery_row = HBoxContainer.new()
	layout.add_child(mystery_row)
	keep_button = _button("Keep · Reveal [K]", TableNetwork.request.bind("keep_mystery", 0.0))
	replace_button = _button("Replace · Reveal [N]", TableNetwork.request.bind("replace_mystery", 0.0))
	for button in [keep_button, replace_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mystery_row.add_child(button)
	TableNetwork.changed.connect(refresh)
	minimum_size_changed.connect(_fit_height)
	refresh()


func _bet_submitted(_text: String) -> void:
	bet_spin.get_line_edit().release_focus()


## Keep the bottom edge fixed as optional rule controls appear or wrap in narrow windows.
func _fit_height() -> void:
	offset_top = -16.0 - get_combined_minimum_size().y


## Selection is local and free; only an explicit card click/confirmation sends an action.
func _reroll_pressed() -> void:
	if _selecting_reroll:
		cancel_reroll()
		return
	if not TableNetwork.local_record().get("can_reroll", false) or TableNetwork.pending:
		return
	_selecting_reroll = true
	_selected_card = -1
	_reroll_context = _selection_context()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()


func cancel_reroll() -> void:
	_selecting_reroll = false
	_selected_card = -1
	refresh()


func _selection_context() -> String:
	var record := TableNetwork.local_record()
	for index in range(record.get("hands", []).size()):
		if record.hands[index].active:
			return "%d:%d:%s" % [TableNetwork.state.round, index, str(record.hands[index].cards)]
	return ""


func active_reroll_hand() -> int:
	var record := TableNetwork.local_record()
	for index in range(record.get("hands", []).size()):
		if record.hands[index].active:
			return index
	return -1


func is_selecting_reroll() -> bool:
	return _selecting_reroll and not TableNetwork.pending and TableNetwork.local_record().get("can_reroll", false) and _selection_context() == _reroll_context


func _select_dropdown_card(index: int) -> void:
	# Item zero is a prompt, never an implicit choice of the first dealt card.
	_selected_card = index - 1
	replace_selected_button.disabled = not is_selecting_reroll() or _selected_card < 0


func _replace_selected() -> void:
	choose_reroll_card(active_reroll_hand(), _selected_card)


func choose_reroll_card(hand_index: int, card_index: int) -> bool:
	if not is_selecting_reroll() or hand_index != active_reroll_hand() or card_index < 0:
		return false
	var record := TableNetwork.local_record()
	if card_index >= record.hands[hand_index].cards.size():
		return false
	_selecting_reroll = false
	_selected_card = -1
	TableNetwork.request("reroll", 0.0, card_index)
	refresh()
	return true


## Match visible labels; disabled/out-of-turn actions and text-entry focus never submit.
func handle_shortcut(key: int) -> bool:
	if TableNetwork.local_record().get("seat", -1) < 0:
		return false
	if key == KEY_ESCAPE and _selecting_reroll:
		cancel_reroll()
		return true
	if key == KEY_R:
		_reroll_pressed()
		return true
	var button: Button
	match key:
		KEY_Q: button = actions.hit
		KEY_E: button = actions.stand
		KEY_Z: button = actions.double
		KEY_X: button = actions.split
		KEY_T: button = second_chance_button
		KEY_K: button = keep_button if mystery_row.visible else null
		KEY_N: button = replace_button if mystery_row.visible else null
		KEY_B: button = ready_button if betting_row.visible else null
		_: return false
	if button != null and not button.disabled:
		button.pressed.emit()
	return true


func set_info_caption(caption: String) -> void:
	info_button.text = "Info: " + caption + " [L]"


func _ready_pressed() -> void:
	var record := TableNetwork.local_record()
	TableNetwork.request("cancel" if record.get("ready", false) else "ready", bet_spin.value)


func refresh() -> void:
	var state := TableNetwork.state
	var record := TableNetwork.local_record()
	if record.is_empty() or state.is_empty():
		hide()
		return
	show()
	if _bet_session != state.session.id:
		_bet_session = state.session.id
		bet_spin.set_value_no_signal(record.bet)
	if _selecting_reroll and not is_selecting_reroll():
		_selecting_reroll = false
		_selected_card = -1
	balance_label.text = "Balance $%.2f" % record.balance
	net_label.text = "%s$%.2f" % ["+" if record.delta > 0 else ("−" if record.delta < 0 else ""), absf(record.delta)] if record.has_result else ""
	net_label.add_theme_color_override("font_color", Color("69eda4") if record.delta > 0 else (Color("ff7a8e") if record.delta < 0 else Color("b7cbd1")))
	var playing: bool = state.phase == "playing"
	var seated: bool = record.seat >= 0
	dealer_button.disabled = not seated or state.dealer.is_empty()
	betting_row.visible = seated and not playing and state.session.status == "active" and record.enrolled
	action_row.visible = seated and playing and not record.mystery_pending
	mystery_row.visible = seated and playing and record.mystery_pending
	keep_button.disabled = TableNetwork.pending or not record.can_keep_mystery
	replace_button.disabled = TableNetwork.pending or not record.can_replace_mystery
	bet_spin.editable = not record.ready and not TableNetwork.pending
	ready_button.disabled = TableNetwork.pending or not record.can_bet
	ready_button.text = "Cancel Ready [B]" if record.ready else "Ready · Next Deal [B]"
	for action in actions:
		actions[action].disabled = TableNetwork.pending or not record.can_act or _selecting_reroll
	actions.hit.disabled = TableNetwork.pending or not record.can_hit or _selecting_reroll
	actions.stand.disabled = TableNetwork.pending or not record.can_stand or _selecting_reroll
	actions.stand.text = ("Take Target Win [E]" if record.target_match else "Accept Bust [E]") if record.bust_pending else "Stand [E]"
	actions.double.disabled = actions.double.disabled or not record.can_double
	actions.split.disabled = actions.split.disabled or not record.can_split
	_refresh_rules(state, record)
	var lifted := TableNetwork.viewed_hand(multiplayer.get_unique_id())
	lift_button.text = "Lower My Cards [V]" if lifted >= 0 else "Lift My Cards [V]"
	lift_button.disabled = not seated or record.hands.is_empty()
	hand_selector.visible = lifted >= 0 and record.hands.size() > 1
	hand_selector.clear()
	for index in range(record.hands.size()):
		hand_selector.add_item("Hand %d" % (index + 1))
	if lifted >= 0:
		hand_selector.select(lifted)
	seat_button.text = "Leave Seat [G]" if seated else "Sit [G]"
	var text: String = state.message
	if not playing:
		var waiting := PackedStringArray()
		for person in state.players:
			if person.connected and person.enrolled and person.seat >= 0 and person.balance >= 1 and not person.ready:
				waiting.append(person.name)
		if not waiting.is_empty():
			text = "Waiting for ready: " + ", ".join(waiting)
	if not seated:
		text = "Sit in a chair to join the next deal. " + (state.message if playing else "")
	elif record.balance < 1.0 and not playing:
		text = "You need at least $1 to bet. You can keep watching the table."
	if state.session.status == "setup":
		text = "Open Console to choose rounds and starting money." if multiplayer.is_server() else "Waiting for the host to start a session."
	elif state.session.status == "finished":
		text = "Session complete · Open Console for final standings."
	elif not record.enrolled:
		text = "Spectating · You can enter when the host starts the next session."
	if playing and not record.rule_message.is_empty():
		text = record.rule_message + " " + text
	if _selecting_reroll:
		text = "Reroll: click a gold card, or choose below and Replace Selected. Esc / R cancels."
	var progress := "Session Setup" if state.session.status == "setup" else "Round %d of %d" % [maxi(1, state.session.current_round), state.session.round_limit]
	status_label.text = progress + " · " + text
	status_label.tooltip_text = status_label.text
	_fit_height()


func _refresh_rules(state: Dictionary, record: Dictionary) -> void:
	var names := PackedStringArray()
	for id in state.active_rules:
		var rule := _catalog.get_rule(id)
		var text := rule.display_name
		if id == &"double_target":
			text += ": %d" % state.target
		elif id == &"reroll":
			text += " (used)" if record.reroll_used else " (ready)"
		elif id == &"lucky_nine":
			for hand in record.hands:
				if hand.lucky_nine_qualified:
					text += " (qualified · +$%.2f on a win)" % hand.lucky_nine_bonus
		elif id == &"second_chance":
			text += " (used)" if record.second_chance_used else " (ready)"
		names.append(text)
	rules_label.text = "This round · " + ("Classic" if names.is_empty() else ", ".join(names))
	if state.phase != "playing":
		var config: Dictionary = state.configuration
		var pool := PackedStringArray()
		for id in config.selected:
			pool.append(_catalog.get_rule(id).display_name)
		if config.mode == RuleManager.RuleMode.OFF or pool.is_empty():
			rules_label.text = "Next deal · Classic"
		else:
			rules_label.text = "Next deal · %s · %s" % ["Random %d" % mini(config.random_count, pool.size()) if config.mode == RuleManager.RuleMode.RANDOM_SELECTED else "All Active", ", ".join(pool)]
	rules_label.tooltip_text = rules_label.text
	var show_reroll: bool = state.phase == "playing" and record.seat >= 0 and not record.mystery_pending and state.active_rules.has(&"reroll")
	var show_second: bool = state.phase == "playing" and record.seat >= 0 and not record.mystery_pending and state.active_rules.has(&"second_chance")
	rule_row.visible = show_reroll or show_second
	reroll_button.visible = show_reroll
	second_chance_button.visible = show_second
	reroll_button.disabled = TableNetwork.pending or not record.can_reroll
	reroll_button.text = "Cancel Reroll [R]" if _selecting_reroll else ("Reroll Used [R]" if record.reroll_used else "Reroll [R]")
	second_chance_button.disabled = TableNetwork.pending or not record.can_second_chance or _selecting_reroll
	second_chance_button.text = "Recovery Used [T]" if record.second_chance_used else "Second Chance [T]"
	selection_row.visible = _selecting_reroll
	replace_selected_button.disabled = not is_selecting_reroll() or _selected_card < 0
	reroll_selector.clear()
	reroll_selector.add_item("Choose a card to replace…")
	var active_index := active_reroll_hand()
	if active_index >= 0:
		for index in range(record.hands[active_index].cards.size()):
			var code: Variant = record.hands[active_index].cards[index]
			reroll_selector.add_item("Card %d: %s" % [index + 1, "?" if code == null else ClassicTable.decode_card(code).get_card_name()])
	reroll_selector.select(clampi(_selected_card + 1, 0, reroll_selector.item_count - 1))


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 36
	button.pressed.connect(func():
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			focus.release_focus()
		action.call())
	return button


func _label(text: String, size_px: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 1
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size_px)
	return label
