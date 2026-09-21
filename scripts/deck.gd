class_name Deck
extends Resource


var cards: Array[Card] = []


func _init():
	reset()


func create_deck() -> void:
	cards.clear()

	for suit in Card.Suit.values():
		for rank in Card.Rank.values():
			cards.append(Card.new(suit, rank))


func shuffle() -> void:
	cards.shuffle()


func deal_card() -> Card:
	if cards.is_empty():
		return null

	return cards.pop_back()


func reset() -> void:
	create_deck()
	shuffle()


func cards_remaining() -> int:
	return cards.size()


func is_empty() -> bool:
	return cards.is_empty()
