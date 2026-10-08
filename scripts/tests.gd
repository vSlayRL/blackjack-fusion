## Story-based logic and UI checks run from scenes/tests.tscn (F6).
## Fixed draw sequences isolate rules; a shuffled demonstration shows normal round flow.
extends Node

var failures: int = 0

# A reproducible shoe still passes through start_round and the real actions.
class ScriptedDeck extends Deck:
	var draw_order: Array[Card] = []

	## Restore the prescribed draw order, reversing it because Deck draws from the back.
	func reset() -> void:
		cards.assign(draw_order)
		cards.reverse()


## Record an expectation failure without skipping later checks; headless execution exits nonzero.
func _expect(condition: bool, message: String = "Gameplay expectation failed") -> void:
	if not condition:
		failures += 1
		push_error(message)


## Run foundational checks, deterministic gameplay stories, and real UI interactions.
## Await layout/input scenarios before reporting success or selecting the headless exit code.
func _ready():
	print("=== BLACKJACK FUSION LOGIC TESTS ===")

	test_card_values()
	test_hand_ace_logic()
	test_deck()
	test_player_betting()
	test_minimum_bet()
	test_player_bust_ends_round()
	test_dealer_turn_and_push()
	test_player_win()
	test_dealer_bust()
	test_complete_random_round()
	test_double_flow()
	test_double_results()
	test_action_restrictions()
	test_split_then_double()
	test_split_bust_then_win()
	test_all_split_hands_bust()
	test_split_aces()
	test_resplit_limit()
	test_split_blackjack_payout()
	test_split_dealer_bust_and_reset()
	test_opening_blackjacks()
	test_empty_deck_protection()
	test_rule_manager()
	test_rule_hooks()
	test_reroll_flow()
	test_reroll_results()
	test_reroll_across_split_hands()
	test_reroll_then_double_and_split()
	test_reroll_rejections()
	test_second_chance_flow()
	test_second_chance_split_and_double()
	test_second_chance_with_reroll()
	test_round_net_results()
	test_lucky_nine_flow()
	test_lucky_nine_outcomes()
	test_lucky_nine_combinations()
	test_double_target_randomization()
	test_double_target_flow()
	test_double_target_second_chance()
	test_double_target_splits()
	test_double_target_combinations()
	test_mystery_card_flow()
	test_mystery_card_blackjacks()
	test_mystery_card_combinations()
	await test_mystery_card_ui()
	await test_playable_ui()
	await test_reroll_ui()
	await test_second_chance_ui()
	await test_lucky_nine_ui()
	await test_double_target_ui()

	if failures == 0:
		print("\n=== ALL LOGIC AND UI TESTS PASSED ===")
	else:
		push_error("%d expectations failed" % failures)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if failures == 0 else 1)


## Check Ace, face-card, and numbered values plus a readable card name.
func test_card_values() -> void:
	var ace := Card.new(Card.Suit.SPADES, Card.Rank.ACE)
	var king := Card.new(Card.Suit.HEARTS, Card.Rank.KING)
	var seven := Card.new(Card.Suit.CLUBS, Card.Rank.SEVEN)

	_expect(ace.get_blackjack_value() == 11)
	_expect(king.get_blackjack_value() == 10)
	_expect(seven.get_blackjack_value() == 7)
	_expect(ace.get_card_name() == "Ace of Spades")

	print("PASS: Card values and names")


## Follow an Ace through a soft total, an extra card, and a fresh two-card Blackjack.
func test_hand_ace_logic() -> void:
	var hand := Hand.new()
	hand.add_card(Card.new(Card.Suit.HEARTS, Card.Rank.ACE))
	hand.add_card(Card.new(Card.Suit.CLUBS, Card.Rank.SEVEN))
	_expect(hand.get_total() == 18)

	hand.add_card(Card.new(Card.Suit.SPADES, Card.Rank.KING))
	_expect(hand.get_total() == 18)
	_expect(not hand.is_bust())

	hand.clear_hand()
	hand.add_card(Card.new(Card.Suit.HEARTS, Card.Rank.ACE))
	hand.add_card(Card.new(Card.Suit.DIAMONDS, Card.Rank.KING))
	_expect(hand.is_blackjack())

	print("PASS: Hand totals, Aces, and Blackjack")


## Draw from a 52-card deck, verify the reduced count, then reset to a full deck.
func test_deck() -> void:
	var deck := Deck.new()
	_expect(deck.cards_remaining() == 52)

	var card := deck.deal_card()
	_expect(card != null)
	_expect(deck.cards_remaining() == 51)

	deck.reset()
	_expect(deck.cards_remaining() == 52)

	print("PASS: Deck creation, dealing, and reset")


## Follow a bankroll through accepted/rejected wagers and win/loss/push payouts.
func test_player_betting() -> void:
	var player := Player.new("Test Player", 100.0)
	_expect(player.place_bet(20.0))
	_expect(player.money == 80.0)
	_expect(not player.place_bet(10.0))

	player.win_bet()
	_expect(player.money == 120.0)
	_expect(player.bet == 0.0)

	_expect(player.place_bet(20.0))
	player.lose_bet()
	_expect(player.money == 100.0)

	_expect(player.place_bet(20.0))
	player.win_blackjack()
	_expect(player.money == 130.0)

	_expect(not player.place_bet(200.0))
	_expect(not player.place_bet(0.0))

	print("PASS: Betting and payouts")


## Reject subminimum wagers and verify a low bankroll cannot start a new round.
func test_minimum_bet() -> void:
	var game := BlackjackGame.new()

	_expect(not game.start_round(0.5))
	_expect(game.player.money == 100.0)
	_expect(game.status_message == "Minimum bet is $1.00.")

	game.player.money = 0.5
	_expect(not game.can_start_round())

	print("PASS: Minimum bet and low-bankroll protection")


## Force a player bust and confirm immediate loss without additional dealer cards.
func test_player_bust_ends_round() -> void:
	var game := _new_active_game(20.0)

	# Replace the random player hand with a guaranteed 19.
	game.player.hand.clear_hand()
	game.player.hand.add_card(Card.new(Card.Suit.HEARTS, Card.Rank.TEN))
	game.player.hand.add_card(Card.new(Card.Suit.CLUBS, Card.Rank.NINE))

	# The next card is guaranteed to make the player bust.
	game.deck.cards.clear()
	game.deck.cards.append(Card.new(Card.Suit.SPADES, Card.Rank.FIVE))

	var dealer_cards_before := game.dealer.hand.card_count()
	_expect(game.player_hit())
	_expect(game.player.hand.is_bust())
	_expect(game.round_over)
	_expect(game.result == BlackjackGame.RoundResult.PLAYER_BUST)
	_expect(game.dealer.hand.card_count() == dealer_cards_before)
	_expect(game.player.bet == 0.0)
	_expect(not game.player_stand())

	print("PASS: Player bust ends the round without a dealer turn")


## Let the dealer hit below 17 and return the wager when final totals tie.
func test_dealer_turn_and_push() -> void:
	var game := _new_active_game(10.0)

	game.player.hand.clear_hand()
	game.player.hand.add_card(Card.new(Card.Suit.HEARTS, Card.Rank.TEN))
	game.player.hand.add_card(Card.new(Card.Suit.CLUBS, Card.Rank.EIGHT))

	game.dealer.hand.clear_hand()
	game.dealer.hand.add_card(Card.new(Card.Suit.DIAMONDS, Card.Rank.TEN))
	game.dealer.hand.add_card(Card.new(Card.Suit.SPADES, Card.Rank.SIX))

	# Dealer has 16 and must draw this 2, ending on 18.
	game.deck.cards.clear()
	game.deck.cards.append(Card.new(Card.Suit.HEARTS, Card.Rank.TWO))

	_expect(game.player_stand())
	_expect(game.dealer.hand.get_total() == 18)
	_expect(game.result == BlackjackGame.RoundResult.PUSH)
	_expect(game.player.money == 100.0)

	print("PASS: Dealer hits below 17 and push returns the bet")


## Stand on a higher player total and check the ordinary winning bankroll.
func test_player_win() -> void:
	var game := _new_active_game(10.0)

	game.player.hand.clear_hand()
	game.player.hand.add_card(Card.new(Card.Suit.HEARTS, Card.Rank.KING))
	game.player.hand.add_card(Card.new(Card.Suit.CLUBS, Card.Rank.NINE))

	game.dealer.hand.clear_hand()
	game.dealer.hand.add_card(Card.new(Card.Suit.DIAMONDS, Card.Rank.TEN))
	game.dealer.hand.add_card(Card.new(Card.Suit.SPADES, Card.Rank.EIGHT))

	_expect(game.player_stand())
	_expect(game.result == BlackjackGame.RoundResult.PLAYER_WIN)
	_expect(game.player.money == 110.0)

	print("PASS: Higher player total wins and pays correctly")


## Stand while the dealer must draw, then verify a dealer bust pays the player.
func test_dealer_bust() -> void:
	var game := _new_active_game(10.0)

	game.player.hand.clear_hand()
	game.player.hand.add_card(Card.new(Card.Suit.HEARTS, Card.Rank.TEN))
	game.player.hand.add_card(Card.new(Card.Suit.CLUBS, Card.Rank.EIGHT))

	game.dealer.hand.clear_hand()
	game.dealer.hand.add_card(Card.new(Card.Suit.DIAMONDS, Card.Rank.TEN))
	game.dealer.hand.add_card(Card.new(Card.Suit.SPADES, Card.Rank.SIX))

	# Dealer has 16 and must draw the King, causing a bust.
	game.deck.cards.clear()
	game.deck.cards.append(Card.new(Card.Suit.HEARTS, Card.Rank.KING))

	_expect(game.player_stand())
	_expect(game.dealer.hand.is_bust())
	_expect(game.result == BlackjackGame.RoundResult.DEALER_BUST)
	_expect(game.player.money == 110.0)

	print("PASS: Dealer bust pays the player")


## Run a normal shuffled round to a valid outcome and print its cards and bankroll.
func test_complete_random_round() -> void:
	var game := BlackjackGame.new()
	_expect(game.start_round(10.0))

	print("\n--- RANDOM ROUND DEMO ---")
	print("Player money after bet: $", game.player.money)
	print("Player hand: ", _hand_to_string(game.player.hand), " = ", game.player.hand.get_total())
	print("Dealer showing: ", game.dealer.hand.cards[0].get_card_name())

	# A starting Blackjack may have already ended the round.
	while game.is_player_turn() and game.player.hand.get_total() < 17:
		game.player_hit()

	if game.is_player_turn():
		game.player_stand()

	_expect(game.round_over)
	_expect(game.player.bet == 0.0)

	print("Dealer hand: ", _hand_to_string(game.dealer.hand), " = ", game.dealer.hand.get_total())
	print("Result: ", game.get_result_text())
	print("Player money: $", game.player.money)
	print("PASS: Complete round reaches a valid finished state")


## Obtain a shuffled playable opening for tests that replace hands with controlled cards.
func _new_active_game(bet_amount: float) -> BlackjackGame:
	# Opening Blackjacks can legitimately end a random round immediately.
	# For tests that need an active player turn, create a fresh game until
	# the opening deal produces a normal playable hand.
	for attempt in range(100):
		var game := BlackjackGame.new()

		if game.start_round(bet_amount) and game.is_player_turn():
			return game

	_expect(false, "Could not create an active test round.")
	return null


## Format hand names for the console demonstration without changing the hand.
func _hand_to_string(hand: Hand) -> String:
	var names: Array[String] = []

	for card in hand.cards:
		names.append(card.get_card_name())

	return ", ".join(names)


