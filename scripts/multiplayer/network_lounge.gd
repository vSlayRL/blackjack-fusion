extends Node3D
## Shared lounge and session table. Movement and table decisions use independent services.

const AVATAR: PackedScene = preload("res://scenes/multiplayer/network_avatar.tscn")

var avatars: Dictionary = {}
var local_avatar: RoomExplorer
var _send_elapsed: float = 0.0
var _notice_until: int = 0
var _notice: String = ""
var _target_seat: int = -1
var _title: Label
var _roster: Label
var _hint: Label
var _hint_panel: PanelContainer
var _dot: Label
var _hud: Control
var table_view: Node3D
var table_hud: PanelContainer
var header_panel: PanelContainer
var _restore_hud: Button
var _dealer_raised: bool = false
var _dealer_round: int = -1
var rule_console: NetworkRuleConsole
var session_dialog: NetworkSessionDialog
var leaderboard: NetworkLeaderboard
var _finished_session: int = -1
var _dealer_session: int = -1


func _ready() -> void:
	if not RoomNetwork.active:
		get_tree().change_scene_to_file.call_deferred("res://scenes/multiplayer/launcher.tscn")
		return
	RoomNetwork.roster_changed.connect(_sync_roster)
	RoomNetwork.poses_changed.connect(_sync_poses)
	RoomNetwork.teleported.connect(_teleport_local)
	RoomNetwork.notice_received.connect(_show_notice)
	RoomNetwork.connection_ended.connect(_connection_ended)
	TableNetwork.notice_received.connect(_show_notice)
	_build_hud()
	_sync_roster()
	rule_console = NetworkRuleConsole.new()
	rule_console.theme = _hud.theme
	add_child(rule_console)
	rule_console.visibility_changed.connect(_console_visibility_changed)
	session_dialog = NetworkSessionDialog.new()
	session_dialog.theme = _hud.theme
	add_child(session_dialog)
	session_dialog.visibility_changed.connect(_console_visibility_changed)
	session_dialog.setup_requested.connect(open_rules)
	rule_console.results_requested.connect(open_results)
	TableNetwork.changed.connect(_session_changed)
	TableNetwork.changed.connect(_refresh_console)
	_refresh_console()
	get_viewport().size_changed.connect(_refresh_heading)
	table_view = Node3D.new()
	table_view.set_script(preload("res://scripts/multiplayer/network_table_view.gd"))
	add_child(table_view)
	table_hud = PanelContainer.new()
	table_hud.set_script(preload("res://scripts/multiplayer/network_table_hud.gd"))
	_hud.add_child(table_hud)
	table_hud.focus_requested.connect(_focus_cards)
	table_hud.dealer_requested.connect(_toggle_dealer_cards)
	TableNetwork.changed.connect(_dealer_cards_changed)
	_dealer_cards_changed()
	table_hud.info_requested.connect(_cycle_info)
	table_hud.hide_requested.connect(toggle_hud)
	table_hud.seat_requested.connect(_sit_or_leave)
	for child in $Environment/Furniture/BlackjackTable.get_children():
		if child.name.begins_with("Chips") or child.name in [&"TableTitle", &"TableSubtitle"]:
			child.hide()
	leaderboard = preload("res://scenes/multiplayer/network_leaderboard.tscn").instantiate() as NetworkLeaderboard
	$Environment/Furniture.add_child(leaderboard)
	ToyNetwork.attach($Environment/TableToys)
	_session_changed()


## Reconcile by stable peer ID: reconnecting never reuses a departed avatar or seat.
func _sync_roster() -> void:
	for id in avatars.keys():
		if not RoomNetwork.players.has(id):
			avatars[id].queue_free()
			avatars.erase(id)
	for id in RoomNetwork.players:
		var record: Dictionary = RoomNetwork.players[id]
		if not avatars.has(id):
			var avatar := AVATAR.instantiate()
			avatar.name = "Player_%d" % id
			avatar.peer_id = id
			avatar.local_player = id == multiplayer.get_unique_id()
			$Players.add_child(avatar)
			avatar.teleport_to(record.position, record.yaw, record.pitch, record.seat)
			avatars[id] = avatar
			if avatar.local_player:
				local_avatar = avatar
				avatar.interact_requested.connect(_interact)
				avatar.seat_requested.connect(_sit_or_leave)
				avatar.reset_requested.connect(RoomNetwork.request_reset)
		avatars[id].update_record(record)
	_refresh_heading()


func _sync_poses() -> void:
	for id in avatars:
		if id != multiplayer.get_unique_id() and RoomNetwork.players.has(id):
			avatars[id].update_record(RoomNetwork.players[id])


