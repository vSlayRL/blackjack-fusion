class_name Dealer
extends Resource


var hand: Hand


func _init():
	hand = Hand.new()


func reset_hand() -> void:
	hand.clear_hand()


func should_hit() -> bool:
	# Basic dealer rule for this iteration:
	# hit on 16 or lower and stand on every 17 or higher.
	return hand.get_total() < 17


func should_stand() -> bool:
	return hand.get_total() >= 17
