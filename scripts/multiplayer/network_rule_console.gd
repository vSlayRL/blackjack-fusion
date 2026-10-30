class_name NetworkRuleConsole
extends AcceptDialog
## One scrollable form for session money/length and next-deal rule preferences.

signal results_requested

var mode_select: OptionButton
var count_spin: SpinBox
var rounds_spin: SpinBox
var money_spin: SpinBox
var checks: Dictionary = {}
var note: Label
var active_label: Label
var results_button: Button
var scroll: ScrollContainer
var _settings_revision: int = -1
var _expected_session: int = -1
var _catalog: RuleManager = RuleManager.new()


func _ready() -> void:
	title = "Session & Rules Console"
	min_size = Vector2i(400, 320)
	exclusive = true
	dialog_hide_on_ok = false
	add_cancel_button("Cancel")
	results_button = add_button("View Results", false, "results")
	custom_action.connect(func(action: StringName):
		if action == &"results":
			hide()
			results_requested.emit())
	confirmed.connect(_apply)
	TableNetwork.changed.connect(_refresh_summary)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 14)
	scroll.add_child(layout)
	active_label = _label("", 19)
	layout.add_child(active_label)
	note = _label("")
	layout.add_child(note)
	layout.add_child(_label("Session", 20))
	rounds_spin = _spin(1, TableSession.MAX_ROUNDS, 1)
	money_spin = _spin(1, TableSession.MAX_STARTING_MONEY, 0.01)
	money_spin.prefix = "$"
	_field(layout, "Rounds in this session", rounds_spin)
	_field(layout, "Starting balance per player", money_spin)
	layout.add_child(_label("Every connected player enters at Start. Late arrivals spectate until the next session. Money and round limits stay locked during play."))
	layout.add_child(HSeparator.new())
	layout.add_child(_label("Round Rules", 20))
	mode_select = OptionButton.new()
	mode_select.add_item("Classic", RuleManager.RuleMode.OFF)
	mode_select.add_item("Random", RuleManager.RuleMode.RANDOM_SELECTED)
	mode_select.add_item("All Active (checked rules)", RuleManager.RuleMode.ALL_SELECTED)
	_field(layout, "Mode", mode_select)
	mode_select.item_selected.connect(func(_index: int): _refresh_summary())
	count_spin = _spin(1, 5, 1)
	_field(layout, "Random rules per round", count_spin)
	layout.add_child(_label("Random selects distinct checked rules, up to the available pool. Saved rule changes apply to the next deal and clear existing Ready confirmations."))
	for rule in _catalog.get_catalog():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		layout.add_child(row)
		var check := CheckBox.new()
		check.custom_minimum_size = Vector2(36, 36)
		check.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		check.tooltip_text = "Include " + rule.display_name
		row.add_child(check)
		checks[rule.rule_id] = check
		var detail := VBoxContainer.new()
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(detail)
		detail.add_child(_label(rule.display_name, 18))
		detail.add_child(_label(rule.description))


func open_console() -> void:
	if TableNetwork.state.is_empty():
		return
	var state := TableNetwork.state
	var config: Dictionary = state.configuration
	_settings_revision = state.settings_revision
	_expected_session = state.session.id
	rounds_spin.value = state.session.round_limit
	money_spin.value = state.session.starting_money
	mode_select.select(mode_select.get_item_index(config.mode))
	count_spin.value = config.random_count
	var host := multiplayer.is_server()
	mode_select.disabled = not host
	for id in checks:
		checks[id].set_pressed_no_signal(config.selected.has(id))
		checks[id].disabled = not host
	scroll.scroll_vertical = 0
	_refresh_summary()
	popup_centered_clamped(Vector2i(660, 620), 0.9)


func _refresh_summary() -> void:
	if active_label == null or TableNetwork.state.is_empty():
		return
	var state := TableNetwork.state
	var session: Dictionary = state.session
	var active: bool = session.status == "active"
	var host := multiplayer.is_server()
	active_label.text = "%d of %d rounds completed" % [session.completed, session.round_limit] if active or session.status == "finished" else "Set up the next competition"
	var names := PackedStringArray()
	for person in state.players:
		if person.connected:
			names.append(person.name)
	note.text = ("Money and length are locked; rules apply next deal. " if active else "Start commits session settings and rule preferences together. ") if host else "Only the host can change these settings. "
	note.text += "Players connected: " + ", ".join(names)
	rounds_spin.editable = host and not active
	money_spin.editable = host and not active
	count_spin.editable = host and mode_select.get_selected_id() == RuleManager.RuleMode.RANDOM_SELECTED
	results_button.visible = session.status == "finished"
	get_ok_button().text = ("Apply · Next Deal" if active else "Start Session") if host else "Close"


func _apply() -> void:
	if not multiplayer.is_server():
		hide()
		return
	var selected: Array[StringName] = []
	for id in checks:
		if checks[id].button_pressed:
			selected.append(id)
	var error := ""
	if TableNetwork.state.session.status == "active":
		error = TableNetwork.configure_rules(mode_select.get_selected_id(), selected, int(count_spin.value), _settings_revision)
	else:
		error = TableNetwork.start_configured_session(int(rounds_spin.value), money_spin.value, mode_select.get_selected_id(), selected, int(count_spin.value), _expected_session, _settings_revision)
	if error.is_empty():
		hide()
	else:
		note.text = error
		scroll.scroll_vertical = 0


func _spin(minimum: float, maximum: float, step_size: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step_size
	spin.custom_minimum_size.x = 165
	return spin


func _field(layout: VBoxContainer, caption: String, control: Control) -> void:
	var row := HBoxContainer.new()
	layout.add_child(row)
	row.add_child(_label(caption))
	row.add_child(control)


func _label(text: String, size_px: int = 16) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 1
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", size_px)
	return label
