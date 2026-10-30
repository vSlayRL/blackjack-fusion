extends Node3D
## Four table lanes and synchronized card lifting. Card inspection never changes the game.

const CARD_SCENE: PackedScene = preload("res://scenes/room/table_card.tscn")
var _cards: Dictionary = {}
var _identities: Dictionary = {}
var _labels: Node3D
var _round: int = -1
var _session: int = -1
var _poses: Dictionary = {}
# 0 faint, 1 hidden, 2 solid. Preferences apply only to this player's view.
var info_mode: int = 0
# A local-only display preference, never sent through TableNetwork.
var dealer_raised: bool = false


func _ready() -> void:
	_labels = Node3D.new()
	add_child(_labels)
	TableNetwork.changed.connect(refresh)
	refresh()


func cycle_info() -> void:
	info_mode = (info_mode + 1) % 3
	refresh()


func info_caption() -> String:
	return ["Faint", "Hidden", "Solid"][info_mode]


func refresh() -> void:
	var state := TableNetwork.state
	if state.is_empty():
		return
	if _round != state.round or _session != state.session.id:
		for card in _cards.values():
			card.queue_free()
		_cards.clear()
		_poses.clear()
		dealer_raised = false
		_round = state.round
		_session = state.session.id
	for label in _labels.get_children():
		label.queue_free()
	var alive: Array[String] = []
	for index in range(state.dealer.size()):
		var columns := mini(state.dealer.size(), 6)
		var key := "dealer:%d" % index
		var position_on_table := Vector3((index % columns - (columns - 1) / 2.0) * 0.43, 1.16 + index * 0.002, -1.52 + int(index / float(columns)) * 0.21)
		_card(key, state.dealer[index], position_on_table, 0.70, 0, 0, index, state.dealer.size())
		alive.append(key)
	var dealer_text := "DEALER · Waiting"
	if not state.dealer.is_empty():
		dealer_text = "DEALER · %d" % state.dealer_total if state.dealer_total >= 0 else "DEALER · %d + ?" % _identity(state.dealer[0]).get_blackjack_value()
	_plate(dealer_text, Vector3(0, 1.38, -2.1), Color("dbf0f2"), 1.9, 0.0, true)
	for person in state.players:
		if person.hands.is_empty() or person.round_seat < 0:
			continue
		var seat: int = person.round_seat
		var outer := seat == 0 or seat == 3
		var center := Vector3((seat - 1.5) * 1.4, 0, -0.4 if outer else -0.10)
		var lucky_bonus := 0.0
		var text: String = person.name.left(12) + (" ▶" if person.can_act else "")
		for hand_index in range(person.hands.size()):
			var hand: Dictionary = person.hands[hand_index]
			if hand.lucky_nine_qualified:
				lucky_bonus = hand.lucky_nine_bonus
			var split: bool = person.hands.size() > 1
			var hand_center := center + Vector3((-0.32 if hand_index % 2 == 0 else 0.32) if split else 0.0, 0, (-0.38 if hand_index < 2 else 0.13) if split else 0.0)
			var columns := mini(hand.cards.size(), 4 if split else 5)
			var step := minf(0.18 if split else 0.28, (0.5 if split else 1.06) / maxf(columns - 1.0, 1.0))
			for card_index in range(hand.cards.size()):
				var target := hand_center + Vector3((card_index % columns - (columns - 1) / 2.0) * step, 1.16 + card_index * 0.002, int(card_index / float(columns)) * 0.15)
				var key := "%d:%d:%d" % [person.id, hand_index, card_index]
				_card(key, hand.cards[card_index], target, 0.43 if split else 0.64, person.id, hand_index, card_index, hand.cards.size())
				alive.append(key)
			text += "\n%s%s · $%.2f%s" % ["▶ " if hand.active else ("✓ " if hand.standing else ""), "?" if hand.total < 0 else str(hand.total), hand.wager, " · %s$%.2f" % ["+" if hand.net >= 0 else "−", absf(hand.net)] if state.phase == "settled" else ""]
		var color: Color = Color("f3d581") if person.can_act else RoomNetwork.players.get(person.id, {}).get("color", Color("afc6ca"))
		var plate := _plate(text, Vector3(center.x, 1.29, 0.35 if outer else 0.80), color, 1.24, RoomNetwork.SEAT_YAWS[seat], false, lucky_bonus)
		if plate != null:
			plate.set_meta("peer_id", person.id)
	for key in _cards.keys():
		if not alive.has(key):
			_cards[key].queue_free()
			_cards.erase(key)
			_poses.erase(key)


