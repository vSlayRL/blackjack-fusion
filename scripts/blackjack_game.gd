class_name BlackjackGame
extends Resource

const MINIMUM_BET: float = 1.0
const MAX_PLAYER_HANDS: int = 4

enum RoundState {
	WAITING_FOR_BET,
	PLAYER_TURN,
	DEALER_TURN,
	ROUND_OVER,
	MYSTERY_CARD_CHOICE
}

enum RoundResult {
	NONE,
	PLAYER_BLACKJACK,
	DEALER_BLACKJACK,
	PLAYER_WIN,
	DEALER_WIN,
	PUSH,
	PLAYER_BUST,
	DEALER_BUST,
	DOUBLE_TARGET_WIN
}

var deck: Deck
var player: Player
var dealer: Dealer
var rules: RuleManager = RuleManager.new()
var last_rule_message: String = ""
var last_round_delta: float = 0.0
var has_round_result: bool = false
var _round_start_money: float = 0.0
var _pending_bust_index: int = -1
var _pending_bust_action: StringName = &""
var state: int = RoundState.WAITING_FOR_BET
# For one hand, result retains its original meaning. Split results live on
# player.hands[i].result; get_result_text() summarizes all of them.
var result: int = RoundResult.NONE
var round_over: bool = true
var status_message: String = "Place a bet to begin."


func _init():
	deck = Deck.new()
	player = Player.new("Steve", 100.0)
	dealer = Dealer.new()


func start_round(bet_amount: float) -> bool:
	if not round_over:
		status_message = "The current round is still in progress."
		return false
	if not is_finite(bet_amount) or bet_amount < MINIMUM_BET:
		status_message = "Minimum bet is $%.2f." % MINIMUM_BET
		return false
	if not player.place_bet(bet_amount):
		status_message = "Invalid bet or insufficient money."
		return false

	deck.reset()
	last_round_delta = 0.0
	has_round_result = false
	_round_start_money = player.money + bet_amount
	_pending_bust_index = -1
	_pending_bust_action = &""
	player.reset_hand()
	dealer.reset_hand()
	state = RoundState.PLAYER_TURN
	result = RoundResult.NONE
	round_over = false
	last_rule_message = ""
	rules.prepare_round()
	_notify_rules(&"round_started")

	# Player, dealer, player, dealer. Mystery Card finalizes the opening
	# before either Blackjack is resolved or normal actions become available.
	for i in range(2):
		if not _deal_to_player() or not _deal_to_dealer():
			_cancel_round("Unable to complete the opening deal. Bets returned.")
			return false
	if rules.is_rule_active(&"mystery_card"):
		state = RoundState.MYSTERY_CARD_CHOICE
		status_message = "Mystery Card: keep your hidden card, or replace it once."
	else:
		_finalize_opening()
	return true


func is_awaiting_mystery_card() -> bool:
	return not round_over and state == RoundState.MYSTERY_CARD_CHOICE


func is_player_card_hidden(hand_index: int, card_index: int) -> bool:
	return is_awaiting_mystery_card() and hand_index == 0 and card_index == 1


func can_replace_mystery_card() -> bool:
	return is_awaiting_mystery_card() and not deck.is_empty()


func player_choose_mystery_card(replace_card: bool = false) -> bool:
	if not is_awaiting_mystery_card():
		return false
	var rule := rules.get_rule(&"mystery_card") as MysteryCardRule
	if rule == null or not rule.apply(player, deck, replace_card):
		status_message = "No replacement available. Keep your hidden card to continue."
		return false
	state = RoundState.PLAYER_TURN
	last_rule_message = "Mystery Card replaced and revealed." if replace_card else "Mystery Card kept and revealed."
	_finalize_opening()
	return true


func _finalize_opening() -> void:
	_check_starting_blackjacks()
	if not round_over:
		# Lucky 9 sees the final opening hand, never the concealed original.
		_notify_rules(&"opening_dealt")


func player_hit() -> bool:
	if not is_player_turn():
		return false
	last_rule_message = ""
	if not _deal_to_player():
		status_message = "Unable to draw a card."
		return false
	_notify_rules(&"hand_changed", &"hit", player.hand.card_count() - 1)
	if player.hand.is_bust():
		_handle_player_bust(&"hit", player.hand.card_count() - 1)
	elif player.hand.has_21():
		_advance_hand()
	else:
		_update_player_status()
	return true


