## Offers a small return for an exact bust total announced at round start.
## The target is shared across split hands and never changes in response to cards or busts.
class_name DoubleTargetRule
extends SpecialRule

const MIN_TARGET: int = 22
const MAX_TARGET: int = 30
const RETURN_MULTIPLIER: float = 1.25

var target_total: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Describe the payout and initialize a target RNG separate from random rule selection.
func _init() -> void:
	super(&"double_target", "Double Target", "Each active round announces one random target from 22 through 30. A kept bust at exactly that total returns 1.25 times the hand's wager in total: $10 returns $12.50, a $2.50 profit. Second Chance can recover any bust first. Split hands share the target. Other busts lose normally; Lucky 9 does not add a bonus to this payout.", "Random target 22–30: an exact bust returns 1.25× your wager. Second Chance still offers recovery.")
	_rng.randomize()


## Clear the previous target, including when this rule is inactive next round.
func reset_round() -> void:
	target_total = 0


## Select one uniformly random integer from 22 to 30 before the player acts.
func activate() -> void:
	super.activate()
	# One uniform choice per active round, before any player action.
	target_total = _rng.randi_range(MIN_TARGET, MAX_TARGET)


## Check the normal Ace-adjusted bust total against the active announced target.
func matches(hand: Hand) -> bool:
	return active and target_total >= MIN_TARGET and target_total <= MAX_TARGET and hand.is_bust() and hand.get_total() == target_total


## Return 1.25 times the stake, rounded to cents: principal plus a 25% profit.
static func total_return(wager: float) -> float:
	return snappedf(wager * RETURN_MULTIPLIER, 0.01)
