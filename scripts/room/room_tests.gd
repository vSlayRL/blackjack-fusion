extends Node
## Integration checks for the physical room, shared settings, and existing rule actions through the 3D HUD.

var _failures: int = 0
var _room: SpaceLounge
var _fixture: Node


## Run asynchronously so controls, camera layout, and collision picking have initialized.
func _ready() -> void:
	_run.call_deferred()


## Record failures without aborting later checks or falsely reporting an asynchronous pass.
func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


## Wait for deferred layouts and physics updates after changing a room view.
func _frames(count: int = 5) -> void:
	for frame in range(count):
		await get_tree().process_frame


## Reuse prescribed deals that run the real engine and special-rule lifecycle.
func _scenario(player_cards: Array[int], dealer_cards: Array[int], draws: Array[int], reroll: bool = false, second_chance: bool = false, lucky_nine: bool = false, target: int = 0, mystery: bool = false) -> BlackjackGame:
	return _fixture._scenario(player_cards, dealer_cards, draws, 10.0, 100.0, reroll, second_chance, lucky_nine, target, mystery)


## Install a deterministic game and synchronize the same HUD/model path used by real buttons.
func _show_game(game: BlackjackGame) -> void:
	# Prescribed fixtures are already accepted engine deals; attach a fresh long session.
	_room.hud.results_dialog.hide()
	_room.hud.session = BlackjackSession.new()
	_room.hud.session.start_session(100, 100.0, RuleManager.RuleMode.OFF, [], 1)
	_room.hud.session.game = game
	_room.hud.session._round_pending = true
	_room.hud._results_shown = false
	_room.hud.game = game
	_room.hud._refresh_ui()


## Approach a station with the walking camera, keeping proximity checks in the interaction path.
func _approach(station: StringName) -> void:
	_room.explorer.position = Vector3(0, 0, 3.8) if station == &"table" else Vector3(5.7, 0, -1.9)
	_room.explorer.rotation.y = 0
	_room.explorer.camera.rotation.x = 0


## Exercise console Apply/Cancel and camera transitions without resetting the shared session.
func _test_stations() -> void:
	_expect(not _room.try_interact(), "An out-of-range station must not open.")
	_room.hud.deal_button.pressed.emit()
	_expect(_room.hud.session.phase == BlackjackSession.Phase.SETUP and _room.hud.game.player.hand.cards.is_empty(), "A session must be configured before dealing.")
	_approach(&"console")
	_expect(_room.try_interact() and _room.mode == SpaceLounge.RoomMode.CONSOLE, "Nearby console should open session settings.")
	_expect(_room.hud.rule_dialog.visible and not _room.explorer.controls_enabled, "Console UI suspends movement.")
	_room.hud.rounds_spin.value = 3
	_room.hud.starting_money_spin.value = 250
	_room.hud.rule_mode_option.select(RuleManager.RuleMode.RANDOM_SELECTED)
	for id in _room.hud.rule_checkboxes:
		_room.hud.rule_checkboxes[id].button_pressed = id in [&"reroll", &"second_chance"]
	_room.hud.random_count_spin.value = 2
	_room.hud.rule_dialog.canceled.emit()
	_room.hud.rule_dialog.hide()
	_expect(_room.hud.session.phase == BlackjackSession.Phase.SETUP and _room.hud.session.starting_money == 100.0 and _room.hud.game.rules.rule_mode == RuleManager.RuleMode.OFF, "Cancel must discard all draft session settings.")
	_room.open_console()
	_expect(_room.hud.rounds_spin.value == 10 and _room.hud.starting_money_spin.value == 100, "Reopening setup should restore saved defaults.")
	_room.hud.rule_mode_option.select(RuleManager.RuleMode.RANDOM_SELECTED)
	for id in _room.hud.rule_checkboxes:
		_room.hud.rule_checkboxes[id].button_pressed = id in [&"reroll", &"second_chance"]
	_room.hud.random_count_spin.value = 2
	_room.hud.rule_dialog.confirmed.emit()
	_room.hud.rule_dialog.hide()
	var settings := _room.hud.game.rules.get_configuration()
	_expect(settings.mode == RuleManager.RuleMode.RANDOM_SELECTED and settings.selected.size() == 2 and settings.random_count == 2, "Starting session should commit checked rules and random count.")
	_expect(_room.hud.session.phase == BlackjackSession.Phase.PLAYING and _room.hud.session.completed_rounds == 0, "Session should start before the first deal without counting a round.")
	_expect(_room.mode == SpaceLounge.RoomMode.WALKING and _room.explorer.controls_enabled, "Starting session returns to walking.")
	_expect("RANDOM" in _room.console_label.text and "2 of 2" in _room.console_label.text, "Physical screen should reflect the saved mode/count.")
	_room.open_console()
	_expect(_room.hud.rule_mode_option.disabled and not _room.hud.rounds_spin.editable and _room.hud.rule_dialog.get_ok_button().disabled, "Session settings lock even between deals.")
	var checkbox: CheckBox = _room.hud.rule_checkboxes[&"reroll"]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_room.hud._on_rule_title_input(click, checkbox)
	_expect(checkbox.button_pressed, "Clicking a locked rule title must not toggle its checkbox.")
	_room.hud.rule_dialog.confirmed.emit()
	_room.hud.rule_dialog.hide()
	_expect(_room.hud.game.rules.get_configuration() == settings, "Even direct confirm must not alter locked settings.")
	_approach(&"table")
	var interaction := InputEventKey.new()
	interaction.physical_keycode = KEY_E
	interaction.pressed = true
	get_viewport().push_input(interaction, true)
	_expect(_room.mode == SpaceLounge.RoomMode.TABLE and _room.table_camera.current, "E at the chair should activate the table camera.")
	_expect(not _room.explorer.controls_enabled and _room.hud.get_node("WindowMargin").visible, "Seating should enable HUD and suspend walking.")
	print("PASS: Session console draft/cancel/start, settings/title locks, Random count, and E seating.")


