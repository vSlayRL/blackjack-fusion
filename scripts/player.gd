class_name Player
extends RefCounted


var player_name: String
var money: float
var hands: Array[PlayerHand] = []
var active_hand_index: int = 0

# Preserve the original API: these properties refer to the active hand.
var bet: float:
	get:
		return hands[active_hand_index].bet
	set(value):
		hands[active_hand_index].bet = value

var hand: Hand:
	get:
		return hands[active_hand_index].hand
	set(value):
		hands[active_hand_index].hand = value

var is_standing: bool:
	get:
		return hands[active_hand_index].is_standing
	set(value):
		hands[active_hand_index].is_standing = value


func _init(
	p_name: String = "Player",
	starting_money: float = 100.0
) -> void:
	player_name = p_name
	money = starting_money
	hands.append(PlayerHand.new())


# Returns false if the bet is invalid,
# so the game controller can reject it.
func place_bet(amount: float) -> bool:
	if not is_finite(amount) or amount <= 0.0:
		return false
	
	if amount > money:
		return false
	
	# Prevent multiple active bets.
	if total_bet() > 0.0:
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


func settle_return(total_return: float) -> void:
	# A special rule supplies the complete return, including the original bet.
	money += total_return
	bet = 0.0


func reset_for_round() -> void:
	# Return any outstanding wagers before clearing their state.
	money += total_bet()
	hands = [PlayerHand.new()]
	active_hand_index = 0


func reset_hand() -> void:
	var wager := total_bet()
	hands = [PlayerHand.new(wager)]
	active_hand_index = 0


func total_bet() -> float:
	var total: float = 0.0
	for played_hand in hands:
		total += played_hand.bet
	return total


func add_to_bet(amount: float) -> bool:
	if not is_finite(amount) or amount <= 0.0 or amount > money:
		return false
	money -= amount
	bet += amount
	return true


# Compatibility functions for our current BlackjackGame.

func win_bet() -> void:
	win()


func push_bet() -> void:
	push()


func lose_bet() -> void:
	lose()


func can_bet(amount: float) -> bool:
	return is_finite(amount) and amount > 0.0 and amount <= money and total_bet() <= 0.0
