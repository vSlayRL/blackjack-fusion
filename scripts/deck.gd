## Owns a single 52-card deck and removes cards as they are dealt.
## A new round rebuilds the deck, restoring every card discarded by special rules.
class_name Deck
extends Resource


var cards: Array[Card] = []


## Start with a complete shuffled deck.
func _init():
	reset()


## Build all four suits and thirteen ranks, clearing the previous deck first.
func create_deck() -> void:
	cards.clear()

	for suit in Card.Suit.values():
		for rank in Card.Rank.values():
			cards.append(Card.new(suit, rank))


## Randomize the remaining cards; this does not add any discarded cards back.
func shuffle() -> void:
	cards.shuffle()


## Remove one card from the deck, or return null when no card is available.
func deal_card() -> Card:
	if cards.is_empty():
		return null

	return cards.pop_back()


## Rebuild and shuffle all 52 cards for a fresh round.
func reset() -> void:
	create_deck()
	shuffle()


## Expose the count used to validate drawing, doubling, and splitting.
func cards_remaining() -> int:
	return cards.size()


## Report whether an action requiring a new card can draw anything.
func is_empty() -> bool:
	return cards.is_empty()