func _identity(code: int) -> Card:
	if not _identities.has(code):
		_identities[code] = ClassicTable.decode_card(code)
	return _identities[code]


func _card(key: String, code: Variant, target: Vector3, card_scale: float, player_id: int = 0, hand_index: int = 0, card_index: int = 0, count: int = 0) -> void:
	var existing := _cards.has(key)
	if not _cards.has(key):
		var view := CARD_SCENE.instantiate() as TableCard3D
		add_child(view)
		_cards[key] = view
		view.body.set_meta("card_view", view)
	var previous: Transform3D = _cards[key].transform
	# A concealed card is a generic placeholder, never the host's actual card.
	_cards[key].present(_identity(0 if code == null else int(code)), code == null, false, target, card_scale, Vector3(1.95, 1.3, -1.25), 0.0)
	# Preserve animation progress when a new snapshot refreshes the same card face.
	if _cards[key]._motion != null:
		_cards[key]._motion.kill()
	if existing:
		_cards[key].transform = previous
	_cards[key].hand_index = hand_index
	_cards[key].card_index = card_index
	_poses[key] = {"home": Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * card_scale), target),
		"id": player_id, "hand": hand_index, "index": card_index, "count": count, "hidden": code == null}


## Move the original physical meshes between the table and a fan in front of the player.
## Remote players see the same hand lifted; the owner gets framing fitted to their window.
func _process(delta: float) -> void:
	var lounge := get_parent()
	for key in _poses:
		var pose: Dictionary = _poses[key]
		var target: Transform3D = pose.home
		if pose.id == 0:
			target = _dealer_pose(pose)
		elif TableNetwork.viewed_hand(pose.id) == pose.hand and lounge.avatars.has(pose.id):
			target = _held_pose(lounge.avatars[pose.id], pose)
		if pose.id != 0 and pose.hidden:
			target.basis *= Basis(Vector3.FORWARD, PI)
		_cards[key].transform = _cards[key].transform.interpolate_with(target, 1.0 - exp(-14.0 * delta))
		var eligible := _eligible_pose(pose)
		if _cards[key].selectable != eligible:
			_cards[key].set_selectable(eligible)
		# Nonselectable cards also block picking; clicking through another hand cannot reroll.
		_cards[key].body.collision_layer = 2 if eligible else 4


## Only the local active hand is eligible during a live selection context.
func _eligible_pose(pose: Dictionary) -> bool:
	var lounge := get_parent()
	return lounge.table_hud != null and lounge.table_hud.is_selecting_reroll() and pose.id == multiplayer.get_unique_id() and pose.hand == lounge.table_hud.active_reroll_hand() and not pose.hidden


## Ray-test cards and room geometry together so furniture/other hands block selection.
func pick_card(screen_position: Vector2) -> TableCard3D:
	var lounge := get_parent()
	if lounge.table_hud == null or not lounge.table_hud.is_selecting_reroll():
		return null
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.project_ray_origin(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen_position) * 30.0, 1 | 2 | 4)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider := hit.collider as Node
	if not collider.has_meta("card_view"):
		return null
	var view := collider.get_meta("card_view") as TableCard3D
	if view == null or not view.selectable:
		return null
	for key in _cards:
		if _cards[key] == view and _eligible_pose(_poses[key]):
			return view
	return null


func hover_card(hovered: TableCard3D) -> void:
	for view in _cards.values():
		view.set_hovered(view == hovered)