func _physics_process(delta: float) -> void:
	if local_avatar == null or not RoomNetwork.active:
		return
	_send_elapsed += delta
	if _send_elapsed >= 0.05:
		_send_elapsed = 0.0
		RoomNetwork.send_pose(local_avatar.position, local_avatar.rotation.y, local_avatar.camera.rotation.x)


func _process(_delta: float) -> void:
	if local_avatar == null:
		return
	_dot.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_dot.position = get_viewport().get_visible_rect().size / 2.0 - Vector2(6, 20)
	_target_seat = _find_seat()
	var seated: bool = local_avatar.seat_index >= 0
	if table_hud != null:
		table_hud.seat_button.disabled = not seated and _target_seat < 0
	_hint.text = ""
	if Time.get_ticks_msec() < _notice_until:
		_hint.text = _notice
	elif not _toy_hint().is_empty():
		_hint.text = _toy_hint()
	elif not seated and _near_console():
		_hint.text = "Rule Console [E] · " + ("Configure next deal" if multiplayer.is_server() else "View table settings")
	elif not seated and _target_seat >= 0:
		var seat_peer := RoomNetwork.seat_owner(_target_seat)
		_hint.text = "Sit [G] · Chair %d" % (_target_seat + 1) if seat_peer == 0 else "Chair %d · occupied by %s" % [_target_seat + 1, RoomNetwork.players[seat_peer].name]
	_hint_panel.visible = not _hint.text.is_empty()
	if _hint_panel.visible and table_hud != null:
		var edge: float = table_hud.get_global_rect().position.y - 8.0
		_hint_panel.offset_bottom = edge - get_viewport().get_visible_rect().size.y
		_hint_panel.offset_top = _hint_panel.offset_bottom - _hint_panel.get_combined_minimum_size().y
	if table_view != null:
		var hovered: TableCard3D
		if table_hud.is_selecting_reroll() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			hovered = table_view.pick_card(get_viewport().get_mouse_position())
		table_view.hover_card(hovered)


func _find_seat() -> int:
	var best := -1
	var distance := 2.3
	for index in range(RoomNetwork.SEATS.size()):
		var point: Vector3 = RoomNetwork.SEATS[index] + Vector3(0, 0.5, 0)
		var offset := point - local_avatar.camera.global_position
		var flat := Vector2(offset.x, offset.z).length()
		if flat < distance and -local_avatar.camera.global_basis.z.dot(offset.normalized()) > 0.25:
			best = index
			distance = flat
	return best


## Walking E opens the console. Seating has its own G shortcut/button.
func _interact() -> void:
	if not _modal_open() and local_avatar.seat_index < 0 and _near_console():
		open_rules()


func _sit_or_leave() -> void:
	if _modal_open():
		return
	table_hud.cancel_reroll()
	if local_avatar.seat_index >= 0:
		RoomNetwork.request_seat(-1)
	else:
		var index := _find_seat()
		if index >= 0:
			RoomNetwork.request_seat(index)


func _unhandled_input(event: InputEvent) -> void:
	if _modal_open():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var held := ToyNetwork.held_by(multiplayer.get_unique_id())
		if table_hud.is_selecting_reroll() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			var card: TableCard3D = table_view.pick_card(event.position)
			if card != null:
				table_hud.choose_reroll_card(card.hand_index, card.card_index)
			get_viewport().set_input_as_handled()
		elif held >= 0:
			ToyNetwork.request("throw", held)
			get_viewport().set_input_as_handled()
		else:
			var screen: Vector2 = get_viewport().get_visible_rect().size / 2.0 if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else event.position
			var toy := ToyNetwork.pick(local_avatar.camera, screen)
			if toy >= 0:
				ToyNetwork.request("push", toy)
				get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return
		if table_hud.handle_shortcut(event.physical_keycode):
			get_viewport().set_input_as_handled()
			return
		match event.physical_keycode:
			KEY_F:
				var held := ToyNetwork.held_by(multiplayer.get_unique_id())
				ToyNetwork.request("drop" if held >= 0 else "grab", held if held >= 0 else _aimed_toy())
				get_viewport().set_input_as_handled()
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_C: _focus_cards()
			KEY_D:
				if local_avatar != null and local_avatar.seat_index >= 0:
					_toggle_dealer_cards()
			KEY_V: TableNetwork.toggle_lift()
			KEY_L: _cycle_info()
			KEY_H: toggle_hud()


func _near_console() -> bool:
	if local_avatar == null or local_avatar.seat_index >= 0:
		return false
	var offset: Vector3 = $Environment/Furniture/RuleScreenText.global_position - local_avatar.camera.global_position
	return Vector2(offset.x, offset.z).length() < 2.3 and -local_avatar.camera.global_basis.z.dot(offset.normalized()) > 0.25


