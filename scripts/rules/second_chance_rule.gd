class_name SecondChanceRule
extends SpecialRule

var _used_players: Dictionary = {}


func _init() -> void:
	super(&"second_chance", "Second Chance", "Once per player per round, remove the card that caused a bust. Split hands share this use. A rescued Double still ends the hand; its doubled wager stays on the table.", "Remove a bust-causing card. Once per round; a rescued Double still ends the hand.")


func reset_round() -> void:
	_used_players.clear()


func has_used(player: Player) -> bool:
	return _used_players.has(player.get_instance_id())


func can_use(player: Player) -> bool:
	return active and not has_used(player)


func apply(player: Player, card_index: int) -> bool:
	if not can_use(player) or player.is_standing or not player.hand.is_bust():
		return false
	if player.hands[player.active_hand_index].split_aces or card_index < 0 or card_index >= player.hand.card_count():
		return false
	# Remove only the recorded bust-causing card. It stays discarded this round.
	player.hand.cards.remove_at(card_index)
	player.hands[player.active_hand_index].has_been_rescued = true
	_used_players[player.get_instance_id()] = true
	return true
