class_name TableHUD
extends "res://scripts/ui/game_ui.gd"
## Reuses the tested 2D action/settings handlers while presenting a compact overlay for 3D play.

signal state_refreshed
signal leave_requested
signal focus_requested
signal new_session_requested
signal modal_opened

var session: BlackjackSession = BlackjackSession.new()
var rounds_spin: SpinBox
var starting_money_spin: SpinBox
var session_label: Label
var session_note: Label
var results_dialog: AcceptDialog
var results_details: Label
var results_net: Label
var results_button: Button
var console_new_button: Button
var _results_shown: bool = false

var play_area: Control
var leave_button: Button
var focus_button: Button
var fullscreen_button: Button
var selection_row: HBoxContainer
var card_selector: OptionButton
var bottom_dock: MarginContainer
var look_hint: Label
var look_reticle: Label


## Keep the original controls, replacing their card board with space for the 3D table.
func _ready() -> void:
	_build_overlay()
	super._ready()
	game = session.game
	_build_results_dialog()
	_refresh_ui()
	$Background.hide()
	table_scroll.hide()
	rules_button.hide()
	$WindowMargin/Layout/Header/TitleGroup/Subtitle.text = "RULE SETTINGS: SIDE CONSOLE"
	show_table(false)
	set_process(true)


## Show balance/results and controls; hand information stays on the physical table.
func _build_overlay() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	$WindowMargin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layout := $WindowMargin/Layout as VBoxContainer
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 6)
	play_area = Control.new()
	play_area.name = "WorldSpace"
	play_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(play_area)
	look_reticle = _label("·", 28, INK)
	look_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	look_reticle.autowrap_mode = TextServer.AUTOWRAP_OFF
	look_reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	look_reticle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	look_reticle.size = Vector2(24, 24)
	look_reticle.hide()
	add_child(look_reticle)
	# Hide the legacy board before any minimum-size measurements can include it.
	%TableScroll.hide()
	$WindowMargin/Layout/Header/TitleGroup.hide()
	$WindowMargin/Layout/Header/Stats/BetGroup.hide()
	%StatusLabel.hide()
	$WindowMargin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bottom_dock = MarginContainer.new()
	bottom_dock.name = "BottomDock"
	bottom_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	add_child(bottom_dock)
	var dock_layout := VBoxContainer.new()
	dock_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock_layout.add_theme_constant_override("separation", 6)
	bottom_dock.add_child(dock_layout)
	%StatusPanel.reparent(dock_layout)
	session_label = _label("SESSION — Configure at the console", 14, INK)
	session_label.max_lines_visible = 1
	session_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	%ActiveRulesLabel.get_parent().add_child(session_label)
	%ActiveRulesLabel.get_parent().move_child(session_label, 0)
	%ControlsGrid.reparent(dock_layout)
	%StatusLabel.max_lines_visible = 2
	%ActiveRulesLabel.max_lines_visible = 1
	%StatusLabel.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	%ActiveRulesLabel.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	leave_button = Button.new()
	leave_button.text = "Leave Table"
	leave_button.custom_minimum_size = Vector2(112, 36)
	leave_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	leave_button.pressed.connect(func(): leave_requested.emit())
	$WindowMargin/Layout/Header/Stats.add_child(leave_button)
	focus_button = Button.new()
	focus_button.text = "Look at Cards"
	focus_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	focus_button.pressed.connect(func(): focus_requested.emit())
	$WindowMargin/Layout/Header/Stats.add_child(focus_button)
	fullscreen_button = Button.new()
	fullscreen_button.name = "FullscreenButton"
	fullscreen_button.text = "F11"
	fullscreen_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fullscreen_button.disabled = Engine.is_embedded_in_editor()
	fullscreen_button.tooltip_text = "Toggle fullscreen (F11 / Alt+Enter)." if not fullscreen_button.disabled else "For fullscreen, turn off Embed Game on Next Play in Godot's Game menu. For resizing in the preview, select Stretch to Fit."
	fullscreen_button.pressed.connect(DisplaySettings.toggle_fullscreen)
	$WindowMargin/Layout/Header/Stats.add_child(fullscreen_button)
	selection_row = HBoxContainer.new()
	selection_row.add_theme_constant_override("separation", 8)
	dock_layout.add_child(selection_row)
	card_selector = OptionButton.new()
	card_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_row.add_child(card_selector)
	var replace_button := Button.new()
	replace_button.text = "Replace Selected"
	replace_button.pressed.connect(_replace_selected_card)
	selection_row.add_child(replace_button)
	look_hint = _label("Hold RMB: look · C: cards · F: grab/drop · Wheel: zoom", 13, MUTED)
	look_hint.max_lines_visible = 1
	look_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dock_layout.add_child(look_hint)
	results_button = Button.new()
	results_button.text = "View Session Results"
	results_button.pressed.connect(_show_session_results)
	dock_layout.add_child(results_button)
	results_button.hide()
	for button_name in ["HitButton", "StandButton", "DoubleButton", "SplitButton", "RerollButton", "SecondChanceButton", "KeepMysteryButton", "ReplaceMysteryButton", "DealButton"]:
		get_node("%" + button_name).custom_minimum_size.y = 36.0
	%BetSpinBox.custom_minimum_size = Vector2(120, 36)
	%RestartButton.custom_minimum_size = Vector2(90, 36)
	$WindowMargin/Layout/Header/Stats.add_theme_constant_override("separation", 8)
	$WindowMargin/Layout/Header/Stats/MoneyGroup/Caption.text = "BALANCE"
	$WindowMargin/Layout/Header/Stats/MoneyGroup/Caption.add_theme_font_size_override("font_size", 12)
	$WindowMargin/Layout/Header/Stats/BetGroup/Caption.add_theme_font_size_override("font_size", 12)
	%MoneyLabel.add_theme_font_size_override("font_size", 22)
	%CurrentBetLabel.add_theme_font_size_override("font_size", 22)
	%RoundDeltaLabel.add_theme_font_size_override("font_size", 16)
	%RoundDeltaLabel.clip_text = true
	%StatusLabel.add_theme_font_size_override("font_size", 16)


