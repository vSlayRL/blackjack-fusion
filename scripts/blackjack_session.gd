class_name BlackjackSession
extends RefCounted
## Owns finite 3D sessions; the Blackjack engine still owns cards, wagers, and payouts.

enum Phase { SETUP, PLAYING, FINISHED }

const MAX_ROUNDS: int = 100
const MAX_STARTING_MONEY: float = 100000.0

var phase: Phase = Phase.SETUP
var round_limit: int = 10
var starting_money: float = 100.0
var completed_rounds: int = 0
var finish_reason: String = ""
var game: BlackjackGame = BlackjackGame.new()
var _round_pending: bool = false


## Commit all settings together before creating the new bankroll; reject changes during play.
func start_session(rounds: int, money: float, mode: int, selected: Array[StringName], random_count: int) -> bool:
	if phase != Phase.SETUP or rounds < 1 or rounds > MAX_ROUNDS or not is_finite(money) or money < BlackjackGame.MINIMUM_BET or money > MAX_STARTING_MONEY:
		return false
	var next_game := BlackjackGame.new()
	if mode == RuleManager.RuleMode.RANDOM_SELECTED and selected.is_empty():
		return false
	if not next_game.configure_rules(mode, selected, random_count):
		return false
	round_limit = rounds
	starting_money = money
	completed_rounds = 0
	finish_reason = ""
	_round_pending = false
	game = next_game
	game.player.money = starting_money
	phase = Phase.PLAYING
	return true


## Only an accepted deal enters the session counter; invalid bets preserve its progress.
func begin_round(wager: float) -> bool:
	observe_round()
	if phase != Phase.PLAYING or not game.start_round(wager):
		return false
	_round_pending = true
	observe_round()
	return true


## Observe settlement once, including immediate naturals and all completed split hands.
## Refunded/cancelled deals have no outcome and do not consume the configured round limit.
func observe_round() -> void:
	if phase != Phase.PLAYING or not _round_pending or not game.round_over:
		return
	_round_pending = false
	if game.result != BlackjackGame.RoundResult.NONE:
		completed_rounds += 1
	if completed_rounds >= round_limit:
		finish_reason = "All %d rounds completed." % round_limit
		phase = Phase.FINISHED
	elif game.player.money < BlackjackGame.MINIMUM_BET:
		finish_reason = "Not enough money remains for the $1 minimum bet."
		phase = Phase.FINISHED


## Return to setup only after the session ends, retaining the previous settings as defaults.
func new_session() -> bool:
	if phase != Phase.FINISHED:
		return false
	var settings := game.rules.get_configuration()
	game = BlackjackGame.new()
	game.configure_rules(settings.mode, settings.selected, settings.random_count)
	game.player.money = starting_money
	completed_rounds = 0
	finish_reason = ""
	_round_pending = false
	phase = Phase.SETUP
	return true


## Describe the currently played deal, or the next deal between rounds.
func progress_text() -> String:
	if phase == Phase.SETUP:
		return "SESSION — Configure at the console"
	if phase == Phase.FINISHED:
		return "SESSION FINISHED — %d of %d rounds" % [completed_rounds, round_limit]
	return "ROUND %d OF %d" % [mini(completed_rounds + 1, round_limit), round_limit]


## Session net compares settled money with the configured starting bankroll.
func net_result() -> float:
	return game.player.money - starting_money
