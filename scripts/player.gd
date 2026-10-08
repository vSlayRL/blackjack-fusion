## Owns the shared bankroll and the ordered list of player hands.
## Its hand/bet/standing properties refer to the active hand, so settlement can reuse one payout API.
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


## Create a player bankroll and one empty hand ready to accept a wager.
func _init(
	p_name: String = "Player",
	starting_money: float = 100.0
) -> void:
	player_name = p_name
	money = starting_money
	hands.append(PlayerHand.new())


# Returns false if the bet is invalid,
# so the game controller can reject it.
## Validate the opening wager, reserve it from the bankroll, and reject overlapping bets.
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

## Return the reserved bet plus an equal profit: a $10 stake returns $20 total.
func win() -> void:
	money += bet * 2.0
	bet = 0.0


## Return the reserved bet plus 3:2 profit: a $10 stake returns $25 total.
func win_blackjack() -> void:
	# 3:2 Blackjack payout.
	# Since the original bet was already removed,
	# the player receives the bet back + 1.5x winnings.
	money += bet * 2.5
	bet = 0.0


## Refund the active bet with no profit; its retained wager remains available for reporting.
func push() -> void:
	# Return the original bet.
	money += bet
	bet = 0.0


## Clear the active bet; its money was already removed when the wager was placed.
func lose() -> void:
	# Money was already removed when the bet was placed.
	bet = 0.0


## Credit a rule-supplied total return, including principal, then clear the active bet.
func settle_return(total_return: float) -> void:
	# A special rule supplies the complete return, including the original bet.
	money += total_return
	bet = 0.0


## Refund all outstanding bets and replace split hands with one empty hand.
func reset_for_round() -> void:
	# Return any outstanding wagers before clearing their state.
	money += total_bet()
	hands = [PlayerHand.new()]
	active_hand_index = 0


## Carry the accepted opening bet into a fresh hand, clearing prior results and history.
func reset_hand() -> void:
	var wager := total_bet()
	hands = [PlayerHand.new(wager)]
	active_hand_index = 0


## Sum outstanding bets across all hands, including doubled and split stakes.
func total_bet() -> float:
	var total: float = 0.0
	for played_hand in hands:
		total += played_hand.bet
	return total


## Reserve an additional affordable amount for the active hand, as used by Double.
func add_to_bet(amount: float) -> bool:
	if not is_finite(amount) or amount <= 0.0 or amount > money:
		return false
	money -= amount
	bet += amount
	return true


# Compatibility functions for our current BlackjackGame.

## Compatibility alias for the ordinary-win payout.
func win_bet() -> void:
	win()


## Compatibility alias for returning a pushed bet.
func push_bet() -> void:
	push()


## Compatibility alias for settling a lost bet.
func lose_bet() -> void:
	lose()


## Check wager validity and affordability without reserving any money.
func can_bet(amount: float) -> bool:
	return is_finite(amount) and amount > 0.0 and amount <= money and total_bet() <= 0.0