## Refresh through the existing engine interface, then notify the room to synchronize models.
func _refresh_ui() -> void:
	if session.game == game:
		session.observe_round()
	super._refresh_ui()
	restart_button.text = "New Session"
	restart_button.add_theme_font_size_override("font_size", 14 if size.x < 760.0 else 18)
	restart_button.disabled = session.phase != BlackjackSession.Phase.FINISHED
	restart_button.tooltip_text = "Start a new session after this one finishes."
	deal_button.disabled = deal_button.disabled or session.phase != BlackjackSession.Phase.PLAYING
	bet_spin_box.editable = not deal_button.disabled
	if session.phase != BlackjackSession.Phase.PLAYING:
		deal_button.text = "Session Finished" if session.phase == BlackjackSession.Phase.FINISHED else "Set Up at Console"
	session_label.text = session.progress_text()
	session_label.tooltip_text = session_label.text
	results_button.visible = session.phase == BlackjackSession.Phase.FINISHED
	if leave_button != null:
		leave_button.disabled = not game.round_over
		leave_button.tooltip_text = "Return to the room." if game.round_over else "Finish this round before leaving the table."
		selection_row.visible = _selecting_reroll
		card_selector.clear()
		if _selecting_reroll:
			for index in range(game.player.hand.cards.size()):
				card_selector.add_item("Card %d: %s" % [index + 1, game.player.hand.cards[index].get_card_name()], index)
			status_label.text = "Click a gold-outlined card, or choose one below. Cancel keeps your Reroll."
	status_label.tooltip_text = status_label.text
	state_refreshed.emit()
	if session.phase == BlackjackSession.Phase.FINISHED and not _results_shown:
		_results_shown = true
		_show_session_results.call_deferred()


