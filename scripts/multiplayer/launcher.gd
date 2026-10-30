extends Control
## Entry point for the shared lounge and the existing Solo scenes.

var name_edit: LineEdit
var address_edit: LineEdit
var mode_select: OptionButton
var code_edit: LineEdit
var service_edit: LineEdit
var control_spin: SpinBox
var registrar_spin: SpinBox
var advanced_toggle: CheckButton
var advanced: VBoxContainer
var mode_hint: Label
var port_row: HBoxContainer
var port_spin: SpinBox
var host_button: Button
var join_button: Button
var cancel_button: Button
var status: Label
var _solo_buttons: Array[Button] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_menu()
	RoomNetwork.room_ready.connect(_enter_room)
	RoomNetwork.connection_ended.connect(_connection_ended)
	status.text = RoomNetwork.last_message if not RoomNetwork.last_message.is_empty() else "Host a room or paste a friend’s code to join."
	if RoomNetwork.active:
		_enter_room.call_deferred()


func _process(_delta: float) -> void:
	var busy := RoomNetwork.connecting
	host_button.disabled = busy
	join_button.disabled = busy
	name_edit.editable = not busy
	address_edit.editable = not busy
	port_spin.editable = not busy
	mode_select.disabled = busy
	code_edit.editable = not busy
	service_edit.editable = not busy
	control_spin.editable = not busy
	registrar_spin.editable = not busy
	advanced_toggle.disabled = busy
	cancel_button.visible = busy
	for button in _solo_buttons:
		button.disabled = busy
	if busy:
		status.text = RoomNetwork.last_message


func _host() -> void:
	var result := RoomNetwork.host_online(name_edit.text, service_edit.text, int(control_spin.value), int(registrar_spin.value)) if mode_select.selected == 0 else RoomNetwork.host_room(name_edit.text, int(port_spin.value))
	if result != OK:
		status.text = RoomNetwork.last_message


func _join() -> void:
	var result := RoomNetwork.join_online(name_edit.text, code_edit.text, service_edit.text, int(control_spin.value), int(registrar_spin.value)) if mode_select.selected == 0 else RoomNetwork.join_room(name_edit.text, address_edit.text, int(port_spin.value))
	status.text = RoomNetwork.last_message
	if result != OK:
		status.text = RoomNetwork.last_message


func _cancel() -> void:
	RoomNetwork.leave_room()
	RoomNetwork.last_message = "Connection cancelled."
	status.text = RoomNetwork.last_message


func _connection_ended(message: String) -> void:
	status.text = message


func _enter_room() -> void:
	get_tree().change_scene_to_file.call_deferred("res://scenes/multiplayer/network_lounge.tscn")


func _solo(path: String) -> void:
	RoomNetwork.leave_room()
	get_tree().change_scene_to_file(path)