## Deal a prescribed opening and draw sequence through real start_round/action code.
## Optional flags configure real rules; deterministic seeds select actual Double Target activation.
func _scenario(player_ranks: Array[int], dealer_ranks: Array[int], draws: Array[int], wager: float = 10.0, bankroll: float = 100.0, reroll_enabled: bool = false, second_chance_enabled: bool = false, lucky_nine_enabled: bool = false, double_target: int = 0, mystery_enabled: bool = false) -> BlackjackGame:
	var game := BlackjackGame.new()
	game.player.money = bankroll
	var selected: Array[StringName] = []
	if reroll_enabled:
		selected.append(&"reroll")
	if second_chance_enabled:
		selected.append(&"second_chance")
	if lucky_nine_enabled:
		selected.append(&"lucky_nine")
	if double_target > 0:
		selected.append(&"double_target")
		(game.rules.get_rule(&"double_target") as DoubleTargetRule)._rng.seed = _seed_for_target(double_target)
	if mystery_enabled:
		selected.append(&"mystery_card")
	if not selected.is_empty():
		_expect(game.configure_rules(RuleManager.RuleMode.ALL_SELECTED, selected))
	var shoe := ScriptedDeck.new()
	shoe.draw_order.append(Card.new(Card.Suit.HEARTS, player_ranks[0]))
	shoe.draw_order.append(Card.new(Card.Suit.SPADES, dealer_ranks[0]))
	shoe.draw_order.append(Card.new(Card.Suit.CLUBS, player_ranks[1]))
	shoe.draw_order.append(Card.new(Card.Suit.DIAMONDS, dealer_ranks[1]))
	for rank in draws:
		shoe.draw_order.append(Card.new(Card.Suit.HEARTS, rank))
	game.deck = shoe
	_expect(game.start_round(wager), "Scenario opening deal failed")
	return game


## Choose one replacement, reject premature/duplicate actions, and reset the choice next round.
## Also cover discarded cards, empty-deck Keep, inactive rules, and five-rule Random selection.
func test_mystery_card_flow() -> void:
	var game := _scenario([10, 6], [10, 7], [8, 2], 10.0, 100.0, true, true, true, 25, true)
	var original := game.player.hand.cards[1]
	var mystery := game.rules.get_rule(&"mystery_card") as MysteryCardRule
	_expect(game.is_awaiting_mystery_card() and not game.is_player_turn() and not game.round_over)
	_expect(game.player.money == 90.0 and not game.has_round_result and not mystery.resolved)
	_expect(game.is_player_card_hidden(0, 1) and not game.is_player_card_hidden(0, 0) and not game.is_player_card_hidden(1, 1))
	_expect(not game.player_hit() and not game.player_stand() and not game.player_double() and not game.player_split())
	_expect(not game.can_reroll() and not game.player_reroll(1) and not game.can_second_chance())
	_expect(not game.configure_rules(RuleManager.RuleMode.OFF, []) and not game.start_round(10.0))
	_expect(game.deck.cards_remaining() == 2 and not mystery.resolved)
	_expect(game.player_choose_mystery_card(true) and mystery.resolved and mystery.replaced)
	_expect(game.is_player_turn() and game.player.hand.get_total() == 18 and game.deck.cards_remaining() == 1)
	_expect(not game.player.hand.cards.has(original) and not game.deck.cards.has(original))
	_expect(not game.is_player_card_hidden(0, 1) and not game.player_choose_mystery_card(true))
	_expect(game.can_reroll() and not (game.rules.get_rule(&"second_chance") as SecondChanceRule).has_used(game.player))
	_expect(game.player_stand() and game.player.money == 110.0 and game.last_round_delta == 10.0)
	_expect(game.start_round(10.0) and game.is_awaiting_mystery_card() and not mystery.resolved)
	_expect(game.player.hand.cards[1] == original and not game.has_round_result, "Deck reset restores discarded card next round")
	_expect(game.player_choose_mystery_card(false) and not mystery.replaced and game.deck.cards_remaining() == 2)
	_expect(not game.player_choose_mystery_card(false) and game.player_stand())
	var empty := _scenario([10, 6], [10, 7], [], 10.0, 100.0, false, false, false, 0, true)
	_expect(not empty.can_replace_mystery_card() and not empty.player_choose_mystery_card(true))
	_expect(empty.is_awaiting_mystery_card() and not (empty.rules.get_rule(&"mystery_card") as MysteryCardRule).resolved)
	_expect(empty.player_choose_mystery_card(false) and empty.player_stand() and empty.player.money == 90.0)
	var off := _scenario([10, 6], [10, 7], [2])
	_expect(not off.is_awaiting_mystery_card() and not off.player_choose_mystery_card())
	var manager := RuleManager.new()
	manager.configure(RuleManager.RuleMode.RANDOM_SELECTED, [&"reroll", &"second_chance", &"lucky_nine", &"double_target", &"mystery_card"], 1)
	manager._rng.seed = 711
	var seen: Dictionary = {}
	for round_number in range(100):
		manager.prepare_round()
		_expect(manager.active_rules.size() == 1)
		seen[manager.active_rules[0].rule_id] = true
	_expect(seen.size() == 5, "Random mode includes all five rules")
	print("PASS: Mystery Card locks opening actions, discards once, preserves other uses, resets next round, and joins Random mode")


## Keep/replace into natural Blackjack, check 3:2 and double-Blackjack pushes, and retain dealer priority.
## A later Reroll to two-card 21 must still pay ordinary winnings.
func test_mystery_card_blackjacks() -> void:
	var both := _scenario([14, 10], [14, 10], [2], 10.0, 100.0, true, true, true, 25, true)
	_expect(not both.round_over and both.result == BlackjackGame.RoundResult.NONE and both.player.money == 90.0)
	_expect(both.player_choose_mystery_card(false) and both.result == BlackjackGame.RoundResult.PUSH and both.player.money == 100.0)
	var new_both := _scenario([14, 5], [14, 10], [13], 10.0, 100.0, false, false, false, 0, true)
	_expect(new_both.player_choose_mystery_card(true) and new_both.player.hands[0].is_natural_blackjack())
	_expect(new_both.result == BlackjackGame.RoundResult.PUSH and new_both.last_round_delta == 0.0)
	var kept := _scenario([14, 10], [10, 9], [], 10.0, 100.0, false, false, false, 0, true)
	_expect(kept.player_choose_mystery_card(false) and kept.result == BlackjackGame.RoundResult.PLAYER_BLACKJACK and kept.player.money == 115.0)
	var replaced := _scenario([10, 5], [10, 7], [14], 10.0, 100.0, true, true, true, 25, true)
	_expect(replaced.player_choose_mystery_card(true) and replaced.result == BlackjackGame.RoundResult.PLAYER_BLACKJACK)
	_expect(replaced.player.money == 115.0 and replaced.last_round_delta == 15.0 and not replaced.player.hands[0].has_been_rerolled)
	var abandoned := _scenario([14, 10], [14, 10], [2], 10.0, 100.0, false, false, false, 0, true)
	_expect(abandoned.player_choose_mystery_card(true) and abandoned.result == BlackjackGame.RoundResult.DEALER_BLACKJACK and abandoned.player.money == 90.0)
	var dealer_only := _scenario([10, 6], [14, 10], [2], 10.0, 100.0, false, false, false, 0, true)
	_expect(dealer_only.player_choose_mystery_card(false) and dealer_only.result == BlackjackGame.RoundResult.DEALER_BLACKJACK)
	var later := _scenario([10, 5], [10, 8], [6, 14], 10.0, 100.0, true, false, false, 0, true)
	_expect(later.player_choose_mystery_card(true) and later.can_reroll() and later.player_reroll(1))
	_expect(later.result == BlackjackGame.RoundResult.PLAYER_WIN and later.player.money == 110.0 and not later.player.hands[0].is_natural_blackjack())
	print("PASS: Kept and replaced opening Blackjack pay 3:2 or push; dealer priority waits for choice; later Reroll stays ordinary 21")


## Qualify Lucky 9 after the opening choice, then combine recovery, Reroll, Double, and Split.
## Check shared Double Target payouts and that opening hooks run exactly once after the choice.
func test_mystery_card_combinations() -> void:
	var lucky := _scenario([4, 10], [10, 7], [5, 10, 6, 10], 10.0, 100.0, true, true, true, 25, true)
	_expect(not lucky.player.hands[0].lucky_nine_qualified)
	_expect(lucky.player_choose_mystery_card(true) and lucky.player.hands[0].lucky_nine_qualified)
	_expect(lucky.player_hit() and lucky.player_hit() and lucky.can_second_chance())
	_expect(lucky.player_second_chance() and lucky.player.hand.get_total() == 19 and lucky.player.hands[0].lucky_nine_qualified)
	_expect(lucky.player_reroll(2) and lucky.player_stand() and lucky.player.money == 115.0)
	var lost_lucky := _scenario([4, 5], [10, 7], [10], 10.0, 100.0, false, false, true, 0, true)
	_expect(lost_lucky.player_choose_mystery_card(true) and not lost_lucky.player.hands[0].lucky_nine_qualified)
	var kept_lucky := _scenario([4, 5], [10, 7], [10], 10.0, 100.0, false, false, true, 0, true)
	_expect(kept_lucky.player_choose_mystery_card(false) and kept_lucky.player.hands[0].lucky_nine_qualified)
	_expect(kept_lucky.player_hit() and kept_lucky.player_stand() and kept_lucky.player.money == 115.0)
	var ace := _scenario([14, 5], [10, 7], [8], 10.0, 100.0, false, false, true, 0, true)
	_expect(ace.player_choose_mystery_card(true) and ace.player.hand.get_total() == 19 and not ace.player.hands[0].lucky_nine_qualified)
	var doubled := _scenario([5, 10], [10, 7], [6, 10], 10.0, 100.0, false, false, false, 0, true)
	_expect(doubled.player_choose_mystery_card(true) and doubled.can_double() and doubled.player_double() and doubled.player.money == 120.0)
	var split := _scenario([8, 5], [10, 7], [8, 10, 10, 7], 10.0, 100.0, true, true, true, 25, true)
	_expect(split.player_choose_mystery_card(true) and split.can_split() and split.player_split())
	_expect(not split.is_awaiting_mystery_card() and not split.player_choose_mystery_card(true) and split.can_reroll())
	_expect(split.player_hit() and split.can_second_chance() and split.player_stand())
	_expect(split.player.active_hand_index == 1 and split.get_double_target() == 25 and split.player_stand())
	_expect(split.player.money == 112.5 and split.last_round_delta == 12.5)
	# Opening hooks run once, after the choice. No pre-choice qualification leak.
	var observed := _scenario([4, 5], [10, 7], [10])
	observed.player_stand()
	var tracker := TrackingRule.new()
	observed.rules.register_rule(tracker)
	observed.configure_rules(RuleManager.RuleMode.ALL_SELECTED, [&"test_rule", &"mystery_card", &"lucky_nine"])
	_expect(observed.start_round(10.0) and tracker.started == 1 and tracker.dealt == 0)
	_expect(observed.player_choose_mystery_card(false) and tracker.dealt == 1 and observed.player.hands[0].lucky_nine_qualified)
	_expect(not observed.player_choose_mystery_card(true) and tracker.dealt == 1)
	print("PASS: Final opening controls Lucky 9; later Reroll/Second Chance preserve it; Double, Split, and Double Target continue normally")