## Fit the HUD at small widths while reserving a central region for physical cards.
func _apply_responsive_layout() -> void:
	if not is_node_ready() or game == null:
		return
	active_rules_label.text = _get_rules_text()
	active_rules_label.tooltip_text = _get_rules_text(true)
	%BetRow.visible = game.round_over and session.phase != BlackjackSession.Phase.FINISHED
	%ActionsGrid.visible = not game.round_over and not game.is_awaiting_mystery_card()
	%Header.columns = 1
	# Compact utility controls reserve space for configurable six-digit bankrolls.
	var compact := size.x < 760.0
	restart_button.add_theme_font_size_override("font_size", 14 if compact else 18)
	leave_button.text = "Leave" if compact else "Leave Table"
	leave_button.custom_minimum_size.x = 80.0 if compact else 112.0
	focus_button.text = "Cards" if compact else "Look at Cards"
	focus_button.tooltip_text = "Look at Cards (C)."
	focus_button.custom_minimum_size.x = 80.0 if compact else 0.0
	for button in [leave_button, focus_button, fullscreen_button]:
		button.add_theme_font_size_override("font_size", 14 if compact else 18)
	$WindowMargin/Layout/Header/TitleGroup.hide()
	$WindowMargin/Layout/Header/TitleGroup/Title.add_theme_font_size_override("font_size", 22)
	%ControlsGrid.columns = 1
	var count := 4 + int(reroll_button.visible) + int(second_chance_button.visible)
	%ActionsGrid.columns = count if size.x >= 850.0 else (3 if count > 4 else 4)
	for edge in ["left", "right", "top", "bottom"]:
		%WindowMargin.add_theme_constant_override("margin_" + edge, 10)
	if rule_dialog.visible:
		rule_dialog.position = Vector2i(maxi(0, int((size.x - rule_dialog.size.x) / 2.0)), maxi(0, int((size.y - rule_dialog.size.y) / 2.0)))
	if results_dialog != null and results_dialog.visible:
		results_dialog.position = Vector2i(maxi(0, int((size.x - results_dialog.size.x) / 2.0)), maxi(0, int((size.y - results_dialog.size.y) / 2.0)))


## Make the 3D board mouse-transparent and omit unnecessary 2D card generation.
func _render_dealer_cards() -> void:
	pass


## Hand summaries and world models replace the original card-panel renderer.
func _render_player_hands() -> void:
	pass


## Do not advertise another round after the limit; make Random's count explicit between deals.
func _get_rules_text(expanded: bool = false) -> String:
	if session.phase == BlackjackSession.Phase.FINISHED:
		return "SESSION COMPLETE — New Session to play again"
	var text := super._get_rules_text(expanded)
	if session.phase == BlackjackSession.Phase.SETUP:
		return text.replace("NEXT ROUND", "SESSION RULES")
	var settings := game.rules.get_configuration()
	if game.round_over and settings.mode == RuleManager.RuleMode.RANDOM_SELECTED and not expanded:
		return "NEXT ROUND — Random %d of %d checked rules" % [mini(settings.random_count, settings.selected.size()), settings.selected.size()]
	return text


## Use compact padding for the overlay controls while retaining the shared readable theme.
func _build_theme() -> void:
	super._build_theme()
	theme.set_color("font_outline_color", "Label", Color("071318"))
	theme.set_constant("outline_size", "Label", 3)
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := theme.get_stylebox(state_name, "Button") as StyleBoxFlat
		style.content_margin_top = 6
		style.content_margin_bottom = 6
	for button in [deal_button, bet_spin_box.get_line_edit()]:
		for state_name in ["normal", "focus"]:
			var style := button.get_theme_stylebox(state_name).duplicate() as StyleBoxFlat
			style.content_margin_top = 6
			style.content_margin_bottom = 6
			button.add_theme_stylebox_override(state_name, style)
	%StatusPanel.add_theme_stylebox_override("panel", _panel_style(Color("102831"), Color("30505e"), 1, 8))


## Physical cards use the seated camera; the old 2D scrolling focus is not needed.
func _request_hand_focus() -> void:
	pass


## Allow the shared settings dialog to remain usable while the table overlay is hidden.
func show_table(show_overlay: bool) -> void:
	$WindowMargin.visible = show_overlay
	bottom_dock.visible = show_overlay
	play_area.visible = show_overlay
	look_reticle.hide()