## Play through real Hit/Stand buttons, prevent wager abandonment, and retain results after reseating.
func _test_classic_round() -> void:
	_show_game(_scenario([10, 6], [10, 7], [2]))
	_expect(not _room.leave_table() and _room.hud.leave_button.disabled and _room.hud.restart_button.disabled, "Active rounds must lock Leave and Restart.")
	_expect(not _room.open_console(), "The console cannot change an active round.")
	_room.hud.hit_button.pressed.emit()
	_expect(_room.hud.game.player.hand.get_total() == 18, "3D HUD Hit should use the existing engine.")
	_room.hud.stand_button.pressed.emit()
	_expect(_room._hand_labels[0].text.contains("Total: 17"), "Dealer tabletop display must reveal the complete total at settlement.")
	_expect(_room.hud.game.round_over and _room.hud.game.player.money == 110.0, "3D round should settle to the expected bankroll.")
	_expect(_room.hud.round_delta_label.visible and _room.hud.round_delta_label.text.contains("+$10.00"), "HUD should show green net winnings after settlement.")
	_expect(not _room._cards["dealer:1"].concealed, "Dealer hole card reveals at settlement.")
	var same_game := _room.hud.game
	_expect(_room.leave_table() and _room.explorer.camera.current, "Completed rounds should return to the walking camera.")
	_approach(&"table")
	_expect(_room.sit_at_table() and _room.hud.game == same_game and same_game.player.money == 110.0, "Reseating must retain money and game state.")
	_room.hud.deal_button.pressed.emit()
	_expect(not _room.hud.game.has_round_result and not _room.hud.round_delta_label.visible, "New round clears the previous net result.")
	print("PASS: 3D round settlement, active-round locks, reseating persistence, and next-deal net clearing.")