## Use Keep/Replace controls and inspect concealment, totals, dealer secrecy, and final results.
## Exercise an actual Keep click and resize all five active rules across supported window sizes.
func test_mystery_card_ui() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 640)
	add_child(viewport)
	var ui := preload("res://scenes/game.tscn").instantiate()
	viewport.add_child(ui)
	if not ui.has_method("_refresh_ui"):
		_expect(false, "Mystery Card UI script failed to load")
		viewport.free()
		return
	ui._populate_rule_settings()
	ui.rule_mode_option.select(RuleManager.RuleMode.ALL_SELECTED)
	ui.rule_checkboxes[&"mystery_card"].button_pressed = true
	ui.rule_dialog.confirmed.emit()
	_expect(ui.game.rules.selected_rule_ids.has(&"mystery_card") and ui.random_count_spin.max_value == 5)
	ui.game = _scenario([4, 5], [10, 7], [5, 10], 10.0, 100.0, true, true, true, 25, true)
	ui._refresh_ui()
	_expect(ui.active_rules_label.text.contains("Mystery Card") and ui.active_rules_label.text.contains("Double Target: 25"))
	_expect(ui.status_label.text.contains("Mystery Card:") and not ui.round_delta_label.visible)
	_expect(ui.keep_mystery_button.is_visible_in_tree() and not ui.keep_mystery_button.disabled)
	_expect(ui.replace_mystery_button.is_visible_in_tree() and not ui.replace_mystery_button.disabled)
	_expect(not ui.hit_button.is_visible_in_tree() and ui.hit_button.disabled and ui.stand_button.disabled)
	var layout: Node = ui.hand_panels[0].get_node("HandLayout")
	_expect(layout.get_child(0).get_child(1).text == "Total: ?")
	_expect(not layout.has_node("LuckyNineLabel"), "Lucky 9 must not reveal the original concealed total")
	var hidden: Control = layout.get_node("Cards").get_child(1)
	_expect(hidden.get_meta("hidden") and hidden.tooltip_text == "Hidden Card")
	_expect(hidden.get_child(0).get_child(0).text == "?" and hidden.get_child(0).get_child(1).text == "HIDDEN")
	_expect(ui.dealer_cards.get_child(1).get_meta("hidden") and ui.dealer_total_label.text == "Showing: 10")
	for window_size in [Vector2i(640, 560), Vector2i(960, 640), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = window_size
		for frame in range(6):
			await get_tree().process_frame
		for control in [ui.keep_mystery_button, ui.replace_mystery_button, ui.status_label, ui.active_rules_label]:
			_expect(Rect2(Vector2.ZERO, Vector2(window_size)).encloses(control.get_global_rect()), "Mystery controls must fit at %s" % window_size)
		_expect(ui.table_scroll.get_global_rect().encloses(hidden.get_global_rect()), "Hidden card must be visible at %s" % window_size)
	# Exercise an actual mouse click on Keep, including the event wiring.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.button_mask = MOUSE_BUTTON_MASK_LEFT
	click.pressed = true
	click.position = ui.keep_mystery_button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = click.position
	viewport.push_input(motion, true)
	viewport.push_input(click, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = click.position
	viewport.push_input(release, true)
	_expect(ui.game.is_player_turn() and not ui.keep_mystery_button.is_visible_in_tree())
	_expect(not ui.hand_panels[0].get_node("HandLayout/Cards").get_child(1).get_meta("hidden"))
	_expect(ui.hand_panels[0].get_node("HandLayout").get_child(0).get_child(1).text == "Total: 9")
	_expect(ui.hand_panels[0].has_node("HandLayout/LuckyNineLabel") and ui.reroll_button.text == "Reroll")
	_expect(ui.dealer_cards.get_child(1).get_meta("hidden"), "Normal dealer hole card stays hidden after choice")
	# All five rules fit after the opening as well as during it.
	for window_size in [Vector2i(640, 560), Vector2i(960, 640), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = window_size
		for frame in range(6):
			await get_tree().process_frame
		for control in [ui.hit_button, ui.stand_button, ui.double_button, ui.split_button, ui.reroll_button, ui.second_chance_button, ui.status_label, ui.active_rules_label]:
			_expect(Rect2(Vector2.ZERO, Vector2(window_size)).encloses(control.get_global_rect()), "Five-rule controls must fit at %s" % window_size)
		var card: Control = ui.hand_panels[0].get_node("HandLayout/Cards").get_child(0)
		_expect(ui.table_scroll.get_global_rect().encloses(card.get_global_rect()), "Five-rule cards remain readable at %s" % window_size)
		var heading: Control = ui.hand_panels[0].get_node("HandLayout").get_child(0)
		_expect(ui.table_scroll.get_global_rect().encloses(heading.get_global_rect()), "Five-rule total remains readable at %s" % window_size)
	ui.game = _scenario([10, 5], [10, 7], [14], 10.0, 100.0, true, true, true, 25, true)
	ui._refresh_ui()
	ui.replace_mystery_button.pressed.emit()
	_expect(ui.game.result == BlackjackGame.RoundResult.PLAYER_BLACKJACK and ui.money_label.text == "$115.00")
	_expect(ui.status_label.text.contains("Blackjack") and ui.round_delta_label.text.contains("15.00"))
	_expect(not ui.dealer_cards.get_child(1).get_meta("hidden") and not ui.replace_mystery_button.is_visible_in_tree())
	ui.deal_button.pressed.emit()
	_expect(ui.game.is_awaiting_mystery_card() and not ui.round_delta_label.visible)
	ui.restart_button.pressed.emit()
	_expect(ui.game.round_over and ui.game.rules.selected_rule_ids.has(&"mystery_card"))
	_expect(not ui.keep_mystery_button.is_visible_in_tree() and not ui.round_delta_label.visible)
	ui.game = _scenario([10, 5], [10, 7], [], 10.0, 100.0, false, false, false, 0, true)
	ui._refresh_ui()
	_expect(ui.replace_mystery_button.disabled and not ui.keep_mystery_button.disabled)
	viewport.free()
	print("PASS: Mystery UI conceals card/total/qualification, supports Keep/Replace, preserves dealer secrecy, and fits all supported sizes")


## Find a seed producing the requested real target draw instead of overwriting rule state.
func _seed_for_target(target_total: int) -> int:
	# Seed the real round activation, rather than overwriting the target.
	var probe := RandomNumberGenerator.new()
	for candidate in range(1000):
		probe.seed = candidate
		if probe.randi_range(22, 30) == target_total:
			return candidate
	_expect(false, "No deterministic seed found for target %d" % target_total)
	return 0


## Bet $20, double to $40, draw 21, and verify the complete $140 bankroll flow.
func test_double_flow() -> void:
	var game := _scenario([5, 6], [10, 8], [10], 20.0)
	_expect(game.player.money == 80.0)
	_expect(game.can_double())
	_expect(game.player_double())
	_expect(game.player.hand.get_total() == 21 and game.player.hand.card_count() == 3)
	_expect(game.round_over and game.result == BlackjackGame.RoundResult.PLAYER_WIN)
	_expect(game.player.money == 140.0 and game.player.total_bet() == 0.0)
	_expect(game.player.hands[0].wager == 40.0)
	_expect(not game.player_double() and not game.player_hit())
	print("PASS: $100 -> bet $20 -> double to $40 -> draw 21 -> finish with $140")


## Settle doubled wins/pushes/losses/busts and a wager using the exact remaining bankroll.
func test_double_results() -> void:
	var push_game := _scenario([5, 6], [10, 8], [7])
	_expect(push_game.player_double())
	_expect(push_game.result == BlackjackGame.RoundResult.PUSH and push_game.player.money == 100.0)
	var lose_game := _scenario([5, 6], [10, 9], [7])
	_expect(lose_game.player_double())
	_expect(lose_game.result == BlackjackGame.RoundResult.DEALER_WIN and lose_game.player.money == 80.0)
	var bust_game := _scenario([10, 8], [10, 6], [10])
	_expect(bust_game.player_double())
	_expect(bust_game.result == BlackjackGame.RoundResult.PLAYER_BUST and bust_game.player.money == 80.0)
	_expect(bust_game.dealer.hand.card_count() == 2)
	var all_in := _scenario([5, 6], [10, 8], [10], 10.0, 20.0)
	_expect(all_in.player_double() and all_in.player.money == 40.0)
	print("PASS: Doubled push, loss, bust, and exact-bankroll wager settle correctly")


## Reject unaffordable, wrong-size, ended-hand, and invalid split actions without side effects.
func test_action_restrictions() -> void:
	var waiting := BlackjackGame.new()
	_expect(not waiting.player_double() and not waiting.player_split())
	var poor := _scenario([8, 8], [10, 7], [2, 3], 10.0, 15.0)
	_expect(not poor.can_double() and not poor.can_split())
	_expect(not poor.player_double() and not poor.player_split())
	_expect(poor.player.money == 5.0 and poor.player.total_bet() == 10.0 and poor.deck.cards_remaining() == 2)
	var hit_game := _scenario([4, 4], [10, 7], [2, 3, 5])
	_expect(hit_game.player_hit())
	_expect(not hit_game.can_double() and not hit_game.can_split())
	var different := _scenario([8, 9], [10, 7], [2, 3])
	_expect(not different.player_split())
	var tens := _scenario([10, 13], [10, 7], [2, 3])
	_expect(tens.can_split(), "Equal-value 10 and King should be splittable")
	_expect(tens.player_split() and tens.player.hands.size() == 2)
	_expect(not waiting.start_round(NAN) and not waiting.start_round(INF))
	print("PASS: Unavailable actions preserve money/cards; splitting accepts equal values")


## Play two split eights in order, pushing one and doubling the second into a win.
func test_split_then_double() -> void:
	var game := _scenario([8, 8], [10, 8], [10, 3, 8])
	_expect(game.player_split())
	_expect(game.player.hands.size() == 2 and game.player.money == 80.0 and game.player.total_bet() == 20.0)
	_expect(game.player.hands[0].hand.get_total() == 18 and game.player.hands[1].hand.get_total() == 11)
	_expect(game.player_stand())
	_expect(not game.round_over and game.player.active_hand_index == 1 and game.dealer.hand.card_count() == 2)
	_expect(game.player.money == 80.0, "No hand should be paid before dealer resolution")
	_expect(game.player_double())
	_expect(game.round_over and game.player.money == 120.0)
	_expect(game.player.hands[0].result == BlackjackGame.RoundResult.PUSH)
	_expect(game.player.hands[1].result == BlackjackGame.RoundResult.PLAYER_WIN)
	_expect(game.player.hands[1].wager == 20.0 and game.player.total_bet() == 0.0)
	_expect(game.get_result_text().contains("Hand 1:") and game.get_result_text().contains("Hand 2:"))
	print("PASS: Split eights -> first hand pushes -> double second hand -> finish with $120")


## Bust the first split hand while preserving play and a winning payout on the second.
func test_split_bust_then_win() -> void:
	var game := _scenario([8, 8], [10, 7], [10, 2, 5, 9])
	_expect(game.player_split())
	_expect(game.player_hit())
	_expect(not game.round_over and game.player.active_hand_index == 1)
	_expect(game.player.hands[0].hand.is_bust())
	_expect(game.player_hit() and game.player_stand())
	_expect(game.round_over and game.player.money == 100.0)
	_expect(game.player.hands[0].result == BlackjackGame.RoundResult.PLAYER_BUST)
	_expect(game.player.hands[1].result == BlackjackGame.RoundResult.PLAYER_WIN)
	print("PASS: One split hand busts; the other keeps playing and wins")


## Bust every split hand and verify both losses without running the dealer.
func test_all_split_hands_bust() -> void:
	var game := _scenario([8, 8], [10, 6], [10, 10, 10, 10])
	_expect(game.player_split() and game.player_hit() and game.player_hit())
	_expect(game.round_over and game.player.money == 80.0 and game.player.total_bet() == 0.0)
	_expect(game.dealer.hand.get_total() == 16 and game.dealer.hand.card_count() == 2)
	for played_hand in game.player.hands:
		_expect(played_hand.result == BlackjackGame.RoundResult.PLAYER_BUST)
	print("PASS: All split hands bust -> no dealer draw -> both wagers lost")


## Split Aces, deal one card to each, and verify automatic finishes with ordinary payouts.
func test_split_aces() -> void:
	var game := _scenario([14, 14], [10, 7], [10, 9])
	_expect(game.player_split())
	_expect(game.round_over and game.player.money == 120.0)
	for played_hand in game.player.hands:
		_expect(played_hand.split_aces and played_hand.hand.card_count() == 2 and played_hand.is_standing)
		_expect(not played_hand.is_natural_blackjack())
		_expect(played_hand.result == BlackjackGame.RoundResult.PLAYER_WIN)
	_expect(not game.player_hit() and not game.player_double() and not game.player_split())
	print("PASS: Split Aces get one card each; Ace + 10 pays 1:1")


## Create four ordered player hands and reject a fifth without deducting another stake.
func test_resplit_limit() -> void:
	var game := _scenario([8, 8], [10, 7], [8, 2, 8, 3, 8, 4, 2, 2, 3, 3])
	_expect(game.player_split() and game.player_split() and game.player_split())
	_expect(game.player.hands.size() == 4 and game.player.money == 60.0 and game.player.total_bet() == 40.0)
	var cards_before := game.deck.cards_remaining()
	_expect(not game.player_split() and game.deck.cards_remaining() == cards_before)
	# Finish each hand in table order; no dealer action until all finish.
	for i in range(4):
		_expect(game.player.active_hand_index == i)
		_expect(game.player_stand())
	_expect(game.round_over and game.player.total_bet() == 0.0)
	print("PASS: Re-split to four hands; a fifth hand cannot be created")


## Reach two split 21s and verify neither receives the natural 3:2 payout.
func test_split_blackjack_payout() -> void:
	var game := _scenario([10, 13], [10, 7], [14, 14])
	_expect(game.player_split())
	_expect(game.round_over and game.player.money == 120.0)
	_expect(game.player.hands[0].hand.has_21() and game.player.hands[1].hand.has_21())
	_expect(game.player.hands[0].result == BlackjackGame.RoundResult.PLAYER_WIN)
	_expect(game.player.hands[1].result == BlackjackGame.RoundResult.PLAYER_WIN)
	print("PASS: Two split 21s automatically finish and both pay normal winnings")


## Pay both hands on dealer bust, then start a fresh round with one hand.
func test_split_dealer_bust_and_reset() -> void:
	var game := _scenario([8, 8], [10, 6], [10, 9, 10])
	_expect(game.player_split() and game.player_stand() and game.player_stand())
	_expect(game.dealer.hand.is_bust() and game.player.money == 120.0)
	for played_hand in game.player.hands:
		_expect(played_hand.result == BlackjackGame.RoundResult.DEALER_BUST)
	game.deck = Deck.new()
	_expect(game.start_round(10.0))
	_expect(game.player.hands.size() == 1 and game.player.active_hand_index == 0)
	_expect(not game.player.hands[0].is_split and not game.player.hands[0].doubled)
	_expect(game.deck.cards_remaining() == 48)
	print("PASS: Dealer bust pays each split hand; next round resets to one hand and a fresh deck")


## Resolve player-only, dealer-only, and simultaneous naturals before extra wagers; stand on soft 17.
func test_opening_blackjacks() -> void:
	var player_natural := _scenario([14, 10], [10, 7], [])
	_expect(player_natural.round_over and player_natural.player.money == 115.0)
	_expect(player_natural.result == BlackjackGame.RoundResult.PLAYER_BLACKJACK)
	var dealer_natural := _scenario([8, 8], [14, 10], [2, 3])
	_expect(dealer_natural.round_over and dealer_natural.player.money == 90.0)
	_expect(not dealer_natural.player_split() and not dealer_natural.player_double())
	var both_natural := _scenario([14, 10], [14, 13], [])
	_expect(both_natural.result == BlackjackGame.RoundResult.PUSH and both_natural.player.money == 100.0)
	var soft_17 := _scenario([10, 8], [14, 6], [])
	_expect(soft_17.player_stand() and soft_17.player.money == 110.0)
	print("PASS: Opening Blackjack pays 3:2; dealer Blackjack blocks extra bets; soft 17 stands")


## Reject actions needing unavailable cards and refund every stake when dealer drawing fails.
func test_empty_deck_protection() -> void:
	var game := _scenario([8, 8], [10, 7], [])
	_expect(not game.player_double() and not game.player_split() and not game.player_hit())
	_expect(game.player.money == 90.0 and game.player.total_bet() == 10.0)
	var short_split := _scenario([8, 8], [10, 7], [2])
	_expect(not short_split.player_split() and short_split.deck.cards_remaining() == 1)
	var short_dealer := _scenario([8, 8], [10, 6], [2, 3])
	_expect(short_dealer.player_split() and short_dealer.player_stand() and short_dealer.player_stand())
	_expect(short_dealer.round_over and short_dealer.player.money == 100.0 and short_dealer.player.total_bet() == 0.0)
	_expect(short_dealer.status_message.contains("returned"))
	print("PASS: Card shortages do not consume action wagers; interrupted dealer refunds all hands")


## Drive real button signals, inspect split panels and bankroll, restart, and verify responsive bounds.
func test_playable_ui() -> void:
	var ui_viewport := SubViewport.new()
	ui_viewport.size = Vector2i(960, 640)
	add_child(ui_viewport)
	var ui := preload("res://scenes/game.tscn").instantiate()
	ui_viewport.add_child(ui)
	if not ui.has_method("_refresh_ui"):
		_expect(false, "UI script failed to load")
		ui_viewport.free()
		return
	_expect(ui.double_button.disabled and ui.split_button.disabled)
	ui.game = _scenario([8, 8], [10, 8], [10, 3, 8])
	ui._refresh_ui()
	_expect(not ui.double_button.disabled and not ui.split_button.disabled)
	_expect(ui.dealer_cards.get_child(1).get_meta("hidden"))
	ui.split_button.pressed.emit()
	_expect(ui.game.player.hands.size() == 2)
	_expect(ui.hand_panels.size() == 2 and ui.hand_panels[0].get_meta("active"))
	_expect(ui.current_bet_label.text == "$20.00")
	ui.stand_button.pressed.emit()
	_expect(ui.player_total_label.text == "Playing hand 2 of 2")
	ui.double_button.pressed.emit()
	_expect(ui.game.round_over and ui.money_label.text == "$120.00")
	_expect(ui.double_button.disabled and ui.split_button.disabled)
	_expect(not ui.dealer_cards.get_child(1).get_meta("hidden"))
	ui.restart_button.pressed.emit()
	_expect(ui.game.player.hands.size() == 1 and ui.game.player.money == 100.0)
	# Four-hand layout must keep the action bar accessible at 960 x 640.
	ui.game = _scenario([8, 8], [10, 7], [8, 2, 8, 3, 8, 4])
	_expect(ui.game.player_split() and ui.game.player_split() and ui.game.player_split())
	ui._refresh_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = ui.get_node("WindowMargin")
	var scroll: ScrollContainer = ui.table_scroll
	_expect(panel.get_global_rect().end.x <= ui_viewport.size.x, "Panel must fit the viewport width")
	_expect(ui.double_button.get_global_rect().end.y <= ui_viewport.size.y, "Action buttons must fit the viewport height")
	_expect(ui.double_button.get_global_rect().position.y >= scroll.get_global_rect().end.y, "Actions must stay outside the scrolling hands")
	_expect(ui.hand_panels.size() == 4)
	for window_size in [Vector2i(640, 560), Vector2i(960, 640), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		ui_viewport.size = window_size
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		var content: Control = ui.get_node("WindowMargin")
		_expect(ui.size == Vector2(window_size), "UI should fill %s" % window_size)
		_expect(content.get_global_rect().position.x >= 0 and content.get_global_rect().end.x <= window_size.x, "Content must fit at %s" % window_size)
		for button in [ui.hit_button, ui.stand_button, ui.double_button, ui.split_button, ui.deal_button, ui.restart_button]:
			if not button.is_visible_in_tree():
				continue
			var rect: Rect2 = button.get_global_rect()
			_expect(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= window_size.x and rect.end.y <= window_size.y, "Buttons must remain visible at %s" % window_size)
		var active_panel: PanelContainer = ui.hand_panels[ui.game.player.active_hand_index]
		var first_card: Control = active_panel.get_node("HandLayout/Cards").get_child(0)
		var visible_area: Rect2 = ui.table_scroll.get_global_rect()
		_expect(first_card.get_global_rect().position.y >= visible_area.position.y and first_card.get_global_rect().end.y <= visible_area.end.y, "Active cards should scroll into view at %s" % window_size)
		_expect(ui.table_scroll.size.y > 60, "Cards must have usable scroll space at %s" % window_size)
	ui_viewport.remove_child(ui)
	ui.free()
	remove_child(ui_viewport)
	ui_viewport.free()
	print("PASS: Real UI buttons, split hand labels, bankroll, hidden dealer card, and restart")


# Test-only rules verify registry selection and hooks without adding gameplay.
class TrackingRule extends SpecialRule:
	var started: int = 0
	var dealt: int = 0
	var changed: int = 0
	var settled: int = 0
	var finished: int = 0

	## Create a test-only observer rule with a distinct ID for lifecycle-order checks.
	func _init(id: StringName = &"test_rule") -> void:
		super(id, "Test Rule", "Test-only observer")

	## Count accepted-round notifications without retaining the temporary context.
	func on_round_started(_context: Dictionary) -> void:
		started += 1

	## Count finalized playable openings to detect early or repeated qualification hooks.
	func on_opening_dealt(_context: Dictionary) -> void:
		dealt += 1

	## Count action notifications for card changes.
	func on_hand_changed(_context: Dictionary) -> void:
		changed += 1

	## Count pre-payout notifications when outcomes are ready.
	func before_settlement(_context: Dictionary) -> void:
		settled += 1

	## Count completed/refunded rounds after settlement.
	func on_round_finished(_context: Dictionary) -> void:
		finished += 1


## Validate unique registration and Off/Always/Random selections, including count clamping.
func test_rule_manager() -> void:
	var manager := RuleManager.new()
	_expect(manager.register_rule(TrackingRule.new(&"one")))
	_expect(manager.register_rule(TrackingRule.new(&"two")))
	_expect(not manager.register_rule(TrackingRule.new(&"one")))
	_expect(manager.configure(RuleManager.RuleMode.OFF, [&"reroll", &"one"]))
	manager.prepare_round()
	_expect(manager.active_rules.is_empty())
	_expect(manager.configure(RuleManager.RuleMode.ALL_SELECTED, [&"reroll", &"one", &"one"]))
	manager.prepare_round()
	_expect(manager.active_rules.size() == 2 and manager.is_rule_active(&"one") and not manager.is_rule_active(&"two"))
	_expect(not manager.configure(99, [&"reroll"]))
	_expect(not manager.configure(RuleManager.RuleMode.OFF, [&"unknown"]))
	_expect(not manager.configure(RuleManager.RuleMode.RANDOM_SELECTED, [&"reroll"], 0))
	_expect(manager.rule_mode == RuleManager.RuleMode.ALL_SELECTED)
	_expect(manager.configure(RuleManager.RuleMode.RANDOM_SELECTED, [&"one", &"two"], 1))
	manager._rng.seed = 741
	var chosen: Dictionary = {}
	for round_number in range(20):
		manager.prepare_round()
		_expect(manager.active_rules.size() == 1 and not manager.is_rule_active(&"reroll"))
		chosen[manager.active_rules[0].rule_id] = true
	_expect(chosen.size() == 2, "Seeded random rounds should choose from both selected rules")
	_expect(manager.configure(RuleManager.RuleMode.RANDOM_SELECTED, [&"reroll"], 10))
	manager.prepare_round()
	_expect(manager.active_rules.size() == 1)
	_expect(manager.configure(RuleManager.RuleMode.ALL_SELECTED, []))
	manager.prepare_round()
	_expect(manager.active_rules.is_empty())
	print("PASS: Rule settings support Off, Always, and Random; only selected rules activate")


## Observe start, opening, card change, settlement, and completion along one real round.
func test_rule_hooks() -> void:
	var game := _scenario([10, 5], [10, 8], [2])
	game.player_stand()
	var observer := TrackingRule.new()
	_expect(game.rules.register_rule(observer))
	_expect(game.configure_rules(RuleManager.RuleMode.ALL_SELECTED, [&"test_rule"]))
	_expect(game.start_round(10.0))
	_expect(observer.started == 1 and observer.dealt == 1)
	_expect(game.player_hit() and game.player_stand())
	_expect(observer.changed == 1 and observer.settled == 1 and observer.finished == 1)
	print("PASS: Registered rules receive round, deal, card-change, settlement, and finish hooks")


## Hit to 17, replace a 10 with a 3, and verify one free use and discarded-card handling.
func test_reroll_flow() -> void:
	var game := _scenario([10, 5], [10, 8], [2, 3, 6], 10.0, 100.0, true)
	_expect(game.player_hit() and game.player.hand.get_total() == 17)
	var removed := game.player.hand.cards[0]
	_expect(game.can_reroll(0) and game.player_reroll(0))
	_expect(game.player.hand.card_count() == 3 and game.player.hand.get_total() == 10)
	_expect(not game.player.hand.cards.has(removed) and not game.deck.cards.has(removed))
	_expect(game.deck.cards_remaining() == 1 and game.player.money == 90.0 and game.player.bet == 10.0)
	_expect(not game.can_reroll() and not game.player_reroll(1) and game.deck.cards_remaining() == 1)
	_expect(game.last_rule_message.contains("Reroll:"))
	_expect(game.player_stand() and game.player.money == 90.0)
	print("PASS: Hit to 17 -> replace the 10 with a 3 -> total 10; no extra bet and no second use")


## Reroll into ordinary 21, bust, and an Ace-adjusted surviving hand, then check payouts.
func test_reroll_results() -> void:
	var win_game := _scenario([10, 5], [10, 8], [14], 10.0, 100.0, true)
	_expect(win_game.player_reroll(1))
	_expect(win_game.round_over and win_game.player.hand.get_total() == 21)
	_expect(not win_game.player.hands[0].is_natural_blackjack())
	_expect(win_game.result == BlackjackGame.RoundResult.PLAYER_WIN and win_game.player.money == 110.0)
	var bust_game := _scenario([10, 5], [10, 6], [2, 10], 10.0, 100.0, true)
	_expect(bust_game.player_hit() and bust_game.player_reroll(1))
	_expect(bust_game.round_over and bust_game.result == BlackjackGame.RoundResult.PLAYER_BUST)
	_expect(bust_game.player.money == 90.0 and bust_game.dealer.hand.card_count() == 2)
	var soft_game := _scenario([14, 6], [10, 7], [9], 10.0, 100.0, true)
	_expect(soft_game.player_reroll(1) and soft_game.player.hand.get_total() == 20)
	_expect(soft_game.player_stand() and soft_game.player.money == 110.0)
	print("PASS: Rerolled 21 pays 1:1; replacement bust loses; Aces still adjust normally")


## Spend or save Reroll across split hands, then regain the single use next round.
func test_reroll_across_split_hands() -> void:
	var game := _scenario([8, 8], [10, 7], [2, 3, 4, 6], 10.0, 100.0, true)
	_expect(game.player_split() and game.player_reroll(1))
	_expect(game.player.hand.get_total() == 12 and game.player.money == 80.0)
	_expect(game.player_stand() and game.player.active_hand_index == 1)
	_expect(not game.can_reroll() and not game.player_reroll(0))
	_expect(game.player_stand() and game.player.money == 80.0)
	_expect(game.start_round(10.0) and game.can_reroll())
	_expect(not game.player.hands[0].has_been_rerolled and game.player.hands.size() == 1)
	var use_on_second := _scenario([8, 8], [10, 7], [2, 3, 4], 10.0, 100.0, true)
	_expect(use_on_second.player_split() and use_on_second.player_stand())
	_expect(use_on_second.player.active_hand_index == 1 and use_on_second.player_reroll(0))
	_expect(use_on_second.player.hand.get_total() == 7)
	var busted_split := _scenario([8, 8], [10, 7], [10, 3, 2, 10], 10.0, 100.0, true)
	_expect(busted_split.player_split() and busted_split.player_hit())
	_expect(busted_split.player_reroll(0) and not busted_split.round_over and busted_split.player.active_hand_index == 1)
	_expect(busted_split.player.hands[0].hand.is_bust() and not busted_split.can_reroll())
	_expect(busted_split.player_stand() and busted_split.player.money == 80.0)
	print("PASS: Split hands share one Reroll; an unused Reroll can be saved for hand two; next round resets it")


## Recalculate Double/Split eligibility after replacement and forbid rerolls on ended/split-Ace hands.
func test_reroll_then_double_and_split() -> void:
	var double_game := _scenario([5, 6], [10, 8], [4, 10], 10.0, 100.0, true)
	_expect(double_game.player_reroll(0) and double_game.can_double())
	_expect(double_game.player_double() and double_game.player.money == 120.0)
	_expect(not double_game.player_reroll(0))
	var split_game := _scenario([8, 5], [10, 7], [8, 2, 3], 10.0, 100.0, true)
	_expect(split_game.player_reroll(1) and split_game.can_split())
	_expect(split_game.player_split() and not split_game.can_reroll())
	_expect(split_game.player_stand() and split_game.player_stand() and split_game.player.money == 80.0)
	var ace_game := _scenario([14, 14], [10, 7], [2, 3, 4], 10.0, 100.0, true)
	_expect(ace_game.player_split() and ace_game.round_over and not ace_game.player_reroll(0))
	print("PASS: Reroll can precede Double or Split; ended hands and split Aces cannot reroll")


## Reject inactive/ended rounds, invalid indices, empty draws, and mid-round settings without spending usage.
func test_reroll_rejections() -> void:
	var off := _scenario([10, 5], [10, 8], [2])
	_expect(not off.can_reroll() and not off.player_reroll(0))
	var game := _scenario([10, 5], [10, 8], [2], 10.0, 100.0, true)
	_expect(not game.player_reroll(-1) and not game.player_reroll(2))
	_expect(game.can_reroll() and game.deck.cards_remaining() == 1)
	_expect(not game.configure_rules(RuleManager.RuleMode.OFF, []))
	_expect(not game.start_round(10.0) and game.can_reroll())
	_expect(game.rules.is_rule_active(&"reroll"))
	game.deck.cards.clear()
	_expect(not game.player_reroll(0) and game.player.hand.get_total() == 15)
	var rule := game.rules.get_rule(&"reroll") as RerollRule
	_expect(not rule.has_used(game.player) and game.player.money == 90.0)
	game.deck.cards.append(Card.new(Card.Suit.HEARTS, Card.Rank.TWO))
	_expect(game.player_reroll(1) and game.player_stand())
	_expect(not game.player_reroll(0))
	_expect(game.configure_rules(RuleManager.RuleMode.OFF, []))
	_expect(game.start_round(10.0) and not game.can_reroll())
	var natural := _scenario([14, 10], [10, 8], [2], 10.0, 100.0, true)
	_expect(natural.round_over and natural.player.money == 115.0 and not natural.player_reroll(0))
	print("PASS: Classic/ended rounds, invalid indices, empty deck, and mid-round settings reject changes safely")


## Select/cancel through buttons, Escape, and real card clicks; verify Used state and resizing.
func test_reroll_ui() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 640)
	add_child(viewport)
	var ui := preload("res://scenes/game.tscn").instantiate()
	viewport.add_child(ui)
	if not ui.has_method("_refresh_ui"):
		_expect(false, "Reroll UI script failed to load")
		viewport.free()
		return
	ui._populate_rule_settings()
	ui.rule_mode_option.select(RuleManager.RuleMode.ALL_SELECTED)
	ui.rule_checkboxes[&"reroll"].button_pressed = true
	ui.rule_dialog.confirmed.emit()
	_expect(ui.game.rules.rule_mode == RuleManager.RuleMode.ALL_SELECTED)
	_expect(ui.active_rules_label.text.contains("Reroll"))
	ui.game = _scenario([8, 8], [10, 8], [10, 3, 8, 4], 10.0, 100.0, true)
	ui.game.player_split()
	ui._refresh_ui()
	_expect(ui.reroll_button.visible and not ui.reroll_button.disabled and ui.rules_button.disabled)
	ui.reroll_button.pressed.emit()
	_expect(ui.reroll_button.text == "Cancel" and ui.hit_button.disabled and ui.stand_button.disabled)
	_expect(ui.hand_panels[0].get_node("HandLayout/Cards").get_child(0).get_meta("reroll_selectable"))
	_expect(not ui.hand_panels[1].get_node("HandLayout/Cards").get_child(0).has_meta("reroll_selectable"))
	ui._choose_reroll_card(1, 0)
	_expect(ui._selecting_reroll and ui.game.can_reroll())
	ui.reroll_button.pressed.emit()
	_expect(not ui._selecting_reroll and ui.game.can_reroll() and ui.game.deck.cards_remaining() == 2)
	ui.reroll_button.pressed.emit()
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	ui._unhandled_key_input(escape)
	_expect(not ui._selecting_reroll and ui.game.can_reroll())
	ui.reroll_button.pressed.emit()
	for frame in range(5):
		await get_tree().process_frame
	var card: Control = ui.hand_panels[0].get_node("HandLayout/Cards").get_child(1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = card.get_global_rect().get_center()
	viewport.push_input(click, true)
	click.pressed = false
	viewport.push_input(click, true)
	_expect(not ui._selecting_reroll and ui.game.player.hand.get_total() == 16)
	_expect(ui.reroll_button.text == "Used" and ui.reroll_button.disabled)
	_expect(ui.active_rules_label.text.contains("used") and ui.status_label.text.contains("Reroll:"))
	ui.stand_button.pressed.emit()
	_expect(ui.game.player.active_hand_index == 1 and ui.reroll_button.disabled)
	# Before spending Reroll, the fifth action must fit every supported size.
	ui.game = _scenario([8, 8], [10, 7], [8, 2, 8, 3, 8, 4, 2], 10.0, 100.0, true)
	ui.game.player_split()
	ui.game.player_split()
	ui.game.player_split()
	ui._refresh_ui()
	for window_size in [Vector2i(640, 560), Vector2i(960, 640), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = window_size
		for frame in range(5):
			await get_tree().process_frame
		for button in [ui.hit_button, ui.stand_button, ui.double_button, ui.split_button, ui.reroll_button, ui.rules_button]:
			var rect: Rect2 = button.get_global_rect()
			_expect(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= window_size.x and rect.end.y <= window_size.y, "Reroll controls must fit at %s" % window_size)
		var active_card: Control = ui.hand_panels[0].get_node("HandLayout/Cards").get_child(0)
		var area: Rect2 = ui.table_scroll.get_global_rect()
		_expect(active_card.get_global_rect().position.y >= area.position.y and active_card.get_global_rect().end.y <= area.end.y, "Active cards must remain readable at %s" % window_size)
	ui.restart_button.pressed.emit()
	_expect(ui.game.player.money == 100.0 and ui.game.rules.rule_mode == RuleManager.RuleMode.ALL_SELECTED)
	_expect(not ui._selecting_reroll and ui.rules_button.disabled == false)
	var reroll_ids: Array[StringName] = [&"reroll"]
	ui.game.configure_rules(RuleManager.RuleMode.RANDOM_SELECTED, reroll_ids, 1)
	ui._populate_rule_settings()
	_expect(ui.random_count_spin.editable)
	viewport.remove_child(ui)
	ui.free()
	remove_child(viewport)
	viewport.free()
	print("PASS: Rule settings, cancel/Escape, real card clicks, Used status, restart preferences, and responsive Reroll UI")


## Recover one bust, accept another, share usage, and restore availability on the next deal.
func test_second_chance_flow() -> void:
	var game := _scenario([10, 5], [10, 7], [10, 8], 10.0, 100.0, false, true)
	_expect(not game.can_second_chance() and not game.player_second_chance())
	_expect(game.player_hit() and game.is_awaiting_second_chance() and not game.round_over)
	_expect(game.player.hand.get_total() == 25 and game.player.money == 90.0)
	_expect(not game.player_hit() and not game.player_double() and not game.player_split() and not game.player_reroll(0))
	_expect(not game.configure_rules(RuleManager.RuleMode.OFF, []))
	_expect(game.player_second_chance() and game.player.hand.get_total() == 15 and game.is_player_turn())
	_expect(game.player.hand.card_count() == 2 and game.deck.cards_remaining() == 1 and game.player.money == 90.0)
	_expect(not game.player_second_chance())
	_expect(game.player_hit() and game.round_over and game.player.money == 90.0)
	_expect(game.start_round(10.0) and not (game.rules.get_rule(&"second_chance") as SecondChanceRule).has_used(game.player))
	var declined := _scenario([10, 5], [10, 7], [10], 10.0, 100.0, false, true)
	_expect(declined.player_hit() and declined.player_stand() and declined.round_over)
	_expect(declined.player.money == 90.0 and not (declined.rules.get_rule(&"second_chance") as SecondChanceRule).has_used(declined.player))
	var empty := _scenario([10, 5], [10, 7], [10], 10.0, 100.0, false, true)
	_expect(empty.player_hit() and empty.deck.is_empty() and empty.player_second_chance())
	_expect(empty.player_stand() and empty.round_over and not empty.player_second_chance())
	var natural := _scenario([14, 10], [10, 7], [], 10.0, 100.0, false, true)
	_expect(natural.round_over and natural.player.money == 115.0 and not natural.can_second_chance())
	print("PASS: Hit to 25 -> pause -> discard the 10 -> continue at 15; one use, decline, empty deck, and next-round reset")


## Save or spend recovery across splits and end a rescued Double with its doubled wager intact.
func test_second_chance_split_and_double() -> void:
	var game := _scenario([8, 8], [10, 8], [10, 5, 10, 10], 10.0, 100.0, false, true)
	_expect(game.player_split() and game.player_hit() and game.player_second_chance())
	_expect(game.player.hand.get_total() == 18 and game.player_stand())
	_expect(game.player.active_hand_index == 1 and game.player_hit() and game.round_over)
	_expect(game.player.money == 90.0 and game.player.hands[1].hand.is_bust())
	var saved := _scenario([8, 8], [10, 8], [10, 5, 10, 10], 10.0, 100.0, false, true)
	_expect(saved.player_split() and saved.player_hit() and saved.player_stand())
	_expect(saved.player.active_hand_index == 1 and saved.player_hit() and saved.can_second_chance())
	_expect(saved.player_second_chance() and saved.player_stand() and saved.player.money == 80.0)
	var doubled := _scenario([10, 5], [10, 7], [10], 10.0, 100.0, false, true)
	_expect(doubled.player_double() and doubled.is_awaiting_second_chance() and doubled.player.bet == 20.0)
	_expect(doubled.player_second_chance() and doubled.round_over and doubled.player.money == 80.0)
	_expect(doubled.player.hand.get_total() == 15 and doubled.player.hands[0].doubled and doubled.player.hands[0].wager == 20.0)
	var aces := _scenario([14, 14], [10, 7], [10, 8], 10.0, 100.0, false, true)
	_expect(aces.player_split() and aces.round_over and not aces.can_second_chance())
	print("PASS: Split hands share Second Chance or save it for hand two; a rescued Double retains its wager and finishes")


## Remove the exact replacement that caused a bust while keeping independent ability usage.
func test_second_chance_with_reroll() -> void:
	var game := _scenario([10, 5], [10, 7], [4, 10, 5], 10.0, 100.0, true, true)
	_expect(game.player_hit() and game.player_reroll(1) and game.is_awaiting_second_chance())
	_expect(game.player.hand.get_total() == 24 and not game.can_reroll())
	_expect(game.player_second_chance() and game.player.hand.get_total() == 14)
	_expect(game.player.hand.cards[1].rank == 4 and game.player.hand.card_count() == 2)
	_expect(not game.can_reroll() and not game.can_second_chance())
	_expect(game.player_hit() and game.player_stand() and game.player.money == 110.0)
	var then_reroll := _scenario([10, 5], [10, 7], [10, 4], 10.0, 100.0, true, true)
	_expect(then_reroll.player_hit() and then_reroll.player_second_chance() and then_reroll.can_reroll())
	_expect(then_reroll.player_reroll(1) and then_reroll.player.hand.get_total() == 14)
	var manager := RuleManager.new()
	manager.configure(RuleManager.RuleMode.RANDOM_SELECTED, [&"reroll", &"second_chance"], 1)
	manager._rng.seed = 42
	var seen: Dictionary = {}
	for round_index in range(20):
		manager.prepare_round()
		_expect(manager.active_rules.size() == 1)
		seen[manager.active_rules[0].rule_id] = true
	_expect(seen.has(&"reroll") and seen.has(&"second_chance"))
	print("PASS: Reroll bust recovery removes the correct replacement; abilities have separate uses and Random chooses either")


## Check net profit/loss for ordinary, natural, doubled, split, pushed, and refunded outcomes.
## Clear the completed amount on an accepted new deal while preserving it after a rejected wager.
func test_round_net_results() -> void:
	var win := _scenario([10, 9], [10, 7], [])
	_expect(not win.has_round_result and win.player_stand())
	_expect(win.last_round_delta == 10.0 and win.player.hands[0].net_result == 10.0)
	var loss := _scenario([10, 5], [10, 7], [10])
	loss.player_hit()
	_expect(loss.last_round_delta == -10.0 and loss.player.hands[0].net_result == -10.0)
	var push := _scenario([10, 7], [10, 7], [])
	push.player_stand()
	_expect(push.last_round_delta == 0.0 and push.player.hands[0].net_result == 0.0)
	var blackjack := _scenario([14, 10], [10, 7], [])
	_expect(blackjack.last_round_delta == 15.0 and blackjack.player.hands[0].net_result == 15.0)
	var double_win := _scenario([5, 6], [10, 8], [10], 20.0)
	double_win.player_double()
	_expect(double_win.last_round_delta == 40.0 and double_win.player.hands[0].net_result == 40.0)
	var split := _scenario([8, 8], [10, 8], [10, 3, 10])
	split.player_split()
	split.player_stand()
	split.player_double()
	_expect(split.last_round_delta == 20.0 and split.player.hands[0].net_result == 0.0 and split.player.hands[1].net_result == 20.0)
	var canceled := _scenario([10, 6], [10, 2], [])
	canceled.player_stand()
	_expect(canceled.last_round_delta == 0.0 and canceled.player.money == 100.0)
	_expect(not win.start_round(999.0) and win.has_round_result and win.last_round_delta == 10.0, "A rejected wager must preserve the completed result")
	_expect(win.start_round(10.0) and not win.has_round_result and win.last_round_delta == 0.0, "A new accepted round must clear the completed result")
	print("PASS: Net gains/losses account for Blackjack, Double, splits, push, refunds, and clear only on an accepted new round")


## Exercise recovery/accept-bust controls, result colors, six-action layouts, and checkbox/title bounds.
func test_second_chance_ui() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 640)
	add_child(viewport)
	var ui := preload("res://scenes/game.tscn").instantiate()
	viewport.add_child(ui)
	if not ui.has_method("_refresh_ui"):
		_expect(false, "Second Chance UI script failed to load")
		viewport.free()
		return
	ui.game = _scenario([10, 5], [10, 7], [10, 8], 10.0, 100.0, true, true)
	ui._refresh_ui()
	_expect(ui.second_chance_button.visible and ui.second_chance_button.disabled)
	ui.hit_button.pressed.emit()
	_expect(ui.second_chance_button.disabled == false and ui.stand_button.text == "Accept Bust")
	_expect(ui.hit_button.disabled and ui.double_button.disabled and ui.split_button.disabled and ui.reroll_button.disabled)
	_expect(ui.status_label.text.contains("Bust!") and ui.rules_button.disabled)
	ui.second_chance_button.pressed.emit()
	_expect(ui.game.is_player_turn() and ui.stand_button.text == "Stand")
	_expect(ui.second_chance_button.text == "Chance Used" and ui.second_chance_button.disabled)
	ui.hit_button.pressed.emit()
	_expect(ui.round_delta_label.text == "Round: −$10.00" and ui.round_delta_label.get_theme_color("font_color") == ui.LOSS)
	_expect(ui.hand_panels[0].get_node("HandLayout").get_child(1).get_child(0).text.contains("−$10.00"))
	ui.game = _scenario([10, 9], [10, 7], [])
	ui.stand_button.pressed.emit()
	_expect(ui.round_delta_label.text == "Round: +$10.00" and ui.round_delta_label.get_theme_color("font_color") == ui.GAIN)
	ui.game = _scenario([10, 7], [10, 7], [])
	ui.stand_button.pressed.emit()
	_expect(ui.round_delta_label.text == "Round: $0.00" and ui.round_delta_label.get_theme_color("font_color") == ui.MUTED)
	# Two active rules make six controls. Keep them and pending busts readable.
	ui.game = _scenario([10, 5], [10, 7], [10], 10.0, 100.0, true, true)
	ui.game.player_hit()
	ui._refresh_ui()
	for window_size in [Vector2i(640, 560), Vector2i(960, 640), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = window_size
		for frame in range(5):
			await get_tree().process_frame
		for button in [ui.hit_button, ui.stand_button, ui.double_button, ui.split_button, ui.reroll_button, ui.second_chance_button, ui.rules_button, ui.round_delta_label]:
			var rect: Rect2 = button.get_global_rect()
			_expect(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= window_size.x and rect.end.y <= window_size.y, "Second Chance controls must fit at %s" % window_size)
		var active_card: Control = ui.hand_panels[0].get_node("HandLayout/Cards").get_child(0)
		_expect(ui.table_scroll.get_global_rect().encloses(active_card.get_global_rect()), "Bust-causing hand cards must fit at %s" % window_size)
	ui.stand_button.pressed.emit()
	_expect(ui.game.round_over and not ui.second_chance_button.visible)
	ui.restart_button.pressed.emit()
	_expect(ui.round_delta_label.text.is_empty() and not ui.round_delta_label.visible and ui.game.rules.selected_rule_ids.has(&"second_chance"))
	_expect(ui.rule_checkboxes.size() == 5)
	var original_root_size := get_tree().root.size
	get_tree().root.size = Vector2i(640, 560)
	ui._on_rules_pressed()
	for frame in range(5):
		await get_tree().process_frame
	for checkbox in ui.rule_checkboxes.values():
		var rules_scroll: ScrollContainer = checkbox.get_parent().get_parent().get_parent()
		rules_scroll.ensure_control_visible(checkbox.get_parent())
		await get_tree().process_frame
		await get_tree().process_frame
		var title: Control = checkbox.get_parent().get_child(1).get_child(0)
		for target in [checkbox, title]:
			await get_tree().process_frame
			var previous: bool = checkbox.button_pressed
			var motion := InputEventMouseMotion.new()
			motion.position = target.get_global_rect().get_center() + Vector2(ui.rule_dialog.position)
			get_tree().root.push_input(motion, true)
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.position = motion.position
			click.pressed = true
			click.button_mask = MOUSE_BUTTON_MASK_LEFT
			get_tree().root.push_input(click, true)
			await get_tree().process_frame
			var release := InputEventMouseButton.new()
			release.button_index = MOUSE_BUTTON_LEFT
			release.position = click.position
			get_tree().root.push_input(release, true)
			_expect(checkbox.button_pressed != previous, "Real click must toggle %s for %s" % [target.get_class(), checkbox.tooltip_text])
		for pressed in [false, true, false, true]:
			checkbox.button_pressed = pressed
			checkbox.grab_focus()
			for frame in range(2):
				await get_tree().process_frame
			_expect(not checkbox.get_global_rect().intersects(title.get_global_rect()), "Rule name must stay outside checkbox bounds, checked or unchecked")
	viewport.free()
	get_tree().root.size = original_root_size
	print("PASS: Second Chance buttons, accept-bust flow, colored net results, six-control layouts, and separated checkbox labels")


## Open with 4+5 and win the 50% bonus, then verify Double keeps the original bonus base.
func test_lucky_nine_flow() -> void:
	var game := _scenario([4, 5], [10, 7], [10], 10.0, 100.0, false, false, true)
	_expect(game.rules.is_rule_active(&"lucky_nine") and game.player.hands[0].lucky_nine_qualified)
	_expect(game.player.money == 90.0 and game.player.hands[0].lucky_nine_bonus == 0.0)
	_expect(game.player_hit() and game.player.hand.get_total() == 19 and game.player_stand())
	_expect(game.player.money == 115.0 and game.last_round_delta == 15.0)
	_expect(game.player.hands[0].net_result == 15.0 and game.player.hands[0].bonus_payout == 5.0 and game.player.hands[0].lucky_nine_bonus == 5.0)
	# Recomputing bonuses must not increase them or mutate the bankroll.
	game._notify_rules(&"before_settlement")
	_expect(game.player.money == 115.0 and game.player.hands[0].bonus_payout == 5.0)
	_expect(game.start_round(10.0) and not game.has_round_result and game.player.hands[0].bonus_payout == 0.0)
	_expect(game.player.hands[0].lucky_nine_base_wager == 10.0)
	var doubled := _scenario([4, 5], [10, 7], [10], 10.0, 100.0, false, false, true)
	_expect(doubled.player_double() and doubled.player.money == 125.0)
	_expect(doubled.player.hands[0].wager == 20.0 and doubled.player.hands[0].lucky_nine_bonus == 5.0 and doubled.last_round_delta == 25.0)
	var fractional := _scenario([4, 5], [10, 7], [10], 1.25, 100.0, false, false, true)
	fractional.player_hit()
	fractional.player_stand()
	_expect(is_equal_approx(fractional.player.hands[0].lucky_nine_bonus, 0.63) and is_equal_approx(fractional.last_round_delta, 1.88))
	print("PASS: Opening 4 + 5 -> hit to 19 -> win $10 plus $5 Lucky 9 bonus; Double keeps the opening-wager bonus")


## Pay only eligible wins/dealer busts; exclude pushes, losses, refunds, soft 19, and inactive rules.
func test_lucky_nine_outcomes() -> void:
	var dealer_bust := _scenario([4, 5], [10, 6], [10, 10], 10.0, 100.0, false, false, true)
	dealer_bust.player_hit()
	dealer_bust.player_stand()
	_expect(dealer_bust.result == BlackjackGame.RoundResult.DEALER_BUST and dealer_bust.player.money == 115.0)
	var pushed := _scenario([4, 5], [10, 7], [8], 10.0, 100.0, false, false, true)
	pushed.player_hit()
	pushed.player_stand()
	_expect(pushed.player.money == 100.0 and pushed.player.hands[0].lucky_nine_bonus == 0.0)
	var lost := _scenario([4, 5], [10, 7], [], 10.0, 100.0, false, false, true)
	lost.player_stand()
	_expect(lost.player.money == 90.0 and lost.player.hands[0].lucky_nine_bonus == 0.0)
	var busted := _scenario([4, 5], [10, 7], [10, 10], 10.0, 100.0, false, false, true)
	busted.player_hit()
	busted.player_hit()
	_expect(busted.round_over and busted.player.money == 90.0 and busted.player.hands[0].bonus_payout == 0.0)
	var refunded := _scenario([4, 5], [10, 2], [10], 10.0, 100.0, false, false, true)
	refunded.player_hit()
	refunded.player_stand()
	_expect(refunded.result == BlackjackGame.RoundResult.NONE and refunded.player.money == 100.0 and refunded.player.hands[0].lucky_nine_bonus == 0.0)
	var dealer_blackjack := _scenario([4, 5], [14, 10], [], 10.0, 100.0, false, false, true)
	_expect(dealer_blackjack.round_over and dealer_blackjack.player.money == 90.0 and dealer_blackjack.player.hands[0].bonus_payout == 0.0)
	var soft_nineteen := _scenario([14, 8], [10, 7], [], 10.0, 100.0, false, false, true)
	_expect(not soft_nineteen.player.hands[0].lucky_nine_qualified)
	soft_nineteen.player_stand()
	_expect(soft_nineteen.player.money == 110.0)
	var off := _scenario([4, 5], [10, 7], [10])
	off.player_hit()
	off.player_stand()
	_expect(not off.player.hands[0].lucky_nine_qualified and off.player.money == 110.0)
	print("PASS: Lucky 9 pays on dealer bust; no bonus for push, loss, bust, refund, dealer Blackjack, soft 19, or Classic mode")


## Preserve original eligibility through Reroll/recovery, remove it on Split, and select it randomly.
func test_lucky_nine_combinations() -> void:
	var recovered := _scenario([4, 5], [10, 7], [10, 10, 5], 10.0, 100.0, true, true, true)
	_expect(recovered.player_hit() and recovered.player_reroll(0) and recovered.can_second_chance())
	_expect(recovered.player_second_chance() and recovered.player.hand.get_total() == 15 and recovered.player.hands[0].lucky_nine_qualified)
	_expect(recovered.player_hit() and recovered.player_stand() and recovered.player.money == 115.0)
	var newly_nine := _scenario([4, 6], [10, 7], [5, 10], 10.0, 100.0, true, false, true)
	_expect(newly_nine.player_reroll(1) and newly_nine.player.hand.get_total() == 9 and not newly_nine.player.hands[0].lucky_nine_qualified)
	newly_nine.player_hit()
	newly_nine.player_stand()
	_expect(newly_nine.player.money == 110.0)
	var split := _scenario([4, 5], [10, 7], [5, 4, 4, 10, 10], 10.0, 100.0, true, false, true)
	_expect(split.player_reroll(0) and split.can_split() and split.player_split())
	_expect(split.player.hands[0].hand.get_total() == 9 and split.player.hands[1].hand.get_total() == 9)
	_expect(not split.player.hands[0].lucky_nine_qualified and not split.player.hands[1].lucky_nine_qualified)
	split.player_hit()
	split.player_stand()
	split.player_hit()
	split.player_stand()
	_expect(split.player.money == 120.0 and split.player.hands[0].bonus_payout == 0.0 and split.player.hands[1].bonus_payout == 0.0)
	var manager := RuleManager.new()
	_expect(manager.configure(RuleManager.RuleMode.RANDOM_SELECTED, [&"reroll", &"second_chance", &"lucky_nine"], 1))
	manager._rng.seed = 42
	var seen: Dictionary = {}
	for round_index in range(30):
		manager.prepare_round()
		_expect(manager.active_rules.size() == 1)
		seen[manager.active_rules[0].rule_id] = true
	_expect(seen.size() == 3 and seen.has(&"lucky_nine"))
	manager.configure(RuleManager.RuleMode.RANDOM_SELECTED, [&"reroll", &"second_chance", &"lucky_nine"], 3)
	manager.prepare_round()
	_expect(manager.active_rules.size() == 3)
	print("PASS: Lucky 9 survives Reroll/Second Chance, cannot be created by Reroll or duplicated by Split, and enters the Random pool")


## Inspect potential/settled bonus labels, colored net amounts, resizing, and next-deal clearing.
func test_lucky_nine_ui() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 640)
	add_child(viewport)
	var ui := preload("res://scenes/game.tscn").instantiate()
	viewport.add_child(ui)
	if not ui.has_method("_refresh_ui"):
		_expect(false, "Lucky 9 UI script failed to load")
		viewport.free()
		return
	ui._populate_rule_settings()
	ui.rule_mode_option.select(RuleManager.RuleMode.ALL_SELECTED)
	ui.rule_checkboxes[&"lucky_nine"].button_pressed = true
	ui.rule_dialog.confirmed.emit()
	_expect(ui.game.rules.selected_rule_ids.has(&"lucky_nine") and ui.active_rules_label.text.contains("Lucky 9"))
	ui.game = _scenario([4, 5], [10, 7], [10, 10, 5], 10.0, 100.0, true, true, true)
	ui._refresh_ui()
	_expect(ui.rule_checkboxes.has(&"lucky_nine") and ui.random_count_spin.max_value == 5)
	_expect(not ui.round_delta_label.visible and ui.round_delta_label.text.is_empty())
	_expect(ui.active_rules_label.text.contains("Lucky 9"))
	_expect(ui.hand_panels[0].get_node("HandLayout/LuckyNineLabel").text.contains("+$5.00 bonus on a win"))
	ui.hit_button.pressed.emit()
	ui.game.player_reroll(0)
	ui._refresh_ui()
	for window_size in [Vector2i(640, 560), Vector2i(960, 640), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = window_size
		for frame in range(6):
			await get_tree().process_frame
		for button in [ui.hit_button, ui.stand_button, ui.double_button, ui.split_button, ui.reroll_button, ui.second_chance_button]:
			_expect(Rect2(Vector2.ZERO, Vector2(window_size)).encloses(button.get_global_rect()), "All rule controls must fit at %s" % window_size)
		var card: Control = ui.hand_panels[0].get_node("HandLayout/Cards").get_child(0)
		_expect(ui.table_scroll.get_global_rect().encloses(card.get_global_rect()), "Lucky 9 cards must remain readable at %s" % window_size)
		var heading: Control = ui.hand_panels[0].get_node("HandLayout").get_child(0)
		_expect(ui.table_scroll.get_global_rect().encloses(heading.get_global_rect()), "Lucky 9 hand total must remain visible at %s" % window_size)
	ui.second_chance_button.pressed.emit()
	ui.hit_button.pressed.emit()
	ui.stand_button.pressed.emit()
	_expect(ui.round_delta_label.visible and ui.round_delta_label.text == "Round: +$15.00")
	_expect(ui.hand_panels[0].get_node("HandLayout/LuckyNineLabel").text == "LUCKY 9 BONUS · +$5.00")
	_expect(ui.status_label.text.contains("Lucky 9 bonus: +$5.00"))
	ui.bet_spin_box.value = 10.0
	ui.deal_button.pressed.emit()
	_expect(not ui.game.round_over and not ui.round_delta_label.visible and ui.round_delta_label.text.is_empty())
	_expect(ui.hand_panels[0].get_node("HandLayout/HandDetails/HandStatus").text == "YOUR TURN", "New hand must not display the previous result")
	ui.game = _scenario([10, 5], [10, 7], [10])
	ui.hit_button.pressed.emit()
	_expect(ui.round_delta_label.visible and ui.round_delta_label.text == "Round: −$10.00")
	ui.deal_button.pressed.emit()
	_expect(not ui.round_delta_label.visible and ui.round_delta_label.text.is_empty())
	# Instant opening Blackjack is a completed new round and shows its own result.
	ui.game = _scenario([14, 10], [10, 7], [])
	ui._refresh_ui()
	ui.deal_button.pressed.emit()
	_expect(ui.game.round_over and ui.round_delta_label.visible and ui.round_delta_label.text == "Round: +$15.00")
	viewport.free()
	print("PASS: Lucky 9 qualification/bonus labels, three-rule layouts, and green/red results vanish on the next deal")


## Draw every target 22-30, preserve the target during a round, and include it in Random selection.
func test_double_target_randomization() -> void:
	var manager := RuleManager.new()
	var target_rule := manager.get_rule(&"double_target") as DoubleTargetRule
	target_rule._rng.seed = 42
	manager.configure(RuleManager.RuleMode.ALL_SELECTED, [&"double_target"])
	var seen: Dictionary = {}
	for round_index in range(100):
		manager.prepare_round()
		_expect(target_rule.target_total >= 22 and target_rule.target_total <= 30)
		seen[target_rule.target_total] = true
	_expect(seen.size() == 9, "Seeded target draws must cover every value from 22 through 30")
	manager.configure(RuleManager.RuleMode.OFF, [&"double_target"])
	manager.prepare_round()
	_expect(not target_rule.active and target_rule.target_total == 0)
	manager._rng.seed = 42
	manager.configure(RuleManager.RuleMode.RANDOM_SELECTED, [&"reroll", &"second_chance", &"lucky_nine", &"double_target"], 1)
	var selected: Dictionary = {}
	for round_index in range(50):
		manager.prepare_round()
		_expect(manager.active_rules.size() == 1)
		selected[manager.active_rules[0].rule_id] = true
		_expect(target_rule.target_total >= 22 if target_rule.active else target_rule.target_total == 0)
	_expect(selected.size() == 4)
	print("PASS: Double Target draws all nine totals from 22–30, resets when inactive, and joins the four-rule Random pool")


## Win exact busts at all nine targets; check misses, Ace values, first-bust limits, and cent rounding.
func test_double_target_flow() -> void:
	for target_total in range(22, 31):
		var game := _scenario([10, target_total - 20], [10, 2], [10, 10], 10.0, 100.0, false, false, false, target_total)
		var target_rule := game.rules.get_rule(&"double_target") as DoubleTargetRule
		var rng_state := target_rule._rng.state
		_expect(game.get_double_target() == target_total and not game.start_round(10.0) and game.get_double_target() == target_total)
		_expect(game.player_hit() and game.round_over and game.player.hand.get_total() == target_total)
		_expect(game.result == BlackjackGame.RoundResult.DOUBLE_TARGET_WIN and game.player.money == 102.5)
		_expect(game.last_round_delta == 2.5 and game.player.hands[0].net_result == 2.5 and game.player.bet == 0.0)
		_expect(game.dealer.hand.card_count() == 2 and game.deck.cards_remaining() == 1, "A special bust payout must not require a dealer draw")
		_expect(target_rule._rng.state == rng_state, "Matching a target must not perform another success roll")
		_expect(not game.player_hit() and not game.player_stand() and not game.player_second_chance())
	var missed := _scenario([10, 10], [10, 7], [9, 14], 10.0, 100.0, false, false, false, 30)
	_expect(missed.player_hit() and missed.round_over and missed.player.money == 90.0)
	_expect(not missed.player_hit() and missed.deck.cards_remaining() == 1, "A bust at 29 cannot keep drawing to reach target 30")
	var off := _scenario([10, 5], [10, 7], [10])
	_expect(off.get_double_target() == 0 and off.player_hit() and off.player.money == 90.0)
	var ace := _scenario([14, 9], [10, 7], [10], 10.0, 100.0, false, false, false, 30)
	_expect(ace.player_hit() and ace.player.hand.get_total() == 20 and not ace.is_double_target_match(ace.player.hands[0]))
	_expect(ace.player_stand() and ace.player.money == 110.0)
	var fractional := _scenario([10, 5], [10, 7], [10], 1.25, 100.0, false, false, false, 25)
	fractional.player_hit()
	_expect(is_equal_approx(fractional.player.money, 100.31) and is_equal_approx(fractional.last_round_delta, 0.31))
	print("PASS: Every exact target automatically returns $12.50 on a $10 wager; misses, Ace handling, and first-bust limits remain classic")


## Recover or keep matching/missed busts and preserve Second Chance when taking a payout.
func test_double_target_second_chance() -> void:
	var kept := _scenario([10, 8], [10, 7], [7], 10.0, 100.0, false, true, false, 25)
	_expect(kept.player_hit() and kept.is_awaiting_second_chance() and not kept.round_over and kept.player.money == 90.0)
	_expect(kept.status_message.contains("$12.50") and kept.get_double_target() == 25)
	_expect(not kept.player_hit() and not kept.player_double() and not kept.player_reroll(0))
	_expect(kept.player_stand() and kept.round_over and kept.player.money == 102.5)
	_expect(not (kept.rules.get_rule(&"second_chance") as SecondChanceRule).has_used(kept.player))
	var recovered := _scenario([10, 8], [10, 7], [7], 10.0, 100.0, false, true, false, 25)
	_expect(recovered.player_hit() and recovered.player_second_chance() and recovered.player.hand.get_total() == 18)
	_expect(not recovered.is_double_target_match(recovered.player.hands[0]) and recovered.player_stand() and recovered.player.money == 110.0)
	var miss := _scenario([10, 8], [10, 7], [6], 10.0, 100.0, false, true, false, 25)
	_expect(miss.player_hit() and miss.can_second_chance() and not miss.is_double_target_match(miss.player.hands[0]))
	_expect(miss.player_second_chance() and miss.player.hand.get_total() == 18 and miss.player_stand())
	_expect(miss.player.money == 110.0)
	var declined_miss := _scenario([10, 8], [10, 7], [6], 10.0, 100.0, false, true, false, 25)
	_expect(declined_miss.player_hit() and declined_miss.player_stand() and declined_miss.player.money == 90.0)
	print("PASS: Exact-target bust offers recovery or payout; taking payout preserves Second Chance, which still recovers any other bust")


## Settle split exact-bust claims independently, share the target, and refund canceled rounds.
func test_double_target_splits() -> void:
	var mixed := _scenario([8, 8], [10, 7], [10, 10, 7], 10.0, 100.0, false, false, false, 25)
	_expect(mixed.player_split() and mixed.player_hit() and mixed.player.active_hand_index == 1 and mixed.get_double_target() == 25)
	_expect(mixed.player_stand() and mixed.player.money == 112.5)
	_expect(mixed.player.hands[0].result == BlackjackGame.RoundResult.DOUBLE_TARGET_WIN and mixed.player.hands[0].net_result == 2.5)
	_expect(mixed.player.hands[1].result == BlackjackGame.RoundResult.PLAYER_WIN and mixed.player.hands[1].net_result == 10.0)
	_expect(mixed.last_round_delta == 12.5)
	var both := _scenario([8, 8], [10, 2], [10, 10, 7, 7, 10], 10.0, 100.0, false, false, false, 25)
	_expect(both.player_split() and both.player_hit() and both.player_hit() and both.round_over)
	_expect(both.player.money == 105.0 and both.dealer.hand.card_count() == 2 and both.last_round_delta == 5.0)
	var saved := _scenario([8, 8], [10, 7], [10, 10, 7, 8], 10.0, 100.0, false, true, false, 25)
	_expect(saved.player_split() and saved.player_hit() and saved.player_stand())
	_expect(saved.player.active_hand_index == 1 and saved.get_double_target() == 25 and saved.player_hit() and saved.can_second_chance())
	_expect(saved.player_second_chance() and saved.player_stand() and saved.player.money == 112.5)
	var used := _scenario([8, 8], [10, 7], [10, 10, 7, 7], 10.0, 100.0, false, true, false, 25)
	_expect(used.player_split() and used.player_hit() and used.player_second_chance() and used.player_stand())
	_expect(used.player_hit() and used.round_over and used.player.money == 112.5)
	var refunded := _scenario([8, 8], [10, 2], [10, 5, 7], 10.0, 100.0, false, false, false, 25)
	_expect(refunded.player_split() and refunded.player_hit() and refunded.player_stand())
	_expect(refunded.player.money == 100.0 and refunded.result == BlackjackGame.RoundResult.NONE and refunded.last_round_delta == 0.0)
	print("PASS: Split hands share one target and settle independently; two exact busts both pay, saved/used recovery works, and cancellation refunds")


## Combine doubled stakes, Reroll, recovery, and Lucky 9 without stacking its bonus onto a bust payout.
func test_double_target_combinations() -> void:
	var doubled := _scenario([10, 8], [10, 7], [7], 10.0, 100.0, false, false, false, 25)
	_expect(doubled.player_double() and doubled.player.money == 105.0 and doubled.last_round_delta == 5.0)
	_expect(doubled.player.hands[0].wager == 20.0 and doubled.player.hands[0].net_result == 5.0)
	var recovered_double := _scenario([10, 8], [10, 7], [7], 10.0, 100.0, false, true, false, 25)
	_expect(recovered_double.player_double() and recovered_double.player_second_chance() and recovered_double.round_over and recovered_double.player.money == 120.0)
	var rerolled := _scenario([10, 5], [10, 7], [5, 10], 10.0, 100.0, true, false, false, 25)
	_expect(rerolled.player_hit() and rerolled.player_reroll(1) and rerolled.round_over and rerolled.player.money == 102.5)
	var lucky_kept := _scenario([4, 5], [10, 7], [10, 6], 10.0, 100.0, false, true, true, 25)
	_expect(lucky_kept.player_hit() and lucky_kept.player_hit() and lucky_kept.player_stand())
	_expect(lucky_kept.player.money == 102.5 and lucky_kept.player.hands[0].lucky_nine_bonus == 0.0 and lucky_kept.player.hands[0].bonus_payout == 0.0)
	var lucky_recovered := _scenario([4, 5], [10, 7], [10, 6], 10.0, 100.0, false, true, true, 25)
	_expect(lucky_recovered.player_hit() and lucky_recovered.player_hit() and lucky_recovered.player_second_chance() and lucky_recovered.player_stand())
	_expect(lucky_recovered.player.money == 115.0 and lucky_recovered.player.hands[0].lucky_nine_bonus == 5.0)
	var natural := _scenario([14, 10], [10, 7], [], 10.0, 100.0, false, false, false, 25)
	_expect(natural.round_over and natural.player.money == 115.0)
	var dealer_natural := _scenario([10, 8], [14, 10], [7], 10.0, 100.0, false, true, false, 25)
	_expect(dealer_natural.round_over and dealer_natural.player.money == 90.0 and not dealer_natural.player_hit())
	var fresh := _scenario([10, 5], [10, 7], [10], 10.0, 100.0, false, false, false, 25)
	var target_rule := fresh.rules.get_rule(&"double_target") as DoubleTargetRule
	var probe := RandomNumberGenerator.new()
	probe.state = target_rule._rng.state
	var next_target := probe.randi_range(22, 30)
	_expect(fresh.player_hit() and fresh.start_round(10.0) and fresh.get_double_target() == next_target)
	_expect(not fresh.has_round_result and fresh.last_round_delta == 0.0)
	print("PASS: Double Target uses doubled wagers and Reroll busts, excludes Lucky 9 stacking, preserves recovered Lucky 9 and naturals, and redraws on next round")


## Display the target and recovery/payout choices, then check small-win colors, split summaries, and reset.
func test_double_target_ui() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 640)
	add_child(viewport)
	var ui := preload("res://scenes/game.tscn").instantiate()
	viewport.add_child(ui)
	if not ui.has_method("_refresh_ui"):
		_expect(false, "Double Target UI script failed to load")
		viewport.free()
		return
	ui._populate_rule_settings()
	ui.rule_mode_option.select(RuleManager.RuleMode.ALL_SELECTED)
	ui.rule_checkboxes[&"double_target"].button_pressed = true
	ui.rule_dialog.confirmed.emit()
	_expect(ui.game.rules.selected_rule_ids.has(&"double_target") and ui.active_rules_label.text.contains("Double Target"))
	_expect(ui.random_count_spin.max_value == 5)
	ui.game = _scenario([4, 5], [10, 7], [10, 6], 10.0, 100.0, true, true, true, 25)
	ui._refresh_ui()
	_expect(ui.active_rules_label.text.contains("Double Target: 25"), "Target must be visible before the first player action")
	ui.hit_button.pressed.emit()
	ui.hit_button.pressed.emit()
	_expect(ui.stand_button.text == "Take Payout" and not ui.stand_button.disabled and not ui.second_chance_button.disabled)
	_expect(ui.status_label.text.contains("$12.50") and not ui.round_delta_label.visible)
	_expect(ui.hand_panels[0].get_node("HandLayout/LuckyNineLabel").text.contains("recover and win"), "Lucky 9 must not imply a bonus on the small bust payout")
	_expect(ui.hit_button.disabled and ui.double_button.disabled and ui.split_button.disabled and ui.reroll_button.disabled)
	for window_size in [Vector2i(640, 560), Vector2i(960, 640), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = window_size
		for frame in range(6):
			await get_tree().process_frame
		for control in [ui.hit_button, ui.stand_button, ui.double_button, ui.split_button, ui.reroll_button, ui.second_chance_button, ui.status_label, ui.active_rules_label]:
			_expect(Rect2(Vector2.ZERO, Vector2(window_size)).encloses(control.get_global_rect()), "Double Target controls must fit at %s" % window_size)
		var card: Control = ui.hand_panels[0].get_node("HandLayout/Cards").get_child(0)
		_expect(ui.table_scroll.get_global_rect().encloses(card.get_global_rect()), "Four-rule cards must remain readable at %s" % window_size)
	ui.stand_button.pressed.emit()
	_expect(ui.game.player.money == 102.5 and ui.round_delta_label.text == "Round: +$2.50" and ui.round_delta_label.get_theme_color("font_color") == ui.GAIN)
	_expect(ui.hand_panels[0].get_node("HandLayout/HandDetails/HandStatus").text.contains("Double Target 25! Small win."))
	_expect(ui.hand_panels[0].get_node("HandLayout/LuckyNineLabel").text.contains("no bonus"))
	_expect(not (ui.game.rules.get_rule(&"second_chance") as SecondChanceRule).has_used(ui.game.player))
	ui.deal_button.pressed.emit()
	_expect(not ui.round_delta_label.visible and ui.game.get_double_target() >= 22 and ui.game.get_double_target() <= 30)
	ui.game = _scenario([10, 8], [10, 7], [7], 10.0, 100.0, false, true, false, 25)
	ui.hit_button.pressed.emit()
	ui.second_chance_button.pressed.emit()
	_expect(ui.game.player.hand.get_total() == 18 and ui.stand_button.text == "Stand" and ui.game.get_double_target() == 25)
	ui.game = _scenario([10, 8], [10, 7], [6], 10.0, 100.0, false, true, false, 25)
	ui.hit_button.pressed.emit()
	_expect(ui.stand_button.text == "Accept Bust" and not ui.second_chance_button.disabled)
	ui.game = _scenario([8, 8], [10, 7], [10, 10, 7], 10.0, 100.0, false, false, false, 25)
	ui.game.player_split()
	ui.hit_button.pressed.emit()
	_expect(ui.hand_panels[0].get_node("HandLayout/HandDetails/HandStatus").text.contains("payout secured"))
	ui.stand_button.pressed.emit()
	_expect(ui.status_label.text.contains("2 won / 0 lost") and ui.round_delta_label.text == "Round: +$12.50")
	ui.restart_button.pressed.emit()
	_expect(ui.game.get_double_target() == 0 and not ui.round_delta_label.visible and ui.game.rules.selected_rule_ids.has(&"double_target"))
	viewport.free()
	print("PASS: Target shown before play, recovery/payout buttons, four-rule layouts, special wins and split summaries, next-deal clearing, and restart settings")
