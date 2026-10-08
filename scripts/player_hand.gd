## Tracks the wager, action history, and result of one player hand.
## Split hands share the Player bankroll but keep separate stakes, bonuses, and turn state.
class_name PlayerHand
extends RefCounted

# Each split hand owns its wager and turn state. The bankroll stays on Player.
var hand: Hand = Hand.new()
# Wager retains the full stake after bet is cleared, so returned money can be
# compared with the amount risked when reporting the hand's net profit/loss.
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
# These history flags affect natural eligibility even when cards later total 21.
var has_been_rerolled: bool = false
var has_been_rescued: bool = false
var net_result: float = 0.0
# Bonuses are prepared by rules, then credited once by BlackjackGame settlement.
var bonus_payout: float = 0.0
var lucky_nine_qualified: bool = false
var lucky_nine_base_wager: float = 0.0
var lucky_nine_bonus: float = 0.0
var result: int = 0


## Initialize the outstanding bet and retained wager used for final net-result reporting.
func _init(initial_wager: float = 0.0) -> void:
	bet = initial_wager


## Allow 3:2 only for an unsplit opening without Reroll or Second Chance history.
## Mystery Card finalizes that opening, so its replacement does not set either history flag.
func is_natural_blackjack() -> bool:
	return not is_split and not has_been_rerolled and not has_been_rescued and hand.is_blackjack()
