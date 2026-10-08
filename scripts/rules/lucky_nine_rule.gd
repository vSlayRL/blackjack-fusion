## Locks in a finalized opening total of 9, then adds a bonus only on ordinary wins.
## Mystery Card runs before qualification; later Reroll/Second Chance preserve it, and Split removes it.
class_name LuckyNineRule
extends SpecialRule

const BONUS_RATE: float = 0.5


## Round the 50% opening-wager bonus to cents; doubling never increases this base.
static func bonus_for_wager(opening_wager: float) -> float:
	return snappedf(opening_wager * BONUS_RATE, 0.01)


## Describe opening qualification and bonus restrictions for the settings catalog.
func _init() -> void:
	super(&"lucky_nine", "Lucky 9", "An opening two-card total of 9 earns a bonus of 50% of the opening wager if that hand wins. Mystery Card finalizes the opening before qualification. Doubling does not increase the bonus. Reroll and Second Chance preserve qualification; splitting removes it. No bonus on a loss, bust, push, or refunded round.", "Opening 9: win to earn +50% of the opening wager. Double does not increase the bonus; Split removes it.")


## Qualify the final two-card opening, after any Mystery Card choice, and retain its stake.
func on_opening_dealt(context: Dictionary) -> void:
	var player: Player = context.player
	var opening := player.hands[0]
	opening.lucky_nine_qualified = opening.hand.card_count() == 2 and opening.hand.get_total() == 9
	if opening.lucky_nine_qualified:
		opening.lucky_nine_base_wager = opening.wager


## Remove eligibility from split hands; other later card changes preserve the opening decision.
func on_hand_changed(context: Dictionary) -> void:
	if context.action == &"split":
		var player: Player = context.player
		for played_hand in player.hands:
			if played_hand.is_split:
				played_hand.lucky_nine_qualified = false
				played_hand.lucky_nine_base_wager = 0.0


## Compute this rule contribution only for normal wins or dealer busts.
## Replace the previous contribution rather than add it twice; Double Target wins receive no bonus.
func before_settlement(context: Dictionary) -> void:
	var player: Player = context.player
	for played_hand in player.hands:
		var bonus: float = 0.0
		if played_hand.lucky_nine_qualified and not played_hand.is_split and played_hand.result in [BlackjackGame.RoundResult.PLAYER_WIN, BlackjackGame.RoundResult.DEALER_BUST]:
			bonus = bonus_for_wager(played_hand.lucky_nine_base_wager)
		# Compute the rule's contribution once, even if preparation is repeated.
		played_hand.bonus_payout += bonus - played_hand.lucky_nine_bonus
		played_hand.lucky_nine_bonus = bonus
