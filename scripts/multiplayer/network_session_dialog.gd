class_name NetworkSessionDialog
extends AcceptDialog
## Final session results. All setup lives in the unified physical-console form.

signal setup_requested

var note: Label
var summary: Label
var board: GridContainer
var new_button: Button
var winner_label: Label
var results_view: bool = true


func _ready() -> void:
	title = "Session Results"
	min_size = Vector2i(500, 300)
	exclusive = true
	dialog_hide_on_ok = false
	get_ok_button().text = "Back to Room"
	confirmed.connect(hide)
	new_button = add_button("New Session", false, "new_session")
	custom_action.connect(func(action: StringName):
		if action == &"new_session":
			hide()
			setup_requested.emit())
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 12)
	scroll.add_child(layout)
	summary = _label("", 19)
	layout.add_child(summary)
	note = _label("")
	layout.add_child(note)
	winner_label = _label("", 21)
	winner_label.add_theme_color_override("font_color", Color("f3d581"))
	layout.add_child(winner_label)
	board = GridContainer.new()
	board.columns = 5
	board.add_theme_constant_override("h_separation", 10)
	board.add_theme_constant_override("v_separation", 12)
	layout.add_child(board)
	TableNetwork.changed.connect(refresh)


func open_results() -> void:
	if TableNetwork.state.get("session", {}).get("status", "setup") != "finished":
		return
	refresh()
	popup_centered_clamped(Vector2i(720, 480), 0.9)


func refresh() -> void:
	if summary == null or TableNetwork.state.is_empty():
		return
	var session: Dictionary = TableNetwork.state.session
	new_button.visible = multiplayer.is_server() and session.status == "finished"
	if session.status != "finished":
		return
	summary.text = "%d of %d rounds completed" % [session.completed, session.round_limit]
	note.text = session.reason
	for child in board.get_children():
		board.remove_child(child)
		child.queue_free()
	var headings := ["Place", "Player Name", "Starting\nBalance", "Ending\nBalance", "Net Profit"]
	var widths := [44.0, 80.0, 96.0, 96.0, 96.0]
	for index in range(headings.size()):
		var label := _label(headings[index])
		label.custom_minimum_size.x = widths[index]
		if index == 1:
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		board.add_child(label)
	var winners := PackedStringArray()
	for entry in session.standings:
		if entry.place == 1:
			winners.append(entry.name)
		var place := _label("#%d" % entry.place)
		place.custom_minimum_size.x = 44
		place.autowrap_mode = TextServer.AUTOWRAP_OFF
		board.add_child(place)
		var name_text: String = entry.name + (" (You)" if entry.id == multiplayer.get_unique_id() else "")
		if not entry.connected:
			name_text += " (left)"
		var player_label := _label(name_text)
		player_label.custom_minimum_size.x = 80
		player_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		board.add_child(player_label)
		board.add_child(_cash(entry.starting_balance))
		board.add_child(_cash(entry.balance))
		var net: float = entry.net
		var result := _cash(absf(net))
		result.text = ("+" if net > 0 else ("−" if net < 0 else "")) + result.text
		result.add_theme_color_override("font_color", Color("69eda4") if net > 0 else (Color("ff7a8e") if net < 0 else Color("b7cbd1")))
		board.add_child(result)
	winner_label.text = ("Winners · " if winners.size() > 1 else "Winner · ") + ", ".join(winners)


func _cash(amount: float) -> Label:
	var label := _label("$%.2f" % amount)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size.x = 96
	return label


func _label(text: String, size_px: int = 16) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 1
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size_px)
	return label
