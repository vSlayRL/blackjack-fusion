class_name ClassicTableHand
extends BlackjackGame
## Reuse Solo actions and payouts; the table chooses when the shared dealer plays.


func _advance_hand() -> void:
	_pending_bust_index = -1
	_pending_bust_action = &""
	player.is_standing = true
	for index in range(player.active_hand_index + 1, player.hands.size()):
		if not player.hands[index].is_standing:
			player.active_hand_index = index
			return
	# Do not resolve a player's hands while another player is still taking a turn.


## Opening choices use Solo qualification, but settlement waits for every player.
func _check_starting_blackjacks() -> void:
	if player.hands[0].is_natural_blackjack():
		player.is_standing = true
	else:
		_update_player_status()


func _resolve_round() -> void:
	if round_over:
		return
	if dealer.hand.is_blackjack():
		for played_hand in player.hands:
			played_hand.result = RoundResult.PUSH if played_hand.is_natural_blackjack() else RoundResult.DEALER_BLACKJACK
		_complete_round()
	elif player.hands[0].is_natural_blackjack():
		_finish_round(RoundResult.PLAYER_BLACKJACK)
	else:
		super._resolve_round()
