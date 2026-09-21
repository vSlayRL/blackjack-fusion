class_name Hand
extends Resource


var cards: Array[Card] = []


func add_card(card: Card) -> void:
	if card == null:
		return

	cards.append(card)


func clear_hand() -> void:
	cards.clear()


func get_total() -> int:
	var total := 0
	var aces := 0

	for card in cards:
		total += card.get_blackjack_value()

		if card.rank == Card.Rank.ACE:
			aces += 1

	# Each Ace starts as 11. Change it to 1 when needed to avoid a bust.
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1

	return total


func is_bust() -> bool:
	return get_total() > 21


func is_blackjack() -> bool:
	return cards.size() == 2 and get_total() == 21


func has_21() -> bool:
	return get_total() == 21


func card_count() -> int:
	return cards.size()
