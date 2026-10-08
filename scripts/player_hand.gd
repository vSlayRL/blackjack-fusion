class_name PlayerHand
extends RefCounted

# Each split hand owns its wager and turn state. The bankroll stays on Player.
var hand: Hand = Hand.new()
var wager: float = 0.0
var bet: float = 0.0:
	set(value):
		bet = value
		if value > 0.0:
			wager = value
var is_standing: bool = false
var is_split: bool = false
var split_aces: bool = false
var doubled: bool = false
var has_been_rerolled: bool = false
var has_been_rescued: bool = false
var net_result: float = 0.0
var bonus_payout: float = 0.0
var lucky_nine_qualified: bool = false
var lucky_nine_base_wager: float = 0.0
var lucky_nine_bonus: float = 0.0
var result: int = 0


func _init(wager: float = 0.0) -> void:
	bet = wager


func is_natural_blackjack() -> bool:
	return not is_split and not has_been_rerolled and not has_been_rescued and hand.is_blackjack()