func _modal_open() -> bool:
	return (rule_console != null and rule_console.visible) or (session_dialog != null and session_dialog.visible)


func open_results() -> void:
	if session_dialog == null:
		return
	if table_hud != null:
		table_hud.cancel_reroll()
	rule_console.hide()
	session_dialog.open_results()


## Auto-open once per finished session; players can close and reopen results from the header.
func _session_changed() -> void:
	if session_dialog == null or TableNetwork.state.is_empty():
		return
	var session: Dictionary = TableNetwork.state.session
	if session.status == "finished" and _finished_session != session.id:
		_finished_session = session.id
		if table_hud != null:
			table_hud.cancel_reroll()
		rule_console.hide()
		session_dialog.open_results()
	elif session.status == "active" and session_dialog.visible and session_dialog.results_view:
		session_dialog.hide()


func open_rules() -> void:
	if rule_console != null:
		if session_dialog != null:
			session_dialog.hide()
		if table_hud != null:
			table_hud.cancel_reroll()
		rule_console.open_console()


func _console_visibility_changed() -> void:
	if local_avatar != null:
		local_avatar.set_controls_enabled(not _modal_open())


func _refresh_console() -> void:
	if TableNetwork.state.is_empty():
		return
	var config: Dictionary = TableNetwork.state.configuration
	var text := "CLASSIC"
	if config.mode != RuleManager.RuleMode.OFF and not config.selected.is_empty():
		text = "RANDOM · %d RULES" % mini(config.random_count, config.selected.size()) if config.mode == RuleManager.RuleMode.RANDOM_SELECTED else "ALL CHECKED · %d RULES" % config.selected.size()
	var session: Dictionary = TableNetwork.state.session
	var progress := "%d / %d ROUNDS" % [session.completed, session.round_limit] if session.status == "active" else ("SESSION COMPLETE" if session.status == "finished" else "HOST: START A SESSION")
	$Environment/Furniture/RuleScreenText.text = "SESSION & RULES\n" + progress + "\n" + text + "\n[E] SETTINGS"


func _cycle_info() -> void:
	table_view.cycle_info()
	table_hud.set_info_caption(table_view.info_caption())


func toggle_hud() -> void:
	table_hud.cancel_reroll()
	_hud.visible = not _hud.visible
	_restore_hud.visible = not _hud.visible
	if not _hud.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _focus_cards() -> void:
	if local_avatar == null or local_avatar.seat_index < 0:
		return
	_set_dealer_raised(false)
	local_avatar._update_fov()
	var target := Vector3(0, 1.15, 0.25) - local_avatar.camera.global_position
	local_avatar.rotation.y = atan2(-target.x, -target.z)
	local_avatar.camera.rotation.x = atan2(target.y, Vector2(target.x, target.z).length())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _toggle_dealer_cards() -> void:
	if local_avatar == null or local_avatar.seat_index < 0 or TableNetwork.state.get("dealer", []).is_empty():
		_show_notice("Sit down and deal a round to view the dealer cards.")
		return
	_set_dealer_raised(not _dealer_raised)


## This preference stays in the local scene: no RPC, player pose or camera change.
func _set_dealer_raised(raised: bool) -> void:
	_dealer_raised = raised
	if table_view != null:
		table_view.dealer_raised = raised
	if table_hud != null:
		table_hud.dealer_button.text = "Lower Dealer Cards [D]" if raised else "Raise Dealer Cards [D]"


func _dealer_cards_changed() -> void:
	var round_id: int = TableNetwork.state.get("round", -1)
	var session_id: int = TableNetwork.state.get("session", {}).get("id", -1)
	if round_id != _dealer_round or session_id != _dealer_session:
		_dealer_round = round_id
		_dealer_session = session_id
		_set_dealer_raised(false)


func _teleport_local(location: Vector3, yaw: float, pitch: float, seat: int) -> void:
	if local_avatar != null:
		_set_dealer_raised(false)
		local_avatar.teleport_to(location, yaw, pitch, seat)


func _show_notice(message: String) -> void:
	_notice = message
	_notice_until = Time.get_ticks_msec() + 3500


