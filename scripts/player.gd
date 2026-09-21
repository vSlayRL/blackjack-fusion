class_name Player
extends RefCounted


var player_name: String
var money: float
var bet: float = 0.0
var hand: Hand = Hand.new()
var is_standing: bool = false


func _init(
	p_name: String = "Player",
	starting_money: float = 100.0
) -> void:
	player_name = p_name
	money = starting_money


# Returns false if the bet is invalid,
# so the game controller can reject it.
func place_bet(amount: float) -> bool:
	if amount <= 0.0:
		return false
	
	if amount > money:
		return false
	
	# Prevent multiple active bets.
	if bet > 0.0:
		return false
	
	bet = amount
	money -= amount
	
	return true


# Payouts.
# The bet was already deducted in place_bet().

func win() -> void:
	money += bet * 2.0
	bet = 0.0


func win_blackjack() -> void:
	# 3:2 Blackjack payout.
	# Since the original bet was already removed,
	# the player receives the bet back + 1.5x winnings.
	money += bet * 2.5
	bet = 0.0


func push() -> void:
	# Return the original bet.
	money += bet
	bet = 0.0


func lose() -> void:
	# Money was already removed when the bet was placed.
	bet = 0.0


func reset_for_round() -> void:
	bet = 0.0
	is_standing = false
	hand.clear_hand()


func reset_hand() -> void:
	is_standing = false
	hand.clear_hand()


# Compatibility functions for our current BlackjackGame.

func win_bet() -> void:
	win()


func push_bet() -> void:
	push()


func lose_bet() -> void:
	lose()


func can_bet(amount: float) -> bool:
	return amount > 0.0 and amount <= money and bet <= 0.0