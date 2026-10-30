class_name NetworkLeaderboard
extends Node3D
## Physical room screen. The shared session ledger changes balances only after settlement.

var rows: Array = []
var heading: Label3D
var progress: Label3D
var columns: Array[String] = []
var _content: Node3D
var _last: String = ""


func _ready() -> void:
	_box(Vector3(5.85, 2.65, 0.14), Vector3(0, 0, -0.04), Color("071822"))
	_box(Vector3(5.65, 2.45, 0.025), Vector3(0, 0, 0.045), Color("102b39"))
	for side in [-1, 1]:
		_box(Vector3(5.75, 0.025, 0.03), Vector3(0, side * 1.27, 0.055), Color("4bd9ed"))
	heading = _text("SESSION LEADERBOARD", Vector3(-2.65, 0.96, 0.07), 46, Color("a9eff5"), 5.3)
	progress = _text("", Vector3(-2.65, 0.72, 0.07), 27, Color("b7cbd1"), 5.3)
	_content = Node3D.new()
	add_child(_content)
	TableNetwork.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if _content == null or TableNetwork.state.is_empty():
		return
	var session: Dictionary = TableNetwork.state.session
	var fingerprint := str(session)
	if fingerprint == _last:
		return
	_last = fingerprint
	rows = session.standings.duplicate(true)
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var finished: bool = session.status == "finished"
	heading.text = "FINAL SESSION STANDINGS" if finished else "SESSION LEADERBOARD"
	if session.status == "setup":
		progress.text = "Start a competition at the Session & Rules console."
	elif finished:
		progress.text = "%d of %d rounds complete · Ties share a place" % [session.completed, session.round_limit]
	else:
		progress.text = "%d of %d rounds settled · Balances update after each deal" % [session.completed, session.round_limit]
	columns.assign(["Place", "Player Name", "Starting\nBalance", "Ending\nBalance" if finished else "Current\nBalance", "Net Profit"])
	var offsets := [-2.65, -2.15, -0.35, 0.77, 1.91]
	var widths := [0.42, 1.65, 1.02, 1.04, 0.83]
	for index in range(5):
		var label := _text(columns[index], Vector3(offsets[index], 0.38, 0.07), 27, Color("95b8c7"), widths[index])
		reparent_text(label)
	for index in range(rows.size()):
		var entry: Dictionary = rows[index]
		var y := 0.03 - index * 0.31
		var net: float = entry.net
		var name_text: String = entry.name + (" (left)" if not entry.connected else "")
		var values := ["#%d" % entry.place, name_text, "$%.2f" % entry.starting_balance, "$%.2f" % entry.balance,
			("+" if net > 0 else ("−" if net < 0 else "")) + "$%.2f" % absf(net)]
		for column in range(5):
			var color := Color("e1f1f5")
			if column == 0 and entry.place == 1:
				color = Color("f3d581")
			elif column == 4:
				color = Color("69eda4") if net > 0 else (Color("ff7a8e") if net < 0 else Color("b7cbd1"))
			var label := _text(values[column], Vector3(offsets[column], y, 0.07), 33, color, widths[column])
			reparent_text(label)


func reparent_text(label: Label3D) -> void:
	label.reparent(_content, false)


func _box(size_value: Vector3, location: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size_value
	mesh.mesh = shape
	mesh.position = location
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _text(value: String, location: Vector3, font_size_value: int, color: Color, width_value: float) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.position = location
	label.font_size = font_size_value
	label.pixel_size = 0.003
	label.width = width_value / label.pixel_size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.outline_size = 0
	label.modulate = color
	add_child(label)
	return label