func _connection_ended(_message: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file.call_deferred("res://scenes/multiplayer/launcher.tscn")


func _leave() -> void:
	RoomNetwork.leave_room()
	RoomNetwork.last_message = "You left the room."
	_connection_ended("")


func _refresh_heading() -> void:
	_title.text = "BLACKJACK FUSION  ·  %s  ·  %d / %d PLAYERS" % ["HOST" if multiplayer.is_server() else "JOINED", RoomNetwork.players.size(), RoomNetwork.MAX_PLAYERS]
	var names := PackedStringArray()
	for record in RoomNetwork.players.values():
		var seated := "Chair %d" % (record.seat + 1) if record.seat >= 0 else "Walking"
		names.append("%s%s · %s" % [record.name, " (Host)" if record.id == 1 else "", seated])
	_roster.text = " · ".join(names)
	if multiplayer.is_server() and not RoomNetwork.online_room:
		_roster.tooltip_text = "Same computer: 127.0.0.1\nLAN addresses: %s\nPort: %d / UDP" % [", ".join(RoomNetwork.lan_addresses()), RoomNetwork.port]


## Compact room UI leaves the world visible and makes connection details easy to find.
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)
	var top := PanelContainer.new()
	header_panel = top
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 16
	_hud.add_child(top)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	top.add_child(layout)
	var row := HBoxContainer.new()
	layout.add_child(row)
	_title = _label("", 17)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_title)
	var rules_button := Button.new()
	rules_button.text = "Console"
	rules_button.focus_mode = Control.FOCUS_NONE
	rules_button.pressed.connect(open_rules)
	row.add_child(rules_button)
	var fullscreen := Button.new()
	fullscreen.focus_mode = Control.FOCUS_NONE
	fullscreen.text = "F11"
	fullscreen.disabled = Engine.is_embedded_in_editor()
	fullscreen.pressed.connect(DisplaySettings.toggle_fullscreen)
	row.add_child(fullscreen)
	var leave := Button.new()
	leave.focus_mode = Control.FOCUS_NONE
	leave.text = "Leave Room"
	leave.pressed.connect(_leave)
	row.add_child(leave)
	_roster = _label("", 15)
	layout.add_child(_roster)
	if RoomNetwork.online_room:
		var code_row := HBoxContainer.new()
		layout.add_child(code_row)
		var code_label := _label("Room code: " + RoomNetwork.room_code, 14)
		code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code_label.tooltip_text = RoomNetwork.room_code
		code_row.add_child(code_label)
		var copy := Button.new()
		copy.text = "Copy Code"
		copy.focus_mode = Control.FOCUS_NONE
		copy.pressed.connect(func():
			DisplayServer.clipboard_set(RoomNetwork.room_code)
			_show_notice("Room code copied."))
		code_row.add_child(copy)
	elif multiplayer.is_server():
		var candidates := RoomNetwork.lan_addresses()
		candidates.insert(0, "127.0.0.1 (this PC)")
		var address := _label("Join IP: %s   ·   Port %d" % [", ".join(candidates), RoomNetwork.port], 14)
		address.tooltip_text = "On this computer, join using 127.0.0.1. Other computers on the same LAN use a listed address."
		layout.add_child(address)
	var bottom := PanelContainer.new()
	_hint_panel = bottom
	_hud.add_child(bottom)
	bottom.hide()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.offset_top = -76
	bottom.offset_bottom = -16
	_hint = _label("", 16)
	bottom.add_child(_hint)
	_dot = _label("·", 28)
	_dot.autowrap_mode = TextServer.AUTOWRAP_OFF
	_dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_dot.position = get_viewport().get_visible_rect().size / 2.0 - Vector2(6, 20)
	_hud.add_child(_dot)
	var theme := Theme.new()
	theme.default_font_size = 16
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.02, 0.055, 0.075, 0.76)
	panel.border_color = Color("4bbdcd")
	panel.border_width_left = 2
	panel.content_margin_left = 14
	panel.content_margin_right = 14
	panel.content_margin_top = 10
	panel.content_margin_bottom = 10
	panel.set_corner_radius_all(6)
	theme.set_stylebox("panel", "PanelContainer", panel)
	_hud.theme = theme
	# Keep a restore control outside the hidden HUD so the mouse can bring it back.
	_restore_hud = Button.new()
	_restore_hud.text = "Show HUD [H]"
	_restore_hud.focus_mode = Control.FOCUS_NONE
	_restore_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_restore_hud.offset_left = -160
	_restore_hud.offset_right = -16
	_restore_hud.offset_top = 16
	_restore_hud.offset_bottom = 54
	_restore_hud.pressed.connect(toggle_hud)
	layer.add_child(_restore_hud)
	_restore_hud.hide()


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 1
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 3
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label


## Seated players aim with their cursor; mouse-look uses the center dot.
func _aimed_toy() -> int:
	if local_avatar == null or _modal_open():
		return -1
	var screen := get_viewport().get_visible_rect().size / 2.0 if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else get_viewport().get_mouse_position()
	return ToyNetwork.pick(local_avatar.camera, screen)


func _toy_hint() -> String:
	return "" if _modal_open() else ToyNetwork.hint(_aimed_toy())


func _exit_tree() -> void:
	ToyNetwork.detach()
