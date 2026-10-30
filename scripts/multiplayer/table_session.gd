class_name TableSession
extends RefCounted
## Finite competition ledger. The table engine owns hands and settles them before recording scores.

const MAX_ROUNDS: int = 100
const MAX_STARTING_MONEY: float = 100000.0

var id: int = 0
var status: String = "setup"
var round_limit: int = 10
var starting_money: float = 100.0
var completed: int = 0
var reason: String = ""
var entrants: Dictionary = {}
var _last_settled_deal: int = -1


## Console drafts validate all settings before the start commits any shared state.
func validate_start(host_id: int, rounds: int, money: float, expected_id: int, members: Dictionary) -> String:
	if host_id != 1:
		return "Only the host can start a session."
	if expected_id != id:
		return "The session changed. Reopen the console to review the latest settings."
	if status == "active":
		return "Starting money and the round limit stay locked until this session ends."
	if rounds < 1 or rounds > MAX_ROUNDS or not is_finite(money) or money < 1.0 or money > MAX_STARTING_MONEY or absf(money * 100.0 - round(money * 100.0)) > 0.00001:
		return "Choose 1–100 rounds and $1–$100,000 starting money, in cents."
	for member in members.values():
		if member.connected:
			return ""
	return "Connect players before starting a session."


func start(host_id: int, rounds: int, money: float, expected_id: int, members: Dictionary) -> String:
	var error := validate_start(host_id, rounds, money, expected_id, members)
	if not error.is_empty():
		return error
	var connected: Array[int] = []
	for member in members.values():
		if member.connected:
			connected.append(member.id)
	id += 1
	status = "active"
	round_limit = rounds
	starting_money = money
	completed = 0
	reason = ""
	_last_settled_deal = -1
	entrants.clear()
	for peer in connected:
		entrants[peer] = {"id": peer, "name": members[peer].name, "connected": true, "starting_balance": money, "balance": money, "rounds": 0}
	return ""


## Preserve departed entrants and their last settled money; reconnects use a new peer ID.
func sync_connections(members: Dictionary) -> void:
	for peer in entrants:
		entrants[peer].connected = members.has(peer) and members[peer].connected
		if entrants[peer].connected:
			entrants[peer].name = members[peer].name


## One accepted, fully settled deal counts once, including every split and opening natural.
## Refunded interrupted deals update bankrolls but never consume a round.
func record_settlement(deal: int, played: Array[int], members: Dictionary, counted: bool) -> void:
	if status != "active" or deal <= _last_settled_deal:
		return
	_last_settled_deal = deal
	for peer in entrants:
		if members.has(peer):
			entrants[peer].balance = members[peer].game.player.money
		if counted and played.has(peer):
			entrants[peer].rounds += 1
	if counted:
		completed += 1
	if completed >= round_limit:
		status = "finished"
		reason = "All %d rounds completed." % round_limit
	check_early_end()


## Walking is allowed between deals; only absence or bankruptcy removes betting eligibility.
func check_early_end() -> void:
	if status != "active":
		return
	for entry in entrants.values():
		if entry.connected and entry.balance >= 1.0:
			return
	status = "finished"
	reason = "No connected participant can afford the $1 minimum bet."


## Rank the same cent-precision balances displayed to players; ties share a place (1, 1, 3).
func standings() -> Array:
	var rows: Array = entrants.values().duplicate(true)
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		var left := roundi(float(a.balance) * 100.0)
		var right := roundi(float(b.balance) * 100.0)
		return left > right if left != right else int(a.id) < int(b.id))
	var previous: int = -1
	var place := 0
	for index in range(rows.size()):
		var cents := roundi(float(rows[index].balance) * 100.0)
		if index == 0 or cents != previous:
			place = index + 1
		previous = cents
		rows[index].place = place
		rows[index].net = float(rows[index].balance) - float(rows[index].starting_balance)
	return rows


func snapshot(playing: bool) -> Dictionary:
	return {"id": id, "status": status, "round_limit": round_limit, "starting_money": starting_money,
		"completed": completed, "current_round": mini(completed + (1 if playing else 0), round_limit),
		"reason": reason, "standings": standings()}