## Hide rank/suit/total, finalize Mystery Card, and consume Reroll through an actual world-card ray hit.
func _test_mystery_and_picking() -> void:
	_show_game(_scenario([10, 6], [10, 7], [8, 2], true, true, true, 25, true))
	_expect(_room._hand_labels[0].text.contains("Showing: 10 + ?") and not _room._hand_labels[0].text.contains("17"), "Dealer tabletop display must show only the visible card before settlement.")
	var hidden_card := _room._cards["player:0:1"]
	_expect(hidden_card.concealed and hidden_card.rank_label.text.is_empty() and hidden_card.suit_label.text.is_empty(), "Mystery mesh must not display hidden rank/suit.")
	_expect("?" in _room._hand_labels[1].text and _room.hud.hit_button.disabled, "Mystery total/actions remain concealed and locked.")
	_room.hud.keep_mystery_button.pressed.emit()
	_expect(not hidden_card.concealed and hidden_card.rank_label.text == "6♣" and _room._cards["dealer:1"].concealed, "Keep reveals only the player's card.")
	_room.hud.reroll_button.pressed.emit()
	await get_tree().create_timer(0.85).timeout
	_room.focus_table()
	var screen_position := _room.table_camera.unproject_position(hidden_card.global_position)
	_expect(_room.pick_card(screen_position) == hidden_card, "Ray picking should identify the highlighted physical card.")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen_position
	get_viewport().notify_mouse_entered()
	get_viewport().push_input(click, true)
	click.pressed = false
	get_viewport().push_input(click, true)
	_expect(_room.hud.game.player.hand.get_total() == 18 and not _room.hud._selecting_reroll, "Clicking the 3D card should apply one Reroll.")
	_expect((_room.hud.game.rules.get_rule(&"reroll") as RerollRule).has_used(_room.hud.game.player), "World selection must consume the shared Reroll allowance once.")
	_show_game(_scenario([14, 6], [14, 10], [10], false, false, false, 0, true))
	_room.hud.replace_mystery_button.pressed.emit()
	_expect(_room.hud.game.result == BlackjackGame.RoundResult.PUSH, "Replacement natural and dealer natural should push in 3D too.")
	_expect(not _room._cards["dealer:1"].concealed, "Opening Blackjack resolution should reveal dealer cards.")
	print("PASS: 3D Mystery secrecy, world-card Reroll selection, and replacement Blackjack push.")


## Keep the special payout/recovery choice and Lucky 9 bonus on the existing settlement path.
func _test_special_payouts() -> void:
	_show_game(_scenario([10, 6], [10, 7], [9], true, true, true, 25, false))
	_room.hud.hit_button.pressed.emit()
	_expect(_room.hud.game.is_awaiting_second_chance() and _room.hud.stand_button.text == "Take Payout", "Exact target bust should offer payout or recovery.")
	_room.hud.stand_button.pressed.emit()
	_expect(_room.hud.game.player.money == 102.5 and _room.hud.game.last_round_delta == 2.5, "Double Target should return 1.25 times the stake.")
	_show_game(_scenario([10, 6], [10, 7], [9, 2], true, true, false, 25, false))
	_room.hud.hit_button.pressed.emit()
	_room.hud.second_chance_button.pressed.emit()
	_expect(_room.hud.game.player.hand.get_total() == 16 and _room.hud.game.is_player_turn(), "Second Chance should recover the recorded bust.")
	_room.hud.hit_button.pressed.emit()
	_room.hud.stand_button.pressed.emit()
	_expect(_room.hud.game.player.money == 110.0, "Recovered hand should settle normally.")
	_show_game(_scenario([4, 5], [10, 7], [10], false, false, true))
	_room.hud.hit_button.pressed.emit()
	_room.hud.stand_button.pressed.emit()
	_expect(_room.hud.game.player.money == 115.0 and _room.hud.game.player.hands[0].lucky_nine_bonus == 5.0, "Lucky 9 should retain its opening-wager bonus in 3D.")
	print("PASS: 3D Double Target choice, Second Chance recovery, and Lucky 9 bonus.")


