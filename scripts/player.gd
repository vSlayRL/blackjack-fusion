class_name Player
extends RefCounted

var player_name: String
var money: int
var bet: int = 0
var hand: Hand = Hand.new()
var is_standing: bool = false


func _init(p_name: String, starting_money: int = 1000) -> void:
	player_name = p_name
	money = starting_money


#returns false if the bet is invalid, so the game controller can reject it.
func place_bet(amount: int) -> bool:
	if amount <= 0 or amount > money:
		return false
	bet = amount
	money -= amount
	return true

#Payouts. The bet was already deducted in place_bet()

func win() -> void:
	money += bet * 2


func win_blackjack() -> void:
	money += bet + int(bet * 1.5)  #3:2 payout


func push() -> void:
	money += bet  #bet returned


func lose() -> void:
	pass  #bet stays with the house


func reset_for_round() -> void:
	bet = 0
	is_standing = false
	hand.clear()
