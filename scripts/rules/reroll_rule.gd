class_name RerollRule
extends SpecialRule

var _used_players: Dictionary = {}


func _init() -> void:
	super(&"reroll", "Reroll", "Once per player per round, replace one card in the active hand. Split hands share this use. A replacement can bust; a rerolled 21 is a normal 21.", "Replace one active-hand card. Once per round, shared across split hands.")


func reset_round() -> void:
	_used_players.clear()


func has_used(player: Player) -> bool:
	return _used_players.has(player.get_instance_id())


func can_use(player: Player) -> bool:
	return active and not has_used(player)


func apply(player: Player, deck: Deck, card_index: int) -> bool:
	if not can_use(player):
		return false
	if card_index < 0 or card_index >= player.hand.card_count():
		return false
	if player.is_standing or player.hands[player.active_hand_index].split_aces:
		return false
	var replacement := deck.deal_card()
	if replacement == null:
		return false
	# The old card is discarded, not returned to the deck this round.
	player.hand.replace_card(card_index, replacement)
	player.hands[player.active_hand_index].has_been_rerolled = true
	_used_players[player.get_instance_id()] = true
	return true
