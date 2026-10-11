extends Node
## Session stories use actual accepted deals, HUD controls, and the existing Blackjack engine.

var _failures: int = 0
var _room: SpaceLounge

class SessionDeck extends Deck:
	var draw_order: Array[Card] = []
	func reset() -> void:
		cards.assign(draw_order)
		cards.reverse()


func _ready() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _frames(count: int = 8) -> void:
	for frame in range(count):
		await get_tree().process_frame


## Prescribe the shoe before Deal; start_round still resets, bets, activates rules, and deals.
func _shoe(ranks: Array[int]) -> void:
	var deck := SessionDeck.new()
	for rank in ranks:
		deck.draw_order.append(Card.new(Card.Suit.CLUBS, rank))
	_room.hud.game.deck = deck


func _start(rounds: int, money: float, mode: int, selected: Array[StringName], count: int = 1) -> void:
	_room.hud.rounds_spin.value = rounds
	_room.hud.starting_money_spin.value = money
	_room.hud.rule_mode_option.select(mode)
	for id in _room.hud.rule_checkboxes:
		_room.hud.rule_checkboxes[id].button_pressed = selected.has(id)
	_room.hud.random_count_spin.value = count
	_room.hud._update_session_controls()
	_room.hud.rule_dialog.confirmed.emit()
	_room.hud.rule_dialog.hide()
	_room.explorer.position = Vector3(0, 0, 3.8)
	_room.explorer.rotation.y = 0
	_expect(_room.sit_at_table(), "Started session should allow seating.")


## New Session comes from the same results action used by players, opening draft setup.
func _new_session() -> void:
	_room.hud.results_dialog.custom_action.emit(&"new_session")
	_expect(_room.mode == SpaceLounge.RoomMode.CONSOLE and _room.hud.rule_dialog.visible, "New Session should open setup directly.")
	_expect(_room.hud.session.phase == BlackjackSession.Phase.SETUP, "New Session should return to setup.")


## Exercise actual GUI Deal clicks rather than counting fabricated finished game states.
func _deal(ranks: Array[int], wager: float = 10.0) -> void:
	_shoe(ranks)
	_room.hud.bet_spin_box.value = wager
	await _frames()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = _room.hud.deal_button.get_global_rect().get_center()
	click.pressed = true
	get_viewport().push_input(click, true)
	click.pressed = false
	get_viewport().push_input(click, true)