func player_stand() -> bool:
	if is_awaiting_second_chance():
		last_rule_message = "Double Target payout accepted." if is_double_target_match(player.hands[player.active_hand_index]) else "Bust accepted."
		_advance_hand()
		return true
	if not is_player_turn():
		return false
	last_rule_message = ""
	_advance_hand()
	return true


func can_double() -> bool:
	return (
		is_player_turn()
		and player.hand.card_count() == 2
		and not player.hands[player.active_hand_index].split_aces
		and player.bet > 0.0
		and player.money >= player.bet
		and deck.cards_remaining() >= 1
	)


func player_double() -> bool:
	if not can_double():
		return false
	last_rule_message = ""
	# Verify card availability before deducting the additional wager.
	var card := deck.deal_card()
	if card == null:
		return false
	player.add_to_bet(player.bet)
	player.hands[player.active_hand_index].doubled = true
	player.hand.add_card(card)
	_notify_rules(&"hand_changed", &"double", player.hand.card_count() - 1)
	# Exactly one card, then the next hand (or the dealer), even after bust.
	if player.hand.is_bust():
		_handle_player_bust(&"double", player.hand.card_count() - 1)
	else:
		_advance_hand()
	return true


func can_split() -> bool:
	return (
		is_player_turn()
		and player.hands.size() < MAX_PLAYER_HANDS
		and not player.hands[player.active_hand_index].split_aces
		and player.hand.card_count() == 2
		and player.hand.cards[0].get_blackjack_value() == player.hand.cards[1].get_blackjack_value()
		and player.bet > 0.0
		and player.money >= player.bet
		and deck.cards_remaining() >= 2
	)


func player_split() -> bool:
	if not can_split():
		return false
	last_rule_message = ""
	var current := player.hands[player.active_hand_index]
	var new_hand := PlayerHand.new(current.bet)
	var second_card: Card = current.hand.cards.pop_back()
	new_hand.hand.add_card(second_card)
	current.is_split = true
	new_hand.is_split = true
	current.split_aces = current.hand.cards[0].rank == Card.Rank.ACE
	new_hand.split_aces = current.split_aces
	player.money -= new_hand.bet
	# Insert immediately after this hand to preserve left-to-right turns.
	player.hands.insert(player.active_hand_index + 1, new_hand)
	current.hand.add_card(deck.deal_card())
	new_hand.hand.add_card(deck.deal_card())
	_notify_rules(&"hand_changed", &"split")

	# Split Aces get one card each. Split 21 is a normal 21, not Blackjack.
	new_hand.is_standing = new_hand.split_aces or new_hand.hand.has_21()
	if current.split_aces or current.hand.has_21():
		_advance_hand()
	else:
		_update_player_status()
	return true


func configure_rules(mode: int, selected: Array[StringName], random_count: int = 1) -> bool:
	# Settings are frozen for the duration of the current round.
	if not round_over:
		return false
	return rules.configure(mode, selected, random_count)


func can_reroll(card_index: int = -1) -> bool:
	var rule := rules.get_rule(&"reroll") as RerollRule
	if not is_player_turn() or rule == null or not rule.can_use(player):
		return false
	if player.hands[player.active_hand_index].split_aces or deck.is_empty():
		return false
	return card_index == -1 or (card_index >= 0 and card_index < player.hand.card_count())


func player_reroll(card_index: int) -> bool:
	if card_index < 0 or not can_reroll(card_index):
		return false
	var rule := rules.get_rule(&"reroll") as RerollRule
	var old_name := player.hand.cards[card_index].get_card_name()
	if not rule.apply(player, deck, card_index):
		return false
	last_rule_message = "Reroll: %s → %s." % [old_name, player.hand.cards[card_index].get_card_name()]
	_notify_rules(&"hand_changed", &"reroll", card_index)
	# Replacements are evaluated exactly like normal card changes.
	if player.hand.is_bust():
		_handle_player_bust(&"reroll", card_index)
	elif player.hand.has_21():
		_advance_hand()
	else:
		_update_player_status()
	return true


