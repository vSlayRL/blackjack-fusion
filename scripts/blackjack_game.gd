class_name BlackjackGame
extends Resource


const MINIMUM_BET: float = 1.0


enum RoundState {
	WAITING_FOR_BET,
	PLAYER_TURN,
	DEALER_TURN,
	ROUND_OVER
}


enum RoundResult {
	NONE,
	PLAYER_BLACKJACK,
	DEALER_BLACKJACK,
	PLAYER_WIN,
	DEALER_WIN,
	PUSH,
	PLAYER_BUST,
	DEALER_BUST
}


var deck: Deck
var player: Player
var dealer: Dealer

var state: int = RoundState.WAITING_FOR_BET
var result: int = RoundResult.NONE
var round_over: bool = true
var status_message: String = "Place a bet to begin."


func _init():
	deck = Deck.new()
	player = Player.new("Steve", 100.0)
	dealer = Dealer.new()


func start_round(bet_amount: float) -> bool:
	# Do not allow another round while one is still active.
	if not round_over:
		status_message = "The current round is still in progress."
		return false

	# Enforce the minimum bet.
	if bet_amount < MINIMUM_BET:
		status_message = "Minimum bet is $%.2f." % MINIMUM_BET
		return false

	# Try to place the player's bet.
	if not player.place_bet(bet_amount):
		status_message = "Invalid bet or insufficient money."
		return false

	# Reset the deck and hands for the new round.
	deck.reset()
	player.reset_hand()
	dealer.reset_hand()

	state = RoundState.PLAYER_TURN
	result = RoundResult.NONE
	round_over = false
	status_message = "Player turn."

	# Deal in normal Blackjack order:
	# player, dealer, player, dealer.
	if not _deal_to_player():
		_cancel_round("Unable to deal a card to the player.")
		return false

	if not _deal_to_dealer():
		_cancel_round("Unable to deal a card to the dealer.")
		return false

	if not _deal_to_player():
		_cancel_round("Unable to deal a card to the player.")
		return false

	if not _deal_to_dealer():
		_cancel_round("Unable to deal a card to the dealer.")
		return false

	# Check for starting Blackjacks.
	_check_starting_blackjacks()

	return true


func player_hit() -> bool:
	# The player can only hit during their turn.
	if round_over or state != RoundState.PLAYER_TURN:
		return false

	# A standing player cannot hit.
	if player.is_standing:
		return false

	# Give the player another card.
	if not _deal_to_player():
		status_message = "Unable to draw a card."
		return false

	# Bust means the round immediately ends.
	if player.hand.is_bust():
		_finish_round(RoundResult.PLAYER_BUST)
		return true

	# If the player reaches exactly 21,
	# automatically move on to the dealer.
	if player.hand.has_21():
		player_stand()
		return true

	status_message = "Player turn. Hit or stand."

	return true


func player_stand() -> bool:
	# The player can only stand during their turn.
	if round_over or state != RoundState.PLAYER_TURN:
		return false

	# Prevent standing more than once.
	if player.is_standing:
		return false

	# This comes from the teammate Player implementation.
	player.is_standing = true

	state = RoundState.DEALER_TURN
	status_message = "Dealer turn."

	dealer_turn()

	# After the dealer finishes drawing,
	# determine who won.
	if not round_over:
		_resolve_round()

	return true


func dealer_turn() -> void:
	if round_over or state != RoundState.DEALER_TURN:
		return

	# Dealer hits below 17 and stands on 17 or higher.
	while dealer.should_hit():
		if not _deal_to_dealer():
			status_message = "Unable to draw a card for the dealer."
			return

		if dealer.hand.is_bust():
			break


func is_player_turn() -> bool:
	return (
		not round_over
		and state == RoundState.PLAYER_TURN
		and not player.is_standing
	)


func is_dealer_turn() -> bool:
	return (
		not round_over
		and state == RoundState.DEALER_TURN
	)


func can_start_round() -> bool:
	return (
		round_over
		and player.money >= MINIMUM_BET
	)


func get_result_text() -> String:
	match result:
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
	var player_blackjack := player.hand.is_blackjack()
	var dealer_blackjack := dealer.hand.is_blackjack()

	if player_blackjack and dealer_blackjack:
		_finish_round(RoundResult.PUSH)

	elif player_blackjack:
		_finish_round(RoundResult.PLAYER_BLACKJACK)

	elif dealer_blackjack:
		_finish_round(RoundResult.DEALER_BLACKJACK)

	else:
		status_message = "Player turn. Hit or stand."


func _resolve_round() -> void:
	# Player bust is always a loss.
	if player.hand.is_bust():
		_finish_round(RoundResult.PLAYER_BUST)
		return

	# Dealer bust means the player wins.
	if dealer.hand.is_bust():
		_finish_round(RoundResult.DEALER_BUST)
		return

	var player_total := player.hand.get_total()
	var dealer_total := dealer.hand.get_total()

	if player_total > dealer_total:
		_finish_round(RoundResult.PLAYER_WIN)

	elif dealer_total > player_total:
		_finish_round(RoundResult.DEALER_WIN)

	else:
		_finish_round(RoundResult.PUSH)


func _finish_round(round_result: int) -> void:
	result = round_result

	match result:
		RoundResult.PLAYER_BLACKJACK:
			player.win_blackjack()

		RoundResult.PLAYER_WIN, RoundResult.DEALER_BUST:
			player.win()

		RoundResult.PUSH:
			player.push()

		RoundResult.DEALER_BLACKJACK, \
		RoundResult.DEALER_WIN, \
		RoundResult.PLAYER_BUST:
			player.lose()

	state = RoundState.ROUND_OVER
	round_over = true
	status_message = get_result_text()


func _cancel_round(message: String) -> void:
	# This should only happen if something prevents the
	# opening deal from completing.
	#
	# Return the player's bet so they do not lose money
	# because of an internal game error.
	player.push()

	state = RoundState.ROUND_OVER
	result = RoundResult.NONE
	round_over = true
	status_message = message