## One scrollable form keeps Host/Join usable at the project's minimum window size.
func _build_menu() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("08141d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 28)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 520
	center.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	panel.add_child(layout)
	layout.add_child(_label("BLACKJACK FUSION", 32, Color("effaff")))
	layout.add_child(_label("Play Blackjack together in the space lounge.", 16, Color("b8cad3")))
	name_edit = _field(layout, "Player name", "Player", "Your display name")
	name_edit.max_length = 20
	mode_select = OptionButton.new()
	mode_select.add_item("Online · Room Code")
	mode_select.add_item("LAN / Direct IP")
	mode_select.item_selected.connect(_mode_changed)
	layout.add_child(mode_select)
	mode_hint = _label("", 15, Color("b8cad3"))
	layout.add_child(mode_hint)
	code_edit = _field(layout, "Room code", "", "Paste the host’s full room code")
	code_edit.max_length = 99
	address_edit = _field(layout, "Host IP address", "127.0.0.1", "Example: 192.168.1.20")
	address_edit.tooltip_text = "Use 127.0.0.1 for a second window on this computer. For another computer, use the host's LAN address."
	var row := HBoxContainer.new()
	port_row = row
	layout.add_child(row)
	var port_label := _label("Port", 16, Color("d0e2e9"))
	port_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(port_label)
	port_spin = SpinBox.new()
	port_spin.min_value = 1024
	port_spin.max_value = 65535
	port_spin.step = 1
	port_spin.value = RoomNetwork.DEFAULT_PORT
	port_spin.custom_minimum_size.x = 140
	row.add_child(port_spin)
	advanced_toggle = CheckButton.new()
	advanced_toggle.text = "Advanced online settings"
	layout.add_child(advanced_toggle)
	advanced = VBoxContainer.new()
	layout.add_child(advanced)
	advanced_toggle.toggled.connect(func(expanded: bool): advanced.visible = expanded)
	service_edit = _field(advanced, "Service", OnlineConnection.DEFAULT_SERVICE, "Your Noray service hostname")
	control_spin = _port_field(advanced, "Control port", OnlineConnection.DEFAULT_CONTROL_PORT)
	registrar_spin = _port_field(advanced, "Registrar port", OnlineConnection.DEFAULT_REGISTRAR_PORT)
	advanced.add_child(_label("The default is a shared development relay; availability and capacity may vary. A team-owned service can be entered here.", 14, Color("b8cad3")))
	advanced.hide()
	# Keep connection status, Cancel and primary actions outside the settings scroll.
	var footer_center := CenterContainer.new()
	body.add_child(footer_center)
	var footer_panel := PanelContainer.new()
	footer_panel.custom_minimum_size.x = 520
	footer_center.add_child(footer_panel)
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	footer_panel.add_child(footer)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	footer.add_child(buttons)
	host_button = _button("Host Room", _host)
	join_button = _button("Join Room", _join)
	buttons.add_child(host_button)
	buttons.add_child(join_button)
	cancel_button = _button("Cancel Connection", _cancel)
	cancel_button.hide()
	footer.add_child(cancel_button)
	status = _label("", 15, Color("f1cc81"))
	status.custom_minimum_size.y = 34
	status.max_lines_visible = 3
	footer.add_child(status)
	footer.add_child(HSeparator.new())
	var solo := HBoxContainer.new()
	solo.add_theme_constant_override("separation", 12)
	footer.add_child(solo)
	var solo_room := _button("Solo 3D", _solo.bind("res://scenes/room/space_lounge.tscn"))
	var solo_2d := _button("Solo 2D", _solo.bind("res://scenes/game.tscn"))
	solo.add_child(solo_room)
	solo.add_child(solo_2d)
	_solo_buttons.assign([solo_room, solo_2d])
	var menu_theme := Theme.new()
	menu_theme.default_font_size = 18
	var style := StyleBoxFlat.new()
	style.bg_color = Color("102832")
	style.border_color = Color("3ea8b9")
	style.border_width_left = 2
	style.set_corner_radius_all(10)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	menu_theme.set_stylebox("panel", "PanelContainer", style)
	var footer_style := style.duplicate() as StyleBoxFlat
	footer_style.content_margin_top = 10
	footer_style.content_margin_bottom = 10
	footer_panel.add_theme_stylebox_override("panel", footer_style)
	menu_theme.set_color("font_color", "LineEdit", Color("ecf8fd"))
	menu_theme.set_font_size("font_size", "Button", 18)
	theme = menu_theme
	_mode_changed(0)


func _field(parent: VBoxContainer, caption: String, initial: String, placeholder: String) -> LineEdit:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(caption, 16, Color("d0e2e9"))
	label.custom_minimum_size.x = 125
	row.add_child(label)
	var field := LineEdit.new()
	field.text = initial
	field.placeholder_text = placeholder
	field.custom_minimum_size.y = 40
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return field


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	return button


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 1
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 3
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _mode_changed(index: int) -> void:
	var online := index == 0
	code_edit.get_parent().visible = online
	address_edit.get_parent().visible = not online
	port_row.visible = not online
	advanced_toggle.visible = online
	advanced.visible = online and advanced_toggle.button_pressed
	host_button.text = "Host Online Room" if online else "Host LAN Room"
	join_button.text = "Join by Code" if online else "Join by IP"
	mode_hint.text = "Share a room code to play across networks." if online else "Use 127.0.0.1 for this PC, or the host’s LAN address for another PC on your network."


func _port_field(parent: VBoxContainer, caption: String, initial: int) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(caption, 16, Color("d0e2e9"))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var field := SpinBox.new()
	field.min_value = 1024
	field.max_value = 65535
	field.value = initial
	row.add_child(field)
	return field
