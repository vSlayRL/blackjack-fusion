class_name SpaceLounge
extends Node3D
## Connects room interactions and physical card views to one shared BlackjackGame in TableHUD.

enum RoomMode { WALKING, TABLE, CONSOLE }

const CARD_SCENE: PackedScene = preload("res://scenes/room/table_card.tscn")
const INTERACTION_DISTANCE: float = 2.3
const LOOK_SENSITIVITY: float = 0.003
const DEFAULT_PITCH: float = -0.60
const DEFAULT_FOV: float = 90.0

@export_range(1.5, 3.2, 0.05) var seated_eye_height: float = 2.45
@export_range(1.0, 3.0, 0.05) var seated_eye_distance: float = 1.8

var mode: RoomMode = RoomMode.WALKING
var _cards: Dictionary[String, TableCard3D] = {}
var _hand_labels: Array[Label3D] = []
var _label_plates: Array[MeshInstance3D] = []
var _last_game: BlackjackGame
var looking: bool = false
var held_prop: LoungeProp

@onready var explorer: RoomExplorer = $Explorer
@onready var hud: TableHUD = $HUD/TableHUD
@onready var table_camera: Camera3D = $TableCamera
@onready var card_root: Node3D = $TableCards
@onready var console_label: Label3D = $Furniture/RuleScreenText
@onready var interaction_note: Label = $HUD/ControlsPanel/Text/Note


## Share the HUD's engine, wire lifecycle events, and start in the walking view.
func _ready() -> void:
	hud.state_refreshed.connect(_refresh_world)
	hud.leave_requested.connect(leave_table)
	hud.focus_requested.connect(focus_table)
	hud.new_session_requested.connect(_open_session_setup)
	hud.modal_opened.connect(func():
		_set_looking(false)
		drop_prop())
	hud.rule_dialog.visibility_changed.connect(_on_console_visibility_changed)
	explorer.view_reset.connect(drop_prop)
	table_camera.position = Vector3(0, seated_eye_height, seated_eye_distance)
	focus_table()
	_refresh_world()
	_set_mode(RoomMode.WALKING)


## Update interaction hints and card highlights without overriding the seated camera.
func _process(_delta: float) -> void:
	if mode == RoomMode.WALKING:
		hud.look_reticle.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		var prop := pick_prop(_aim_position())
		var target := get_interaction_target()
		interaction_note.text = "E — Sit at the Blackjack table" if target == &"table" else ("E — Session settings" if target == &"console" else "Approach the lit console for session settings, or the front chair to play.")
		if prop != null and not prop.held:
			interaction_note.text = "F — Pick up · Click / E — " + prop.interaction_hint()
		if is_instance_valid(held_prop):
			interaction_note.text = "F — Drop held toy"
	elif mode == RoomMode.TABLE:
		hud.look_reticle.visible = looking
		var aim := _aim_position()
		var prop := pick_prop(aim)
		hud.look_hint.text = ("F: drop toy · RMB: look · C: cards") if is_instance_valid(held_prop) else (("F: pick up · Click / E: " + prop.interaction_hint()) if prop != null else ("Choose a gold card or use the dropdown · Esc: cancel" if hud._selecting_reroll else "Hold RMB: look · C: cards · F: grab/drop · Wheel: zoom"))
		var hovered := pick_card(aim) if hud._selecting_reroll and not looking else null
		for card in _cards.values():
			card.set_hovered(card == hovered)


## Right-drag captures look even over controls; releasing restores the clickable cursor.
func _input(event: InputEvent) -> void:
	if mode == RoomMode.WALKING and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var prop := pick_prop(_aim_position() if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else event.position)
		if prop != null and not prop.held:
			prop.interact(-explorer.camera.global_basis.z)
			get_viewport().set_input_as_handled()
		return
	if mode != RoomMode.TABLE:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_set_looking(event.pressed)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and looking:
		table_camera.rotation.y -= event.relative.x * LOOK_SENSITIVITY
		table_camera.rotation.x = clampf(table_camera.rotation.x - event.relative.y * LOOK_SENSITIVITY, deg_to_rad(-75.0), deg_to_rad(75.0))
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and looking:
		_set_looking(false)
		get_viewport().set_input_as_handled()