## Anchor action controls to the window bottom independently of hand/status text changes.
func _process(_delta: float) -> void:
	look_reticle.position = size / 2.0 - look_reticle.size / 2.0
	var top_margin := $WindowMargin as MarginContainer
	top_margin.offset_bottom = top_margin.get_combined_minimum_size().y
	var height := bottom_dock.get_combined_minimum_size().y
	bottom_dock.offset_left = 10.0
	bottom_dock.offset_right = -10.0
	bottom_dock.offset_bottom = -10.0
	bottom_dock.offset_top = -10.0 - height
	var top: float = $WindowMargin.get_global_rect().end.y + 6.0
	play_area.position = Vector2(10.0, top)
	play_area.size = Vector2(maxf(1.0, size.x - 20.0), maxf(0.0, bottom_dock.position.y - top - 6.0))


## Label the existing modes clearly for the physical console without changing their IDs.
func _build_rule_dialog() -> void:
	super._build_rule_dialog()
	rule_dialog.title = "Session Settings"
	rule_dialog.get_ok_button().text = "Start Session"
	console_new_button = rule_dialog.add_button("New Session", false, "new_session")
	rule_dialog.custom_action.connect(func(action: StringName):
		if action == &"new_session":
			_on_restart_pressed())
	rule_mode_option.set_item_text(0, "Classic — Special rules off")
	rule_mode_option.set_item_text(1, "All Selected — Activate checked rules")
	rule_mode_option.set_item_text(2, "Random — Choose checked rules each round")
	var margin: MarginContainer
	for child in rule_dialog.get_children():
		if child is MarginContainer:
			margin = child
	var layout := margin.get_child(0) as VBoxContainer
	(layout.get_child(0) as Label).text = "Choose your session length, starting balance, and rules. Settings lock until the session ends."
	rounds_spin = _add_session_setting(layout, "Number of rounds", 1.0, BlackjackSession.MAX_ROUNDS, 10.0, 1)
	starting_money_spin = _add_session_setting(layout, "Starting money ($)", BlackjackGame.MINIMUM_BET, BlackjackSession.MAX_STARTING_MONEY, 100.0, 2)
	# Scroll the complete form rather than growing it beyond a small window.
	for child in layout.get_children():
		if child is ScrollContainer:
			var index := child.get_index()
			child.get_child(0).reparent(layout)
			layout.move_child(layout.get_child(layout.get_child_count() - 1), index)
			layout.remove_child(child)
			child.queue_free()
	margin.remove_child(layout)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(layout)
	session_note = layout.get_child(layout.get_child_count() - 1) as Label
	for checkbox in rule_checkboxes.values():
		checkbox.toggled.connect(func(_pressed: bool): _update_session_controls())