## Exercise four separate hands and confirm HUD controls stay inside all supported window sizes.
func _test_splits_and_sizes() -> void:
	_show_game(_scenario([8, 8], [10, 7], [8, 8, 8, 8, 2, 3, 4, 5, 10], true, true, true, 25))
	for split in range(3):
		_room.hud.split_button.pressed.emit()
	_expect(_room.hud.game.player.hands.size() == 4 and _room.hud.game.player.total_bet() == 40.0, "3D Split should preserve four per-hand wagers.")
	_expect(_room._cards.size() == 10 and _room._hand_labels.size() == 5, "All four hands and dealer should have physical cards and one tabletop display per hand.")
	for window_size in [Vector2i(640, 560), Vector2i(960, 640), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080)]:
		get_viewport().size = window_size
		await _frames(8)
		_expect(_room.hud.play_area.size.y >= 140.0, "3D table must retain a visible central area.")
		for button in [_room.hud.hit_button, _room.hud.stand_button, _room.hud.split_button, _room.hud.reroll_button]:
			var bounds: Rect2 = button.get_global_rect()
			_expect(bounds.position.y >= 0.0 and bounds.end.y <= window_size.y + 1.0 and bounds.end.x <= window_size.x + 1.0, "3D action buttons must fit the window.")
	_room.hud.double_button.pressed.emit()
	_expect(_room.hud.game.player.hands[0].doubled and _room.hud.game.player.hands[0].wager == 20.0, "3D Double should retain the doubled hand wager.")
	for remaining_hand in range(8):
		if _room.hud.game.round_over:
			break
		_room.hud.stand_button.pressed.emit()
	_expect(_room.hud.game.has_round_result, "All split hands should settle in one round.")
	_expect(not _room.hud.get_node("WindowMargin/Layout/Header/Stats/BetGroup").is_visible_in_tree() and not _room.hud.status_label.is_visible_in_tree(), "Screen overlay must omit hand/wager summaries and duplicate status text.")
	_expect(is_equal_approx(_room.table_camera.position.y, _room.seated_eye_height) and _room.seated_eye_height > 1.95, "Seated eye height should be raised and configurable.")
	print("PASS: 3D four-hand Split/Double and responsive HUD bounds.")


## Reproduce the original repeated-Hit overflow with all five rules and a Lucky 9 hand.
func _test_hit_controls() -> void:
	for window_size in [Vector2i(640, 560), Vector2i(960, 640), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080)]:
		get_viewport().size = window_size
		_show_game(_scenario([4, 5], [10, 7], [2, 2, 2, 2, 2, 2], true, true, true, 25, true))
		_room.hud.keep_mystery_button.pressed.emit()
		await _frames(8)
		for hit in range(5):
			var before := _room.hud.game.player.hand.get_total()
			# Dispatch a real click through the GUI, rather than emitting the button signal.
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.position = _room.hud.hit_button.get_global_rect().get_center()
			click.pressed = true
			get_viewport().push_input(click, true)
			click.pressed = false
			get_viewport().push_input(click, true)
			await _frames(8)
			_expect(_room.hud.game.player.hand.get_total() == before + 2, "Each visible Hit button must still receive GUI clicks.")
			for button in [_room.hud.hit_button, _room.hud.stand_button, _room.hud.reroll_button]:
				var rect: Rect2 = button.get_global_rect()
				_expect(button.is_visible_in_tree() and rect.position.y >= 0.0 and rect.end.y <= window_size.y, "Repeated Hits must not move playable controls offscreen.")
			_expect(_room.hud.play_area.size.y >= 140.0, "Repeated Hits should preserve room visibility.")
		_room.hud.stand_button.pressed.emit()
		_expect(_room.hud.game.round_over, "Stand must remain usable after repeated Hits.")
	print("PASS: Actual GUI clicks after five Hits at five window sizes retain visible controls.")