## D changes only this viewer's presentation; concealment is authoritative in either pose.
func _dealer_pose(pose: Dictionary) -> Transform3D:
	var target: Transform3D = pose.home
	if not dealer_raised:
		if pose.hidden:
			target.basis *= Basis(Vector3.FORWARD, PI)
		return target
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return target
	var columns := mini(int(pose.count), 6)
	var rows := int(ceil(int(pose.count) / 6.0))
	var row := int(int(pose.index) / float(columns))
	var anchor := Vector3(0, 1.53 + (rows - 1 - row) * 0.57, -1.52)
	var direction := anchor - camera.global_position
	if direction.length_squared() < 0.0001:
		return target
	var up := Vector3.UP if absf(direction.normalized().dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	var row_basis := Basis.looking_at(direction, up)
	# Turn the whole row so cards stay side by side even from an outer chair.
	target.origin = anchor + row_basis.x * target.origin.x
	var facing := row_basis * Basis(Vector3.RIGHT, PI / 2.0)
	if pose.hidden:
		facing *= Basis(Vector3.FORWARD, PI)
	return Transform3D(facing.scaled(Vector3.ONE * 0.64), target.origin)


func _held_pose(avatar: Node3D, pose: Dictionary) -> Transform3D:
	var camera := avatar.get_node("Camera3D") as Camera3D
	var local: bool = avatar.local_player
	var distance := 1.12
	var card_scale := 0.85
	var anchor: Vector3
	var facing: Basis
	if local:
		var viewport_size := get_viewport().get_visible_rect().size
		var lounge := get_parent()
		var top := 40.0
		var bottom := viewport_size.y - 40.0
		if lounge._hud.visible:
			top = lounge.header_panel.get_global_rect().end.y + 12.0
			bottom = lounge.table_hud.get_global_rect().position.y - 12.0
		# A headless server has a tiny dummy viewport; keep projection finite there too.
		top = clampf(top, 0.0, maxf(0.0, viewport_size.y - 32.0))
		bottom = clampf(bottom, top + 1.0, maxf(top + 1.0, viewport_size.y))
		var focal := viewport_size.y / (2.0 * tan(deg_to_rad(camera.fov) / 2.0))
		card_scale = minf(0.95, maxf(0.40, (bottom - top) * 0.78 * distance / (focal * 0.78)))
		anchor = camera.project_position(Vector2(viewport_size.x * 0.5, (top + bottom) * 0.5), distance)
		facing = camera.global_basis
	else:
		var pitch: float = RoomNetwork.players.get(pose.id, {}).get("pitch", -0.3)
		facing = Basis(Vector3.UP, avatar.rotation.y) * Basis(Vector3.RIGHT, pitch)
		anchor = camera.global_position + facing * Vector3(0, -0.03, -distance)
	var count: int = pose.count
	var offset: float = pose.index - (count - 1) * 0.5
	var spread := minf(0.28, 1.5 / maxf(count - 1, 1))
	var angle := offset * minf(0.09, 0.5 / maxf(count - 1, 1))
	var position_in_fan := Vector3(offset * spread, -absf(offset) * 0.012, pose.index * 0.005)
	var rotation_in_fan := facing * Basis(Vector3.BACK, -angle) * Basis(Vector3.RIGHT, PI / 2.0)
	return Transform3D(rotation_in_fan.scaled(Vector3.ONE * card_scale), anchor + facing * position_in_fan)


func _plate(text: String, target: Vector3, color: Color, width: float, yaw: float, dealer_display: bool = false, lucky_bonus: float = 0.0) -> Node3D:
	if info_mode == 1:
		return null
	var root := Node3D.new()
	root.position = target
	root.rotation = Vector3(deg_to_rad(-45), yaw, 0)
	_labels.add_child(root)
	var plate := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, (text.count("\n") + 1) * (0.20 if dealer_display else 0.105) + 0.04 + (0.15 if lucky_bonus > 0 else 0.0))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.03, 0.12, 0.17, 0.20 if info_mode == 0 else 0.92)
	plate.mesh = quad
	plate.material_override = material
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(plate)
	var label := Label3D.new()
	label.position.z = 0.005
	label.position.y = 0.06 if lucky_bonus > 0 else 0.0
	label.text = text
	label.font_size = 40 if dealer_display else 36
	label.pixel_size = 0.004 if dealer_display else 0.0023
	label.outline_size = 2
	label.modulate = color
	root.add_child(label)
	if lucky_bonus > 0:
		var badge := Label3D.new()
		badge.name = "LuckyNineBadge"
		badge.position = Vector3(0, -0.12, 0.006)
		badge.text = "Lucky 9 · +$%.2f on a win" % lucky_bonus
		badge.font_size = 28
		badge.pixel_size = 0.0023
		badge.modulate = Color("ffdf77")
		badge.outline_size = 2
		root.add_child(badge)
	return root