## Route world clicks, view shortcuts, and station interactions after GUI controls have priority.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E:
			try_interact()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F and mode != RoomMode.CONSOLE:
			toggle_pickup()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_C and mode == RoomMode.TABLE:
			focus_table()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and mode == RoomMode.TABLE:
			if hud._selecting_reroll:
				hud._selecting_reroll = false
				hud._refresh_ui()
			else:
				leave_table()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and mode == RoomMode.TABLE:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			table_camera.fov = clampf(table_camera.fov + (-3.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 3.0), 55.0, 100.0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT and not looking:
			var prop := pick_prop(event.position)
			if prop != null:
				prop.interact(-table_camera.global_basis.z)
				get_viewport().set_input_as_handled()
				return
			var card := pick_card(event.position)
			if card != null:
				hud._choose_reroll_card(card.hand_index, card.card_index)
				get_viewport().set_input_as_handled()


## Use the view center while looking and the free cursor while selecting world objects.
func _aim_position() -> Vector2:
	return get_viewport().get_visible_rect().size / 2.0 if looking or (mode == RoomMode.WALKING and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED) else get_viewport().get_mouse_position()


## Release mouse capture on mode changes, Escape, and application focus loss.
func _set_looking(enabled: bool) -> void:
	looking = enabled
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE


## Losing window focus must not leave the seated view stuck in mouse-look mode.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and looking:
		_set_looking(false)


## Find a close station in front of the walking camera so prompts require an intentional approach.
func get_interaction_target() -> StringName:
	if mode != RoomMode.WALKING:
		return &""
	var targets: Dictionary[StringName, Vector3] = {
		&"table": $TableInteraction.global_position,
		&"console": $ConsoleInteraction.global_position
	}
	var best: StringName = &""
	var best_distance := INTERACTION_DISTANCE
	for target in targets:
		var offset := targets[target] - explorer.camera.global_position
		var flat_distance := Vector2(offset.x, offset.z).length()
		if flat_distance <= best_distance and -explorer.camera.global_basis.z.dot(offset.normalized()) > 0.35:
			best = target
			best_distance = flat_distance
	return best


## Route interactions through the same proximity/phase guards used by the room prompts.
func try_interact() -> bool:
	var prop := pick_prop(_aim_position())
	if prop != null and prop.held:
		return true
	if prop != null and not prop.held:
		var camera := table_camera if mode == RoomMode.TABLE else explorer.camera
		prop.interact(-camera.global_basis.z)
		return true
	if mode == RoomMode.TABLE:
		return leave_table()
	match get_interaction_target():
		&"table":
			return sit_at_table()
		&"console":
			return open_console()
	return false


## Enter the seated perspective view without resetting chips, results, or saved rule settings.
func sit_at_table() -> bool:
	if mode != RoomMode.WALKING or get_interaction_target() != &"table":
		return false
	_set_mode(RoomMode.TABLE)
	table_camera.make_current()
	focus_table()
	hud._refresh_ui()
	return true


## Keep unfinished wagers at the table; returning to the room never recreates the game.
func leave_table() -> bool:
	if mode != RoomMode.TABLE or not hud.game.round_over:
		return false
	_set_mode(RoomMode.WALKING)
	explorer.camera.make_current()
	return true


## Open the familiar settings dialog from the physical console between rounds only.
func open_console() -> bool:
	if mode != RoomMode.WALKING or get_interaction_target() != &"console" or not hud.game.round_over:
		return false
	_set_mode(RoomMode.CONSOLE)
	hud._on_rules_pressed()
	return true


## The final-results New Session button opens setup without requiring a walk to the console.
func _open_session_setup() -> void:
	_set_mode(RoomMode.CONSOLE)
	hud._on_rules_pressed()


## Resume exploration after Apply, Cancel, the window close button, or Escape.
func _on_console_visibility_changed() -> void:
	if mode == RoomMode.CONSOLE and not hud.rule_dialog.visible:
		_set_mode(RoomMode.WALKING)
		_refresh_console()


## Keep room overlays, camera controls, and mouse ownership consistent across modes.
func _set_mode(next_mode: RoomMode) -> void:
	drop_prop()
	_set_looking(false)
	mode = next_mode
	explorer.set_controls_enabled(mode == RoomMode.WALKING)
	hud.show_table(mode == RoomMode.TABLE)
	$HUD/TitlePanel.visible = mode != RoomMode.TABLE
	$HUD/ControlsPanel.visible = mode == RoomMode.WALKING
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Pick one nearby toy at the aiming point; gameplay cards are never pickup targets.
func toggle_pickup() -> bool:
	if mode == RoomMode.CONSOLE:
		return false
	if is_instance_valid(held_prop):
		drop_prop()
		return true
	var prop := pick_prop(_aim_position())
	if prop == null:
		return false
	held_prop = prop
	held_prop.add_collision_exception_with(explorer)
	held_prop.grab(_hold_position())
	return true


## End the hold before changing cameras or resetting the walking position.
func drop_prop() -> void:
	if is_instance_valid(held_prop):
		held_prop.remove_collision_exception_with(explorer)
		held_prop.drop()
	held_prop = null


## Keep the target in front of the current view, pulled back from room surfaces.
func _hold_position() -> Vector3:
	var camera := table_camera if mode == RoomMode.TABLE else explorer.camera
	var start := camera.global_position
	var direction := -camera.global_basis.z
	var target := start + direction * 1.05
	var query := PhysicsRayQueryParameters3D.create(start, start + direction * 1.35, 1)
	query.exclude = [explorer.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var distance := maxf(0.0, start.distance_to(hit.position) - 0.3)
		target = start + direction * minf(1.05, distance)
	return target


## Update only the hold target; the toy's physics integration handles collisions and movement.
func _physics_process(_delta: float) -> void:
	if is_instance_valid(held_prop):
		var target := _hold_position()
		if held_prop.global_position.distance_to(target) > 3.5:
			drop_prop()
		else:
			held_prop.hold_target = target


## Synchronize physical cards and labels from engine state; reset visual slots after Restart.
func _refresh_world() -> void:
	if _last_game != hud.game:
		for card in _cards.values():
			card.queue_free()
		_cards.clear()
		_last_game = hud.game
	_refresh_console()
	var alive: Array[String] = []
	var delay := 0.0
	for index in range(hud.game.dealer.hand.cards.size()):
		var count := hud.game.dealer.hand.cards.size()
		var columns := maxi(2, int(ceil(count / 2.0))) if count > 6 else count
		var row := int(index / float(columns))
		var step := minf(0.58, 2.7 / maxf(1.0, columns - 1.0))
		var target := Vector3((index % columns - (columns - 1) / 2.0) * step, 1.155 + index * 0.002, -1.5 + row * 0.3)
		var key := "dealer:%d" % index
		_show_card(key, hud.game.dealer.hand.cards[index], index == 1 and not hud.game.round_over, false, -1, index, target, 0.88, delay)
		alive.append(key)
		delay += 0.035
	var hand_count := hud.game.player.hands.size()
	for hand_index in range(hand_count):
		var played_hand := hud.game.player.hands[hand_index]
		var center := _hand_center(hand_index, hand_count)
		var count := played_hand.hand.cards.size()
		var columns := count if count <= 5 else int(ceil(count / 2.0))
		var width := 3.6 if hand_count == 1 else 1.7
		var step := minf(0.6 if hand_count == 1 else 0.4, width / maxf(1.0, columns - 1.0))
		for index in range(count):
			var row := int(index / float(columns))
			var target := center + Vector3((index % columns - (columns - 1) / 2.0) * step, 1.16 + index * 0.002, row * 0.3)
			var key := "player:%d:%d" % [hand_index, index]
			var selectable := hud._selecting_reroll and hand_index == hud.game.player.active_hand_index
			_show_card(key, played_hand.hand.cards[index], hud.game.is_player_card_hidden(hand_index, index), selectable, hand_index, index, target, 0.95 if hand_count == 1 else 0.72, delay)
			alive.append(key)
			delay += 0.035
	for key in _cards.keys():
		if not alive.has(key):
			_cards[key].queue_free()
			_cards.erase(key)
	_refresh_hand_labels()
	var table := $Furniture/BlackjackTable
	for child in table.get_children():
		if child.name.begins_with("Chips") or child.name in [&"TableTitle", &"TableSubtitle"]:
			child.visible = hud.game.player.hand.cards.is_empty()


## Use two columns and two rows for up to four hands, keeping every hand on the tabletop.
func _hand_center(index: int, count: int) -> Vector3:
	if count == 1:
		return Vector3(0, 0, -0.02)
	return Vector3(-1.08 if index % 2 == 0 else 1.08, 0, -0.64 if count > 2 and index < 2 else 0.09)


## Create or update a slot, storing indices only for legal card selection.
func _show_card(key: String, card: Card, is_concealed: bool, selectable: bool, hand_index: int, card_index: int, target: Vector3, card_scale: float, delay: float) -> void:
	if not _cards.has(key):
		var created_view := CARD_SCENE.instantiate() as TableCard3D
		card_root.add_child(created_view)
		_cards[key] = created_view
	var view := _cards[key]
	view.hand_index = hand_index
	view.card_index = card_index
	view.body.set_meta("card_view", view)
	view.present(card, is_concealed, selectable, target, card_scale, Vector3(1.95, 1.3, -1.25), minf(delay, 0.5))


## Put one concealed/revealed total per hand on readable tilted tabletop displays.
func _refresh_hand_labels() -> void:
	for label in _hand_labels:
		label.queue_free()
	for plate in _label_plates:
		plate.queue_free()
	_hand_labels.clear()
	_label_plates.clear()
	var dealer_text := "DEALER\nWaiting for deal"
	if not hud.game.dealer.hand.cards.is_empty():
		dealer_text = "DEALER\nTotal: %d" % hud.game.dealer.hand.get_total() if hud.game.round_over else "DEALER\nShowing: %d + ?" % hud.game.dealer.hand.cards[0].get_blackjack_value()
	_add_table_label(dealer_text, Vector3(0, 1.36, -2.08), Color("afc6ca"), 1.2)
	var count := hud.game.player.hands.size()
	for index in range(count):
		var played_hand := hud.game.player.hands[index]
		var hidden := hud.game.is_player_card_hidden(index, 1)
		var total := "?" if hidden else str(played_hand.hand.get_total())
		var active := not hud.game.round_over and index == hud.game.player.active_hand_index
		var title := "YOUR HAND" if count == 1 else "H%d" % (index + 1)
		var text := "%s%s · %s\nBet $%.2f" % [title, " ▶" if active else (" ✓" if played_hand.is_standing and not hud.game.round_over else ""), total, played_hand.wager]
		if played_hand.hand.cards.is_empty():
			text = "YOUR HAND\nReady to deal"
		elif hidden:
			text += "\nKeep or replace"
		elif hud.game.round_over:
			text += " · " + hud._money_delta(played_hand.net_result)
		elif hud.game.is_awaiting_second_chance() and active:
			text += "\nRecover / Take payout" if hud.game.is_double_target_match(played_hand) else "\nBust · Recover / Finish"
		if played_hand.lucky_nine_qualified:
			text += "\nLucky 9 " + (hud._money_delta(played_hand.lucky_nine_bonus) if hud.game.round_over else "ready")
		var color := hud._delta_color(played_hand.net_result) if hud.game.round_over and hud.game.has_round_result else (Color("e8c36e") if active else Color("afc6ca"))
		var target := _hand_center(index, count) + Vector3(0, 1.22 if count > 2 and index >= 2 and text.count("\n") == 1 else 1.26, -0.55 if count == 1 else (-0.39 if count > 2 and index < 2 else (0.55 if count > 2 else -0.4)))
		_add_table_label(text, target, color, 1.3 if count == 1 else 0.95, false)


## Use high-contrast displays tilted toward the seat; text remains anchored in the room.
func _add_table_label(text: String, target: Vector3, color: Color, width: float, dealer_display: bool = true) -> void:
	var tilt := deg_to_rad(-40.0)
	var plate := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, (text.count("\n") + 1) * (0.14 if dealer_display else 0.12) + 0.045)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("102831")
	plate.mesh = quad
	plate.material_override = material
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.position = target
	plate.rotation.x = tilt
	card_root.add_child(plate)
	_label_plates.append(plate)
	var label := Label3D.new()
	label.text = text
	label.position = target + Basis(Vector3.RIGHT, tilt) * Vector3(0, 0, 0.005)
	label.rotation.x = tilt
	label.font_size = 40 if dealer_display else 32
	label.pixel_size = 0.003
	label.outline_size = 2
	label.modulate = color
	card_root.add_child(label)
	_hand_labels.append(label)


## Keep the lit console's mode/count summary aligned with saved next-round preferences.
func _refresh_console() -> void:
	var settings := hud.game.rules.get_configuration()
	var text := "CLASSIC"
	if settings.mode == RuleManager.RuleMode.ALL_SELECTED:
		text = "ALL SELECTED · %d rules" % settings.selected.size()
	elif settings.mode == RuleManager.RuleMode.RANDOM_SELECTED:
		text = "RANDOM · %d of %d" % [mini(settings.random_count, settings.selected.size()), settings.selected.size()]
	var progress := "%d rounds · $%.0f" % [hud.session.round_limit, hud.session.starting_money] if hud.session.phase == BlackjackSession.Phase.SETUP else ("FINISHED · %d/%d rounds" % [hud.session.completed_rounds, hud.session.round_limit] if hud.session.phase == BlackjackSession.Phase.FINISHED else "ROUND %d/%d · LOCKED" % [mini(hud.session.completed_rounds + 1, hud.session.round_limit), hud.session.round_limit])
	console_label.text = "SESSION CONSOLE\n" + progress + "\n" + text + "\n[E] SETTINGS"


## Return to a comfortable card-facing perspective only when explicitly requested.
func focus_table() -> void:
	table_camera.rotation = Vector3(DEFAULT_PITCH, 0.0, 0.0)
	table_camera.fov = DEFAULT_FOV


## Pick nearby toys with room geometry occlusion, excluding the player's walking body.
func pick_prop(screen_position: Vector2) -> LoungeProp:
	if mode == RoomMode.CONSOLE:
		return null
	var camera := table_camera if mode == RoomMode.TABLE else explorer.camera
	var origin := camera.project_ray_origin(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen_position) * 3.3, 5)
	query.exclude = [explorer.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") as LoungeProp if not hit.is_empty() else null


## Ray-pick only eligible world cards; room geometry and other hands cannot consume Reroll.
func pick_card(screen_position: Vector2) -> TableCard3D:
	if mode != RoomMode.TABLE or not hud._selecting_reroll:
		return null
	var origin := table_camera.project_ray_origin(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + table_camera.project_ray_normal(screen_position) * 30.0, 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Node = hit.collider
	return collider.get_meta("card_view", null) as TableCard3D