## Add a compact numeric row, keeping limits in sync with the session model.
func _add_session_setting(layout: VBoxContainer, title: String, minimum: float, maximum: float, initial: float, index: int) -> SpinBox:
	var row := HBoxContainer.new()
	layout.add_child(row)
	layout.move_child(row, index)
	var label := _label(title, 16, INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.custom_minimum_size.x = 130
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1.0
	spin.value = initial
	row.add_child(spin)
	return spin


## Prevent Restart from abandoning an active wager in the 3D room.
func _on_restart_pressed() -> void:
	if not session.new_session():
		return
	results_dialog.hide()
	game = session.game
	_results_shown = false
	_selecting_reroll = false
	_last_active_hand = -1
	_refresh_ui()
	new_session_requested.emit()


## Gate deals through the session lifecycle, including immediately settled opening naturals.
func _on_deal_pressed() -> void:
	_selecting_reroll = false
	session.begin_round(bet_spin_box.value)
	_refresh_ui()


## Populate one draft form; opening or cancelling it never changes the saved session.
func _populate_rule_settings() -> void:
	super._populate_rule_settings()
	rounds_spin.value = session.round_limit
	starting_money_spin.value = session.starting_money
	_update_session_controls()
	random_count_spin.value = game.rules.get_configuration().random_count


## Session settings can be viewed between deals, but only setup permits editing/start.
func _on_rules_pressed() -> void:
	if not game.round_over:
		return
	_populate_rule_settings()
	rule_dialog.popup_centered_clamped(Vector2i(540, 500), 0.9)


func _on_rule_mode_selected(_index: int) -> void:
	_update_session_controls()


## The separate clickable rule titles must respect the same lock as their checkboxes.
func _on_rule_title_input(event: InputEvent, checkbox: CheckBox) -> void:
	if session.phase == BlackjackSession.Phase.SETUP:
		super._on_rule_title_input(event, checkbox)


## Clamp random count to the checked pool and keep every field read-only during play.
func _update_session_controls() -> void:
	if rounds_spin == null:
		return
	var editable := session.phase == BlackjackSession.Phase.SETUP
	console_new_button.visible = session.phase == BlackjackSession.Phase.FINISHED
	var checked := 0
	for checkbox in rule_checkboxes.values():
		checked += int(checkbox.button_pressed)
		checkbox.disabled = not editable
	var random := rule_mode_option.get_selected_id() == RuleManager.RuleMode.RANDOM_SELECTED
	rounds_spin.editable = editable
	starting_money_spin.editable = editable
	rule_mode_option.disabled = not editable
	random_count_spin.max_value = maxi(1, checked)
	random_count_spin.editable = editable and random and checked > 0
	rule_dialog.get_ok_button().disabled = not editable or (random and checked == 0)
	rule_dialog.get_ok_button().text = "Start Session" if editable else "Settings Locked"
	session_note.text = "Check at least one rule for Random mode." if editable and random and checked == 0 else ("Random chooses distinct checked rules each round. Cancel leaves settings unchanged." if editable else session.progress_text() + ". Settings are locked until New Session.")


## Start with one validated configuration; rules and bankroll become fixed for this session.
func _on_rules_confirmed() -> void:
	var selected: Array[StringName] = []
	for id in rule_checkboxes:
		if rule_checkboxes[id].button_pressed:
			selected.append(id)
	if not session.start_session(int(rounds_spin.value), starting_money_spin.value, rule_mode_option.get_selected_id(), selected, int(random_count_spin.value)):
		return
	game = session.game
	_results_shown = false
	_selecting_reroll = false
	_last_active_hand = -1
	bet_spin_box.value = minf(10.0, session.starting_money)
	_refresh_ui()


## Show final settled money and net, with room exploration and a new session as choices.
func _build_results_dialog() -> void:
	results_dialog = AcceptDialog.new()
	results_dialog.title = "Session Results"
	results_dialog.exclusive = true
	results_dialog.get_ok_button().text = "Back to Room"
	results_dialog.confirmed.connect(func(): leave_requested.emit())
	results_dialog.add_button("New Session", false, "new_session")
	results_dialog.custom_action.connect(func(action: StringName):
		if action == &"new_session":
			_on_restart_pressed())
	add_child(results_dialog)
	var layout := VBoxContainer.new()
	layout.custom_minimum_size = Vector2(400, 240)
	layout.size = Vector2(440, 280)
	layout.add_theme_constant_override("separation", 14)
	results_dialog.add_child(layout)
	var title := _label("SESSION COMPLETE", 24, GOLD)
	title.max_lines_visible = 1
	title.size.x = 400
	layout.add_child(title)
	results_details = _label("", 18, INK)
	results_details.max_lines_visible = 6
	results_details.size.x = 400
	layout.add_child(results_details)
	results_net = _label("", 24, MUTED)
	results_net.max_lines_visible = 1
	results_net.size.x = 400
	layout.add_child(results_net)
	var note := _label("Keep exploring the lounge or start a new session.", 16, MUTED)
	note.max_lines_visible = 2
	note.size.x = 400
	layout.add_child(note)


func _show_session_results() -> void:
	if session.phase != BlackjackSession.Phase.FINISHED or results_dialog == null:
		return
	modal_opened.emit()
	results_details.text = "%s\nRounds completed: %d / %d\nStarting money: $%.2f\nFinal balance: $%.2f" % [session.finish_reason, session.completed_rounds, session.round_limit, session.starting_money, game.player.money]
	results_net.text = "Total net: " + _money_delta(session.net_result())
	results_net.add_theme_color_override("font_color", _delta_color(session.net_result()))
	results_dialog.popup_centered_clamped(Vector2i(460, 330), 0.9)


## Send the dropdown choice through the same validation as clicking a 3D card.
func _replace_selected_card() -> void:
	if _selecting_reroll and card_selector.selected >= 0:
		_choose_reroll_card(game.player.active_hand_index, card_selector.get_selected_id())