## Seated mouse look survives game/layout updates; toys remain independent of wagers and rules.
func _test_look_and_props() -> void:
	get_viewport().size = Vector2i(1280, 720)
	_show_game(_scenario([10, 6], [10, 7], [2], true, true, false))
	_room.focus_table()
	await _frames(8)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	get_viewport().push_input(right, true)
	_expect(_room.looking, "Right mouse must enter seated look through actual input dispatch.")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(280, -30)
	get_viewport().push_input(motion, true)
	var turned := _room.table_camera.rotation
	_expect(absf(turned.y) > 0.7 and turned.x != SpaceLounge.DEFAULT_PITCH, "Mouse movement should turn the perspective camera.")
	right.pressed = false
	get_viewport().push_input(right, true)
	_expect(not _room.looking, "Releasing right mouse restores clicking.")
	_room.hud.hit_button.pressed.emit()
	get_viewport().size = Vector2i(960, 640)
	await _frames(8)
	_expect(_room.table_camera.rotation.is_equal_approx(turned), "Hit and resizing must not reset the player's view.")
	var focus_key := InputEventKey.new()
	focus_key.physical_keycode = KEY_C
	focus_key.pressed = true
	get_viewport().push_input(focus_key, true)
	_expect(_room.table_camera.rotation.is_equal_approx(Vector3(SpaceLounge.DEFAULT_PITCH, 0, 0)), "C should restore the card-facing view.")
	var bank := _room.hud.game.player.money
	var total := _room.hud.game.player.hand.get_total()
	var remaining_draws := _room.hud.game.deck.cards.size()
	for toy in _room.get_node("TableToys").get_children():
		var prop := toy as LoungeProp
		_room.table_camera.look_at(prop.global_position)
		await get_tree().physics_frame
		await _frames(8)
		var screen := _room.table_camera.unproject_position(prop.global_position)
		_expect(_room.pick_prop(screen) == prop, "Ray picking should find the nearby toy.")
		var count := prop.interaction_count
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = screen
		click.pressed = true
		get_viewport().push_input(click, true)
		click.pressed = false
		get_viewport().push_input(click, true)
		_expect(prop.interaction_count == count + 1, "World click should interact with each toy during an active round.")
		await get_tree().physics_frame
		await get_tree().physics_frame
		if prop.kind == LoungeProp.Kind.LIGHT:
			_expect(prop.warm_light, "Clicking the orb should change its glow.")
		else:
			_expect(prop.angular_velocity.length() > 0.0, "A nudge should spin the physical toy.")
	# E targets the view center during mouse-look, including while a hand is unfinished.
	var orb := _room.get_node("TableToys/GlowOrb") as LoungeProp
	_room.table_camera.look_at(orb.global_position)
	_room._set_looking(true)
	var use := InputEventKey.new()
	use.physical_keycode = KEY_E
	use.pressed = true
	get_viewport().push_input(use, true)
	_expect(orb.interaction_count == 2 and not orb.warm_light, "E while looking should toggle the orb without leaving the active round.")
	_room._notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_expect(not _room.looking, "Window focus loss must release seated look.")
	_expect(_room.hud.game.player.money == bank and _room.hud.game.player.hand.get_total() == total and _room.hud.game.deck.cards.size() == remaining_draws and _room.hud.game.is_player_turn(), "Toys must not alter chips, cards, draws, or round phase.")
	_expect(not (_room.hud.game.rules.get_rule(&"reroll") as RerollRule).has_used(_room.hud.game.player) and not (_room.hud.game.rules.get_rule(&"second_chance") as SecondChanceRule).has_used(_room.hud.game.player), "Toy interactions must not consume rule allowances.")
	_room.focus_table()
	_room.hud.stand_button.pressed.emit()
	print("PASS: Seated look, focus shortcut, resize persistence, focus-loss release, and physical toy clicks.")


## Step real physics, rather than comparing the new damping/spring settings to themselves.
func _physics_frames(count: int) -> void:
	for frame in range(count):
		await get_tree().physics_frame