func _run() -> void:
	get_viewport().gui_embed_subwindows = true
	get_viewport().size = Vector2i(960, 640)
	_room = preload("res://scenes/room/space_lounge.tscn").instantiate() as SpaceLounge
	add_child(_room)
	await _frames()
	_room.explorer.position = Vector3(5.7, 0, -1.9)
	_room.explorer.rotation.y = 0
	_expect(_room.open_console(), "Initial console should open setup.")
	_start(3, 50.0, RuleManager.RuleMode.ALL_SELECTED, [&"reroll", &"second_chance", &"mystery_card"])
	var session := _room.hud.session
	_expect(session.game == _room.hud.game and session.game.player.money == 50.0 and session.round_limit == 3, "Start Session should create the configured bankroll and round limit.")
	_expect(not session.begin_round(0.0) and session.completed_rounds == 0, "Invalid wagers cannot consume a session round.")
	_expect(not session.start_session(2, 500.0, RuleManager.RuleMode.OFF, [], 1) and not session.new_session(), "An active session cannot be reconfigured or restarted between rounds.")
	await _deal([14, 14, 10, 10])
	_expect(session.completed_rounds == 0 and session.game.is_awaiting_mystery_card(), "Mystery choice is still part of the current round.")
	_room.hud.keep_mystery_button.pressed.emit()
	_expect(session.completed_rounds == 1 and session.game.player.money == 50.0, "Two opening Blackjacks should push and count exactly one completed round.")
	_room.hud._refresh_ui()
	_room.hud._refresh_ui()
	_expect(session.completed_rounds == 1, "Repeated refreshes must not count settlement again.")
	_expect(_room.leave_table(), "A completed deal should permit room exploration.")
	var saved_game := session.game
	_room.explorer.position = Vector3(0, 0, 3.8)
	_expect(_room.sit_at_table() and session.game == saved_game and session.completed_rounds == 1, "Reseating must retain session game, balance, and progress.")
	await _deal([8, 10, 8, 7, 10, 10, 8, 5])
	_room.hud.keep_mystery_button.pressed.emit()
	_room.hud.split_button.pressed.emit()
	_room.hud.reroll_button.pressed.emit()
	_room.hud._choose_reroll_card(0, 0)
	_room.hud.stand_button.pressed.emit()
	_expect(session.completed_rounds == 1 and session.game.player.active_hand_index == 1, "Finishing the first split hand must not count a new round.")
	_room.hud.hit_button.pressed.emit()
	_room.hud.second_chance_button.pressed.emit()
	_expect(session.completed_rounds == 1 and session.game.player.hand.get_total() == 18, "Second Chance should recover within the same deal.")
	_room.hud.stand_button.pressed.emit()
	_expect(session.completed_rounds == 2 and session.game.player.money == 70.0, "Both winning split hands settle as one round with correct bankroll.")
	await _deal([10, 10, 6, 7, 10])
	_expect(not _room.hud.round_delta_label.visible, "Next accepted deal clears the previous round delta.")
	_room.hud.keep_mystery_button.pressed.emit()
	_room.hud.hit_button.pressed.emit()
	_room.hud.stand_button.pressed.emit()
	await _frames()
	_expect(session.phase == BlackjackSession.Phase.FINISHED and session.completed_rounds == 3 and session.game.player.money == 60.0, "Final deal should finish the session at its configured limit.")
	_expect(_room.hud.results_dialog.visible and _room.hud.results_details.text.contains("3 / 3") and _room.hud.results_net.text.contains("+$10.00"), "Results should show completed rounds and net relative to $50 starting money.")
	_expect(_room.hud.results_net.get_theme_color("font_color") == _room.hud.GAIN, "Positive session net should be green.")
	_room.hud.deal_button.pressed.emit()
	_expect(session.completed_rounds == 3 and session.game.player.money == 60.0 and not session.begin_round(10.0), "No extra deals may start after session completion.")
	_room.hud.results_dialog.confirmed.emit()
	_room.hud.results_dialog.hide()
	_expect(_room.mode == SpaceLounge.RoomMode.WALKING and _room.explorer.controls_enabled, "Results Back to Room should resume exploration.")
	_room.explorer.position = Vector3(5.7, 0, -1.9)
	_room.explorer.rotation.y = 0
	_expect(_room.open_console() and _room.hud.console_new_button.visible, "Finished session can open New Session at the physical console.")
	_room.hud.rule_dialog.custom_action.emit(&"new_session")
	_expect(_room.hud.rounds_spin.value == 3 and _room.hud.starting_money_spin.value == 50.0 and _room.hud.rule_checkboxes[&"mystery_card"].button_pressed, "New Session should retain previous settings as defaults.")
	_start(10, 20.0, RuleManager.RuleMode.OFF, [])
	await _deal([10, 10, 6, 7, 10], 20.0)
	_room.hud.hit_button.pressed.emit()
	await _frames()
	session = _room.hud.session
	_expect(session.phase == BlackjackSession.Phase.FINISHED and session.completed_rounds == 1 and session.game.player.money == 0.0, "Bankruptcy should end the session early without a refill.")
	_expect(_room.hud.results_details.text.contains("1 / 10") and _room.hud.results_net.text.contains("$20.00") and _room.hud.results_net.get_theme_color("font_color") == _room.hud.LOSS, "Early results should show actual rounds and a red loss.")
	_new_session()
	_start(2, 50.0, RuleManager.RuleMode.RANDOM_SELECTED, [&"reroll", &"second_chance", &"mystery_card"], 2)
	for round_index in range(2):
		await _deal([10, 10, 6, 7, 2])
		var active_ids: Array[StringName] = []
		for rule in _room.hud.game.rules.active_rules:
			active_ids.append(rule.rule_id)
		_expect(active_ids.size() == 2 and active_ids[0] != active_ids[1], "Random mode should activate the configured number of distinct checked rules.")
		if _room.hud.game.is_awaiting_mystery_card():
			_room.hud.keep_mystery_button.pressed.emit()
		_room.hud.hit_button.pressed.emit()
		var after_hit: Array[StringName] = []
		for rule in _room.hud.game.rules.active_rules:
			after_hit.append(rule.rule_id)
		_expect(after_hit == active_ids, "Random rule selection must remain fixed for the whole round.")
		_room.hud.stand_button.pressed.emit()
		_expect(_room.hud.session.completed_rounds == round_index + 1, "Each ordinary deal should count once.")
	await _frames()
	_new_session()
	_start(1, 100.0, RuleManager.RuleMode.OFF, [])
	await _deal([10, 2, 6, 2])
	_room.hud.stand_button.pressed.emit()
	_expect(_room.hud.session.completed_rounds == 0 and _room.hud.session.phase == BlackjackSession.Phase.PLAYING and _room.hud.game.player.money == 100.0, "A cancelled dealer draw should refund and preserve the available round.")
	await _deal([14, 10, 10, 7])
	await _frames()
	_expect(_room.hud.session.phase == BlackjackSession.Phase.FINISHED and _room.hud.session.completed_rounds == 1, "Immediate natural Blackjack should finish a one-round session correctly.")
	# Both dialogs and their footer controls must fit the minimum supported window.
	get_viewport().size = Vector2i(640, 560)
	_room.hud._show_session_results()
	await _frames()
	_expect(Rect2i(Vector2i.ZERO, Vector2i(640, 560)).encloses(Rect2i(_room.hud.results_dialog.position, _room.hud.results_dialog.size)), "Final results should fit the smallest window.")
	var result_ok := _room.hud.results_dialog.get_ok_button()
	_expect(Rect2(Vector2.ZERO, Vector2(_room.hud.results_dialog.size)).encloses(result_ok.get_global_rect()), "Results footer buttons must stay inside the dialog.")
	_new_session()
	await _frames()
	_expect(Rect2i(Vector2i.ZERO, Vector2i(640, 560)).encloses(Rect2i(_room.hud.rule_dialog.position, _room.hud.rule_dialog.size)), "Scrollable session settings should fit the smallest window.")
	_expect(Rect2(Vector2.ZERO, Vector2(_room.hud.rule_dialog.size)).encloses(_room.hud.rule_dialog.get_ok_button().get_global_rect()), "Start Session must remain accessible below the scrollable form.")
	for checkbox in _room.hud.rule_checkboxes.values():
		checkbox.button_pressed = false
	_room.hud.rule_mode_option.select(RuleManager.RuleMode.RANDOM_SELECTED)
	_room.hud._update_session_controls()
	_expect(_room.hud.rule_dialog.get_ok_button().disabled, "Random setup with an empty pool must ask for at least one checked rule.")
	_start(1, BlackjackSession.MAX_STARTING_MONEY, RuleManager.RuleMode.OFF, [])
	await _frames()
	_expect(_room.hud.fullscreen_button.get_global_rect().end.x <= 640 and _room.hud.money_label.text == "$100000.00", "Maximum starting money and table utility buttons should fit the minimum window.")
	var model := BlackjackSession.new()
	_expect(not model.start_session(0, 100.0, RuleManager.RuleMode.OFF, [], 1) and not model.start_session(10, INF, RuleManager.RuleMode.OFF, [], 1) and not model.start_session(10, 100.0, RuleManager.RuleMode.RANDOM_SELECTED, [], 1), "Invalid lengths, balances, and an empty Random pool must preserve setup.")
	_expect(model.start_session(2, 1.5, RuleManager.RuleMode.OFF, [], 1), "Starting money at least the minimum bet should be accepted.")
	var loss_deck := SessionDeck.new()
	for rank in [10, 10, 6, 7, 10]:
		loss_deck.draw_order.append(Card.new(Card.Suit.CLUBS, rank))
	model.game.deck = loss_deck
	_expect(model.begin_round(1.0), "A $1 minimum bet should be accepted.")
	model.game.player_hit()
	model.observe_round()
	_expect(model.phase == BlackjackSession.Phase.FINISHED and is_equal_approx(model.game.player.money, 0.5), "An unplayable fractional remainder should end early without topping up.")
	print("ALL SESSION TESTS PASSED" if _failures == 0 else "%d SESSION CHECKS FAILED" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
