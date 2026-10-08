## Owns the dealer hand and its fixed hit/stand policy.
## The dealer hits below 17 even when already beating the player, and stands on soft 17.
class_name Dealer
extends Resource


var hand: Hand


## Create an empty dealer hand independent of every player hand.
func _init():
	hand = Hand.new()


## Clear the previous round before the opening deal.
func reset_hand() -> void:
	hand.clear_hand()


## Require another card on 16 or below, independent of the player total.
func should_hit() -> bool:
	# Basic dealer rule for this iteration:
	# hit on 16 or lower and stand on every 17 or higher.
	return hand.get_total() < 17


## Stand on every 17 or higher, including a soft total with an Ace valued at 11.
func should_stand() -> bool:
	return hand.get_total() >= 17