func _handle_player_bust(action: StringName, card_index: int) -> void:
	var rule := rules.get_rule(&"second_chance") as SecondChanceRule
	if rule != null and rule.can_use(player) and not player.hands[player.active_hand_index].split_aces:
		_pending_bust_index = card_index
		_pending_bust_action = action
		status_message = "Bust! Use Second Chance to remove %s, or Accept Bust." % player.hand.cards[card_index].get_card_name()
		if is_double_target_match(player.hands[player.active_hand_index]):
			status_message = "Target %d! Recover with Second Chance, or take $%.2f back." % [get_double_target(), DoubleTargetRule.total_return(player.bet)]
	else:
		_advance_hand()


func get_double_target() -> int:
	var rule := rules.get_rule(&"double_target") as DoubleTargetRule
	return rule.target_total if rule != null and rule.active else 0


func is_double_target_match(played_hand: PlayerHand) -> bool:
	var rule := rules.get_rule(&"double_target") as DoubleTargetRule
	return rule != null and rule.matches(played_hand.hand)


func is_awaiting_second_chance() -> bool:
	return not round_over and state == RoundState.PLAYER_TURN and _pending_bust_index >= 0 and player.hand.is_bust()


func can_second_chance() -> bool:
	var rule := rules.get_rule(&"second_chance") as SecondChanceRule
	return is_awaiting_second_chance() and rule != null and rule.can_use(player)


func player_second_chance() -> bool:
	if not can_second_chance():
		return false
	var rule := rules.get_rule(&"second_chance") as SecondChanceRule
	var removed_name := player.hand.cards[_pending_bust_index].get_card_name()
	var rescued_double := _pending_bust_action == &"double"
	var removed_index := _pending_bust_index
	if not rule.apply(player, removed_index):
		return false
	_pending_bust_index = -1
	_pending_bust_action = &""
	last_rule_message = "Second Chance: removed %s." % removed_name
	_notify_rules(&"hand_changed", &"second_chance", removed_index)
	# Double still means one draw and then stand, even if that draw is discarded.
	if rescued_double or player.hand.has_21():
		_advance_hand()
	else:
		_update_player_status()
	return true


func _notify_rules(event: StringName, action: StringName = &"", card_index: int = -1) -> void:
	rules.dispatch(event, {"game": self, "player": player, "dealer": dealer, "deck": deck, "hand": player.hands[player.active_hand_index], "action": action, "card_index": card_index})


func _advance_hand() -> void:
	_pending_bust_index = -1
	_pending_bust_action = &""
	player.is_standing = true
	for i in range(player.active_hand_index + 1, player.hands.size()):
		if not player.hands[i].is_standing:
			player.active_hand_index = i
			_update_player_status()
			return

	# Only run the dealer if at least one hand survived.
	var all_busted := true
	for played_hand in player.hands:
		if not played_hand.hand.is_bust():
			all_busted = false
			break
	if all_busted:
		_resolve_round()
		return

	state = RoundState.DEALER_TURN
	status_message = "Dealer turn."
	dealer_turn()
	if not round_over:
		_resolve_round()


func dealer_turn() -> void:
	if round_over or state != RoundState.DEALER_TURN:
		return
	# Stand on all 17s, including soft 17.
	while dealer.should_hit():
		if not _deal_to_dealer():
			_cancel_round("Dealer could not draw. All bets returned.")
			return
		if dealer.hand.is_bust():
			break


func is_player_turn() -> bool:
	return not round_over and state == RoundState.PLAYER_TURN and not player.is_standing and not is_awaiting_second_chance()


func is_dealer_turn() -> bool:
	return not round_over and state == RoundState.DEALER_TURN


func can_start_round() -> bool:
	return round_over and player.money >= MINIMUM_BET


func get_result_text() -> String:
	if not round_over or result == RoundResult.NONE:
		return "Round is still in progress."
	if player.hands.size() == 1:
		return get_hand_result_text(result)
	var summaries: PackedStringArray = []
	for i in range(player.hands.size()):
		summaries.append("Hand %d: %s" % [i + 1, get_hand_result_text(player.hands[i].result)])
	return "\n".join(summaries)