## Verify long-range drift, physical bounces, toy-to-toy contact, and walking interaction.
func _test_free_toys() -> void:
	var die := LoungeProp.new()
	die.position = Vector3(3.5, 2.5, 1.5)
	_room.add_child(die)
	await _physics_frames(2)
	var start := die.global_position
	die.interact(Vector3.RIGHT)
	await _physics_frames(120)
	_expect(die.global_position.distance_to(start) > 1.5 and die.linear_velocity.x > 0.8, "Pushed toys should drift away from their starting point instead of springing back.")
	_expect(absf(die.global_position.y - start.y) < 0.01, "A free toy should remain in zero gravity.")
	die.global_position = Vector3(6.35, 2.5, 1.0)
	die.linear_velocity = Vector3(2.0, 0.0, 0.0)
	die.angular_velocity = Vector3.ZERO
	await _physics_frames(45)
	_expect(die.linear_velocity.x < -0.5 and die.global_position.x < 6.7, "Room walls should rebound drifting toys.")
	die.global_position = Vector3(3.5, 4.3, 1.0)
	die.linear_velocity = Vector3(0.0, 2.0, 0.0)
	await _physics_frames(35)
	_expect(die.linear_velocity.y < -0.5 and die.global_position.y < 4.6, "Ceiling collision should keep toys inside the room.")
	die.global_position = Vector3(3.5, 0.4, 1.0)
	die.linear_velocity = Vector3(0.0, -2.0, 0.0)
	await _physics_frames(35)
	_expect(die.linear_velocity.y > 0.5 and die.global_position.y > 0.15, "Floor collision should bounce toys instead of letting them fall through.")
	var orb := LoungeProp.new()
	orb.kind = LoungeProp.Kind.LIGHT
	orb.position = Vector3(4.0, 2.5, 3.0)
	_room.add_child(orb)
	die.global_position = Vector3(3.35, 2.5, 3.0)
	die.linear_velocity = Vector3(2.0, 0.0, 0.0)
	await _physics_frames(45)
	_expect(orb.global_position.x > 4.25 and orb.linear_velocity.x > 0.5, "Toys should transfer momentum to one another, including the previously frozen orb.")
	_expect(_room.leave_table(), "A completed hand should allow following toys into the room.")
	_room.explorer.position = Vector3(3.5, 0, 4.4)
	_room.explorer.rotation.y = 0
	_room.explorer.camera.rotation.x = 0
	die.global_position = Vector3(3.5, 1.65, 2.5)
	die.linear_velocity = Vector3.ZERO
	await _physics_frames(2)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = _room.explorer.camera.unproject_position(die.global_position)
	click.pressed = true
	var before := die.interaction_count
	get_viewport().push_input(click, true)
	click.pressed = false
	get_viewport().push_input(click, true)
	_expect(die.interaction_count == before + 1 and _room.mode == SpaceLounge.RoomMode.WALKING, "Walking players should be able to click and push toys they follow around the room.")
	die.queue_free()
	orb.queue_free()
	print("PASS: Free drift, zero gravity, wall/ceiling/floor bounces, toy collisions, and walking toy clicks.")


