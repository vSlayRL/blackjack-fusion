extends Node
## Shared fullscreen controls for the 2D game and 3D room without resetting their state.

var _previous_mode: Window.Mode = Window.MODE_WINDOWED


## Accept fullscreen shortcuts before a focused gameplay button or wager input consumes them.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F11 or (event.alt_pressed and event.keycode == KEY_ENTER):
			toggle_fullscreen()
			get_viewport().set_input_as_handled()


## Preserve the previous window/maximized mode and avoid unsupported embedded-preview changes.
func toggle_fullscreen() -> void:
	if Engine.is_embedded_in_editor() or DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		window.mode = _previous_mode
	else:
		_previous_mode = window.mode
		window.mode = Window.MODE_FULLSCREEN
