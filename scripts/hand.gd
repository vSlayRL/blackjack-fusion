## Stores cards and computes their best Blackjack total.
## This class recognizes two-card 21; PlayerHand decides whether its history allows a natural payout.
class_name Hand
extends Resource


var cards: Array[Card] = []


## Append a dealt card; safely ignore an unsuccessful draw represented by null.
func add_card(card: Card) -> void:
	if card == null:
		return

	cards.append(card)


## Remove the cards without changing a player bankroll or wager.
func clear_hand() -> void:
	cards.clear()


## Replace a valid slot in place, preserving order and card count.
func replace_card(index: int, replacement: Card) -> bool:
	if index < 0 or index >= cards.size() or replacement == null:
		return false
	cards[index] = replacement
	return true


## Count Aces as 11, then lower them to 1 one at a time while the total exceeds 21.
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


## Check the Ace-adjusted total, also used for exact Double Target matches.
func is_bust() -> bool:
	return get_total() > 21


## Recognize two-card 21; split/reroll/rescue restrictions are checked separately.
func is_blackjack() -> bool:
	return cards.size() == 2 and get_total() == 21


## Recognize any 21, including multi-card hands that earn ordinary winnings.
func has_21() -> bool:
	return get_total() == 21


## Expose hand size for two-card actions such as Double and Split.
func card_count() -> int:
	return cards.size()