func get_hand_result_text(hand_result: int) -> String:
	match hand_result:
		RoundResult.PLAYER_BLACKJACK:
			return "Blackjack! Player wins."
		RoundResult.DEALER_BLACKJACK:
			return "Dealer has Blackjack."
		RoundResult.PLAYER_WIN:
			return "Player wins."
		RoundResult.DEALER_WIN:
			return "Dealer wins."
		RoundResult.PUSH:
			return "Push. Bet returned."
		RoundResult.PLAYER_BUST:
			return "Player busts. Dealer wins."
		RoundResult.DEALER_BUST:
			return "Dealer busts. Player wins."
		RoundResult.DOUBLE_TARGET_WIN:
			return "Double Target %d! Small win." % get_double_target()
		_:
			return "Round is still in progress."


func _deal_to_player() -> bool:
	var card := deck.deal_card()
	if card == null:
		return false
	player.hand.add_card(card)
	return true


func _deal_to_dealer() -> bool:
	var card := deck.deal_card()
	if card == null:
		return false
	dealer.hand.add_card(card)
	return true


func _check_starting_blackjacks() -> void:
	var player_blackjack := player.hands[0].is_natural_blackjack()
	var dealer_blackjack := dealer.hand.is_blackjack()
	if player_blackjack and dealer_blackjack:
		_finish_round(RoundResult.PUSH)
	elif player_blackjack:
		_finish_round(RoundResult.PLAYER_BLACKJACK)
	elif dealer_blackjack:
		_finish_round(RoundResult.DEALER_BLACKJACK)
	else:
		_update_player_status()


func _resolve_round() -> void:
	for played_hand in player.hands:
		if is_double_target_match(played_hand):
			played_hand.result = RoundResult.DOUBLE_TARGET_WIN
		elif played_hand.hand.is_bust():
			played_hand.result = RoundResult.PLAYER_BUST
		elif dealer.hand.is_bust():
			played_hand.result = RoundResult.DEALER_BUST
		elif played_hand.hand.get_total() > dealer.hand.get_total():
			played_hand.result = RoundResult.PLAYER_WIN
		elif played_hand.hand.get_total() < dealer.hand.get_total():
			played_hand.result = RoundResult.DEALER_WIN
		else:
			played_hand.result = RoundResult.PUSH
	_complete_round()


func _finish_round(round_result: int) -> void:
	player.hands[player.active_hand_index].result = round_result
	_complete_round()


func _complete_round() -> void:
	_notify_rules(&"before_settlement")
	var previous_index := player.active_hand_index
	for i in range(player.hands.size()):
		player.active_hand_index = i
		player.is_standing = true
		var money_before := player.money
		match player.hands[i].result:
			RoundResult.PLAYER_BLACKJACK:
				player.win_blackjack()
			RoundResult.PLAYER_WIN, RoundResult.DEALER_BUST:
				player.win()
			RoundResult.PUSH:
				player.push()
			RoundResult.DOUBLE_TARGET_WIN:
				player.settle_return(DoubleTargetRule.total_return(player.bet))
			_:
				player.lose()
		player.money += player.hands[i].bonus_payout
		player.hands[i].net_result = player.money - money_before - player.hands[i].wager
	player.active_hand_index = previous_index
	result = player.hands[0].result
	state = RoundState.ROUND_OVER
	round_over = true
	_record_round_delta()
	status_message = get_result_text()
	_notify_rules(&"round_finished")


func _cancel_round(message: String) -> void:
	var previous_index := player.active_hand_index
	for i in range(player.hands.size()):
		player.active_hand_index = i
		player.push()
		player.is_standing = true
		player.hands[i].result = RoundResult.NONE
		player.hands[i].net_result = 0.0
		player.hands[i].bonus_payout = 0.0
		player.hands[i].lucky_nine_bonus = 0.0
	player.active_hand_index = previous_index
	state = RoundState.ROUND_OVER
	result = RoundResult.NONE
	round_over = true
	_pending_bust_index = -1
	_pending_bust_action = &""
	_record_round_delta()
	status_message = message
	_notify_rules(&"round_finished")


func _record_round_delta() -> void:
	last_round_delta = player.money - _round_start_money
	has_round_result = true


func _update_player_status() -> void:
	status_message = "Player turn. Hit, stand, double, or split when available."
	if player.hands.size() > 1:
		status_message = "Playing hand %d of %d. Hit, stand, double, or split when available." % [player.active_hand_index + 1, player.hands.size()]