## Dispatch actual physical keys so movement polling and world shortcuts share player input.
func _key(code: Key, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


## Hold, turn, drop, and regrab a real toy while an unfinished hand retains its state.
func _test_pickup() -> void:
	_approach(&"table")
	_expect(_room.sit_at_table(), "Pickup scenario should start at the table.")
	_show_game(_scenario([10, 6], [10, 7], [2], true, true))
	var game := _room.hud.game
	var cards_left := game.deck.cards.size()
	_room.table_camera.rotation = Vector3.ZERO
	var toy := LoungeProp.new()
	_room.add_child(toy)
	toy.global_position = _room.table_camera.global_position + Vector3(0, 0, -1.6)
	await _physics_frames(3)
	_room._set_looking(true)
	_key(KEY_F)
	_key(KEY_F, false)
	_expect(_room.held_prop == toy and toy.held, "F should grab the center-aimed toy while a hand is active.")
	await _physics_frames(35)
	_expect(toy.global_position.distance_to(_room._hold_position()) < 0.08, "Held toy should settle in front of the view.")
	var old_position := toy.global_position
	_room.table_camera.rotation.y = 0.7
	await _physics_frames(35)
	_expect(toy.global_position.distance_to(old_position) > 0.5 and toy.global_position.distance_to(_room._hold_position()) < 0.08, "Turning should carry the toy rather than leave it anchored.")
	# Drop during a turn: modest momentum should survive instead of returning to a hold target.
	_room.table_camera.rotation.y = 1.0
	await _physics_frames(3)
	_key(KEY_F)
	_key(KEY_F, false)
	_expect(_room.held_prop == null and not toy.held, "F again must release the single held toy.")
	var released := toy.global_position
	await _physics_frames(25)
	_expect(toy.global_position.distance_to(released) > 0.1, "Dropped toy should continue floating with release momentum.")
	_expect(game.player.money == 90.0 and game.player.hand.get_total() == 16 and game.deck.cards.size() == cards_left and game.is_player_turn(), "Holding and dropping must not change wagers, cards, deck, or phase.")
	_expect(not (game.rules.get_rule(&"reroll") as RerollRule).has_used(game.player), "Pickup must not spend Reroll.")
	_key(KEY_SPACE)
	_key(KEY_SPACE, false)
	_key(KEY_SHIFT)
	_key(KEY_W)
	var seated_position := _room.explorer.position
	await _physics_frames(20)
	_key(KEY_W, false)
	_key(KEY_SHIFT, false)
	_expect(_room.explorer.position.distance_to(seated_position) < 0.02, "Space and sprint must not move the seated walking body.")
	_room._set_looking(false)
	_room.hud.stand_button.pressed.emit()
	_room.leave_table()
	# The headless display cannot capture a cursor; rendered runs cover the walking half.
	if DisplayServer.get_name() == "headless":
		toy.queue_free()
		print("PASS: Seated pickup, turning, release drift, and unchanged Blackjack state. Walking pickup needs a rendered window.")
		return
	_room.explorer.position = Vector3(3.5, 0, 3.5)
	_room.explorer.rotation = Vector3.ZERO
	_room.explorer.camera.rotation = Vector3.ZERO
	toy.global_position = Vector3(3.5, 1.65, 1.9)
	toy.linear_velocity = Vector3.ZERO
	await _physics_frames(3)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_key(KEY_F)
	_key(KEY_F, false)
	_expect(_room.held_prop == toy, "Walking players should also grab using F.")
	_key(KEY_W)
	await _physics_frames(20)
	_key(KEY_W, false)
	await _physics_frames(20)
	_expect(toy.global_position.distance_to(_room._hold_position()) < 0.1, "Walking should carry the held toy with the camera.")
	# Face the wall from close by; the hold target and physical body must remain inside it.
	_room.explorer.position = Vector3(6.15, 0, 1.0)
	_room.explorer.rotation.y = -PI / 2.0
	toy.global_position = Vector3(6.3, 1.65, 1.0)
	await _physics_frames(35)
	_expect(toy.global_position.x < 6.7 and toy.held, "Held objects must stay inside the wall instead of teleporting through it.")
	_room.explorer.reset_view()
	_expect(_room.held_prop == null and not toy.held, "Reset must drop the toy before teleporting the player.")
	# Entering the console also releases toys and leaves typing to the settings controls.
	_approach(&"console")
	toy.global_position = _room.explorer.camera.global_position + Vector3(0, 0, -0.6)
	toy.linear_velocity = Vector3.ZERO
	await _physics_frames(3)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_key(KEY_F)
	_key(KEY_F, false)
	_expect(_room.held_prop == toy, "Console approach should still allow holding a toy.")
	_expect(_room.open_console() and _room.held_prop == null and not toy.held, "Opening a station must drop the toy.")
	_expect(not _room.toggle_pickup(), "Pickup must be suspended while the console is open.")
	_room.hud.rule_dialog.hide()
	toy.queue_free()
	_room.explorer.reset_view()
	print("PASS: F pickup/drop, camera/walking carry, release drift, wall collision, station/reset release, and unchanged Blackjack state.")


## Measure a short jump and real sprint travel, including a landing on the table.
func _test_movement() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP: Sprint/jump input requires mouse capture in a rendered game window.")
		return
	_room.explorer.position = Vector3(-3.5, 0, 3.8)
	_room.explorer.rotation = Vector3.ZERO
	_room.explorer.camera.rotation = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _physics_frames(5)
	var origin := _room.explorer.position
	_key(KEY_W)
	await _physics_frames(20)
	_key(KEY_W, false)
	var walked := origin.distance_to(_room.explorer.position)
	_room.explorer.position = origin
	_key(KEY_W)
	_key(KEY_SHIFT)
	await _physics_frames(20)
	_key(KEY_W, false)
	_key(KEY_SHIFT, false)
	var sprinted := origin.distance_to(_room.explorer.position)
	print("Movement distances: walk=", walked, " sprint=", sprinted)
	_expect(walked > 0.9 and sprinted > walked * 1.45 and sprinted < walked * 1.8, "Shift should provide a controlled sprint faster than ordinary walking.")
	_room.explorer.position = origin
	await _physics_frames(5)
	_key(KEY_SPACE)
	_key(KEY_SPACE, false)
	var peak := origin.y
	var airborne_frames := 0
	var apex_frames := 0
	for frame in range(150):
		await _physics_frames(1)
		peak = maxf(peak, _room.explorer.position.y)
		if _room.explorer.position.y > origin.y + 0.05:
			airborne_frames += 1
		if absf(_room.explorer.velocity.y) < 0.65 and _room.explorer.position.y > origin.y + 0.5:
			apex_frames += 1
		if frame == 15:
			var upward := _room.explorer.velocity.y
			_key(KEY_SPACE)
			_key(KEY_SPACE, false)
			_expect(_room.explorer.velocity.y <= upward, "Pressing Space airborne must not trigger another jump.")
	print("Jump: height=", peak - origin.y, " airborne frames=", airborne_frames, " glide frames=", apex_frames)
	_expect(peak - origin.y > 1.15 and peak - origin.y < 1.5, "Jump height should reach the table without approaching the room ceiling.")
	_expect(airborne_frames > 65 and airborne_frames < 110 and apex_frames >= 18, "Jump should have a brief glide and land in under two seconds.")
	_expect(_room.explorer.is_on_floor() and absf(_room.explorer.position.y - origin.y) < 0.05, "Spacey jump should return to the floor.")
	# Holding Space after a fresh press should not keep bouncing after landing.
	_key(KEY_SPACE)
	await _physics_frames(145)
	_expect(_room.explorer.is_on_floor(), "Holding Space must not auto-jump again after landing.")
	_key(KEY_SPACE, false)
	# Approach the side edge away from the front chair, then jump onto the actual tabletop.
	_room.explorer.position = Vector3(3.25, 0, 0)
	_room.explorer.rotation.y = PI / 2.0
	await _physics_frames(5)
	_key(KEY_SPACE)
	_key(KEY_SPACE, false)
	_key(KEY_W)
	await _physics_frames(32)
	_key(KEY_W, false)
	await _physics_frames(80)
	_expect(_room.explorer.is_on_floor() and _room.explorer.position.y > 1.0 and _room.explorer.position.y < 1.3, "A player should be able to jump and land on the Blackjack table.")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var stopped := _room.explorer.position
	_key(KEY_W)
	_key(KEY_SHIFT)
	_key(KEY_SPACE)
	_key(KEY_SPACE, false)
	await _physics_frames(20)
	_key(KEY_W, false)
	_key(KEY_SHIFT, false)
	_expect(_room.explorer.position.distance_to(stopped) < 0.02, "Released cursor should suspend sprint and jumping.")
	_room.explorer.reset_view()
	print("PASS: Shift sprint distance, room-sized jump/glide/landing, no air jumps or auto-hop, table landing, and cursor suspension.")


## Run the room scenarios and exit with a clear nonzero result on any failure.
func _run() -> void:
	get_viewport().gui_embed_subwindows = true
	get_viewport().size = Vector2i(960, 640)
	_room = preload("res://scenes/room/space_lounge.tscn").instantiate() as SpaceLounge
	_fixture = load("res://scripts/tests.gd").new()
	add_child(_room)
	await _frames()
	_test_stations()
	_test_classic_round()
	await _test_mystery_and_picking()
	_test_special_payouts()
	await _test_splits_and_sizes()
	await _test_hit_controls()
	await _test_look_and_props()
	await _test_free_toys()
	await _test_pickup()
	await _test_movement()
	_fixture.free()
	print("ALL 3D ROOM TESTS PASSED" if _failures == 0 else "%d 3D ROOM CHECKS FAILED" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
