class_name ClassicTable
extends RefCounted
## Host-only shared deck, betting quorum, turn order and exactly-once settlement.
## Network snapshots contain plain values; the dealer hole card never leaves the host.

const STARTING_MONEY: float = 100.0
var members: Dictionary = {}
var order: Array[int] = []
var phase: String = "betting"
var round_id: int = 0
var revision: int = 0
var turn_id: int = 0
var deck: Deck = Deck.new()
var dealer: Dealer = Dealer.new()
# Preferences can change mid-round; prepare_round freezes one shared selection at deal.
var rules: RuleManager = RuleManager.new()
var round_mode: int = RuleManager.RuleMode.OFF
var settings_revision: int = 0
var session: TableSession = TableSession.new()
var message: String = "The host can open the console to choose rounds and starting money."


## Start Classic with all five rules available when the host enables them.
func _init() -> void:
	var selected: Array[StringName] = []
	for rule in rules.get_catalog():
		selected.append(rule.rule_id)
	rules.configure(RuleManager.RuleMode.OFF, selected)


## Only the host can store next-deal preferences; gameplay revisions stay independent.
func configure(id: int, mode: int, selected: Array[StringName], count: int, expected_settings: int) -> String:
	if id != 1:
		return "Only the host can change table rules."
	if expected_settings != settings_revision:
		return "Settings changed. Reopen the console to use the latest preferences."
	if count < 1 or count > 5 or not rules.configure(mode, selected, count):
		return "Choose a valid mode, rule pool and random count (1–5)."
	settings_revision += 1
	# Ready means consent to the displayed next-round rules. A new setting clears it.
	for member in members.values():
		member.ready = false
	return ""


## Start atomically from setup/results. Never reset global deal IDs or request sequences.
func start_session(id: int, rounds: int, money: float, expected_session: int) -> String:
	if phase == "playing":
		return "Finish the current deal before starting a new session."
	var error := session.start(id, rounds, money, expected_session, members)
	if not error.is_empty():
		return error
	for peer in members.keys():
		var member: Dictionary = members[peer]
		if not member.connected:
			members.erase(peer)
			continue
		member.game = ClassicTableHand.new()
		member.game.player = Player.new(member.name, money)
		member.ready = false
		member.bet = minf(10.0, money)
		member.has_result = false
		member.delta = 0.0
		member.round_seat = member.seat
	order.clear()
	dealer.reset_hand()
	rules.active_rules.clear()
	for rule in rules.get_catalog():
		rule.deactivate()
		rule.reset_round()
	phase = "betting"
	turn_id = 0
	message = "Session started. Sit and ready your bet for round 1 of %d." % rounds
	settings_revision += 1
	revision += 1
	return ""


## A combined console Start is atomic: bad/stale drafts cannot partially change rules or money.
func start_configured_session(id: int, rounds: int, money: float, mode: int, selected: Array[StringName], count: int, expected_session: int, expected_settings: int) -> String:
	var error := session.validate_start(id, rounds, money, expected_session, members)
	if not error.is_empty():
		return error
	if phase == "playing" or expected_settings != settings_revision:
		return "Settings changed. Reopen the console before starting."
	var validation := RuleManager.new()
	if count < 1 or count > 5 or not validation.configure(mode, selected, count):
		return "Choose a valid rule mode, checked pool and random count (1–5)."
	error = start_session(id, rounds, money, expected_session)
	if not error.is_empty():
		return error
	rules.configure(mode, selected, count)
	return ""


func active_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for rule in rules.active_rules:
		ids.append(rule.rule_id)
	return ids


func target_total() -> int:
	var rule := rules.get_rule(&"double_target") as DoubleTargetRule
	return rule.target_total if rule.active else 0


func _opening_pending() -> bool:
	for id in order:
		if members[id].game.is_awaiting_mystery_card():
			return true
	return false


func sync_members(records: Dictionary) -> void:
	for member in members.values():
		member.connected = false
	for id in records:
		var record: Dictionary = records[id]
		if not members.has(id):
			members[id] = {"id": id, "name": record.name, "seat": record.seat, "connected": true,
				"game": ClassicTableHand.new(), "ready": false, "bet": 10.0,
				"has_result": false, "delta": 0.0, "round_seat": record.seat}
			members[id].game.player.money = 0.0
		var member: Dictionary = members[id]
		if member.seat != record.seat:
			member.ready = false
		member.name = record.name
		member.seat = record.seat
		member.connected = true
		member.game.player.player_name = record.name
	for id in members.keys():
		var member: Dictionary = members[id]
		if not member.connected or member.seat < 0:
			member.ready = false
			if phase == "playing" and order.has(id):
				# Leaving never refunds an already dealt wager or stalls the next player.
				# An abandoned opening keeps its card, then auto-stands without a refund.
				if member.game.is_awaiting_mystery_card():
					member.game.player_choose_mystery_card(false)
				for played_hand in member.game.player.hands:
					played_hand.is_standing = true
		if not member.connected and not session.entrants.has(id) and (phase != "playing" or not order.has(id)):
			members.erase(id)
	session.sync_connections(members)
	if phase == "playing":
		_advance_turn()
	else:
		session.check_early_end()
		_maybe_deal()
	revision += 1


func ready_bet(id: int, amount: float, ready: bool, expected_round: int, expected_settings: int = -1) -> String:
	if session.status != "active":
		return "Wait for the host to start a session."
	if not session.entrants.has(id):
		return "You are spectating this session. Join the next one when the host starts it."
	if not members.has(id) or not members[id].connected or members[id].seat < 0:
		return "Sit in a chair before readying a bet."
	if phase == "playing" or expected_round != round_id:
		return "A round has already started. Wait for the next deal."
	if ready and expected_settings >= 0 and expected_settings != settings_revision:
		return "Table rules changed. Review them before readying again."
	var member: Dictionary = members[id]
	if ready and (not is_finite(amount) or amount < 1.0 or amount > member.game.player.money or absf(amount * 100.0 - round(amount * 100.0)) > 0.00001):
		return "Choose an affordable bet of at least $1, in cents."
	member.ready = ready
	if ready:
		member.bet = amount
	_maybe_deal()
	revision += 1
	return ""


func _eligible() -> Array[int]:
	var ids: Array[int] = []
	for member in members.values():
		if session.status == "active" and session.entrants.has(member.id) and member.connected and member.seat >= 0 and member.game.player.money >= 1.0:
			ids.append(member.id)
	ids.sort_custom(func(a: int, b: int): return members[a].seat < members[b].seat)
	return ids


func _maybe_deal() -> void:
	var ids := _eligible()
	if ids.is_empty():
		return
	for id in ids:
		if not members[id].ready:
			return
	_begin_round(ids)


func _begin_round(ids: Array[int]) -> void:
	order = ids
	round_id += 1
	phase = "playing"
	turn_id = 0
	deck.reset()
	dealer.reset_hand()
	rules.prepare_round()
	round_mode = rules.rule_mode
	for member in members.values():
		member.ready = false
		member.has_result = false
		member.delta = 0.0
	for id in order:
		var member: Dictionary = members[id]
		var account: Player = member.game.player
		member.round_seat = member.seat
		account.reset_for_round()
		member.game = ClassicTableHand.new()
		var game: ClassicTableHand = member.game
		game.player = account
		game.deck = deck
		game.dealer = dealer
		# Separate rule instances preserve each player's allowances across their own splits.
		game.configure_rules(RuleManager.RuleMode.ALL_SELECTED, active_ids())
		game.rules.prepare_round()
		(game.rules.get_rule(&"double_target") as DoubleTargetRule).target_total = target_total()
		game._round_start_money = account.money
		account.place_bet(member.bet)
		game.round_over = false
		game.state = BlackjackGame.RoundState.PLAYER_TURN
		game._notify_rules(&"round_started")
	for _pass_index in range(2):
		for id in order:
			if not members[id].game._deal_to_player():
				_cancel_deal()
				return
		var card := deck.deal_card()
		if card == null:
			_cancel_deal()
			return
		dealer.hand.add_card(card)
	for id in order:
		var game: ClassicTableHand = members[id].game
		if rules.is_rule_active(&"mystery_card"):
			game.state = BlackjackGame.RoundState.MYSTERY_CARD_CHOICE
		else:
			game._finalize_opening()
	_advance_turn()


func act(id: int, action: String, expected_revision: int, card_index: int = -1) -> String:
	if phase != "playing" or id != turn_id or expected_revision != revision:
		return "Wait for your current turn before acting."
	var game: ClassicTableHand = members[id].game
	# All opening decisions finish before ordinary turns, even against a dealer natural.
	if _opening_pending() and not game.is_awaiting_mystery_card():
		return "Wait until every Mystery Card choice is complete."
	var accepted := false
	match action:
		"hit": accepted = game.player_hit()
		"stand": accepted = game.player_stand()
		"double": accepted = game.player_double()
		"split": accepted = game.player_split()
		"reroll": accepted = game.player_reroll(card_index)
		"second_chance": accepted = game.player_second_chance()
		"keep_mystery": accepted = game.player_choose_mystery_card(false)
		"replace_mystery": accepted = game.player_choose_mystery_card(true)
	if not accepted:
		return "That action is unavailable for this hand."
	_advance_turn()
	revision += 1
	return ""


func _advance_turn() -> void:
	for id in order:
		if members[id].game.is_awaiting_mystery_card():
			turn_id = id
			message = "%s: keep or replace your Mystery Card. Other players choose next." % members[id].name
			return
	if dealer.hand.is_blackjack():
		_finish_round()
		return
	for id in order:
		var game: ClassicTableHand = members[id].game
		if not game.player.is_standing:
			turn_id = id
			message = "%s’s turn · Hand %d of %d" % [members[id].name, game.player.active_hand_index + 1, game.player.hands.size()]
			if game.is_awaiting_second_chance():
				message = "%s · %s" % [members[id].name, game.status_message]
			return
	_finish_round()


func _cancel_deal() -> void:
	for id in order:
		members[id].game._cancel_round("Unable to complete opening. Bets returned.")
	_complete("Unable to complete opening. Bets returned.", false)


func _finish_round() -> void:
	if phase != "playing":
		return
	# Naturals need no dealer draws; all other surviving hands share one dealer run.
	var needs_dealer := false
	for id in order:
		for played_hand in members[id].game.player.hands:
			if not played_hand.hand.is_bust() and not played_hand.is_natural_blackjack():
				needs_dealer = true
	if needs_dealer and not dealer.hand.is_blackjack():
		while dealer.should_hit():
			var card := deck.deal_card()
			if card == null:
				for id in order:
					members[id].game._cancel_round("Deck exhausted. Bets returned.")
				_complete("Deck exhausted. Bets returned.", false)
				return
			dealer.hand.add_card(card)
	for id in order:
		members[id].game._resolve_round()
	_complete("Round %d complete. Ready your next bet when everyone is ready." % (session.completed + 1))


func _complete(text: String, counted: bool = true) -> void:
	if phase != "playing":
		return
	phase = "settled"
	turn_id = 0
	message = text
	for id in order:
		var member: Dictionary = members[id]
		member.has_result = true
		member.delta = member.game.last_round_delta
	session.record_settlement(round_id, order, members, counted)
	if session.status == "finished":
		message = "Session complete. Open the console for the final standings."


## Cards use compact identities 0..51. A null hole card has no identity or total.
static func encode_card(card: Card) -> int:
	return int(card.suit) * 13 + int(card.rank) - 2


static func decode_card(code: int) -> Card:
	return Card.new(int(code / 13.0) as Card.Suit, (code % 13 + 2) as Card.Rank)


func snapshot() -> Dictionary:
	var people: Array = []
	for member in members.values():
		var game: ClassicTableHand = member.game
		var hands: Array = []
		if order.has(member.id):
			for index in range(game.player.hands.size()):
				var played_hand := game.player.hands[index]
				var cards: Array = []
				for card_index in range(played_hand.hand.cards.size()):
					if game.is_player_card_hidden(index, card_index):
						cards.append(null)
					else:
						cards.append(encode_card(played_hand.hand.cards[card_index]))
				var lucky: bool = game.rules.is_rule_active(&"lucky_nine") and played_hand.lucky_nine_qualified and not played_hand.is_split and not game.is_awaiting_mystery_card()
				hands.append({"lucky_nine_qualified": lucky, "lucky_nine_bonus": LuckyNineRule.bonus_for_wager(played_hand.lucky_nine_base_wager) if lucky else 0.0,
					"cards": cards, "total": -1 if game.is_awaiting_mystery_card() else played_hand.hand.get_total(), "wager": played_hand.wager,
					"standing": played_hand.is_standing, "active": phase == "playing" and turn_id == member.id and index == game.player.active_hand_index,
					"result": game.get_hand_result_text(played_hand.result) if phase == "settled" else "", "net": played_hand.net_result})
		var can_act: bool = phase == "playing" and turn_id == member.id
		people.append({"id": member.id, "name": member.name, "seat": member.seat, "round_seat": member.round_seat, "connected": member.connected,
			"balance": game.player.money, "ready": member.ready, "bet": member.bet, "hands": hands,
			"has_result": member.has_result, "delta": member.delta, "can_act": can_act,
			"enrolled": session.entrants.has(member.id),
			"can_bet": session.status == "active" and session.entrants.has(member.id) and member.connected and member.seat >= 0 and game.player.money >= 1.0,
			"can_hit": can_act and game.is_player_turn(),
			"can_stand": can_act and (game.is_player_turn() or game.is_awaiting_second_chance()),
			"can_double": can_act and game.can_double(), "can_split": can_act and game.can_split(),
			"can_reroll": can_act and game.can_reroll(), "can_second_chance": can_act and game.can_second_chance(),
			"mystery_pending": game.is_awaiting_mystery_card(),
			"can_keep_mystery": can_act and game.is_awaiting_mystery_card(),
			"can_replace_mystery": can_act and game.can_replace_mystery_card(),
			"bust_pending": can_act and game.is_awaiting_second_chance(),
			"target_match": can_act and game.is_double_target_match(game.player.hands[game.player.active_hand_index]),
			"reroll_used": (game.rules.get_rule(&"reroll") as RerollRule).has_used(game.player),
			"second_chance_used": (game.rules.get_rule(&"second_chance") as SecondChanceRule).has_used(game.player),
			"rule_message": game.last_rule_message})
	var dealer_cards: Array = []
	for index in range(dealer.hand.cards.size()):
		if phase == "playing" and index == 1:
			dealer_cards.append(null)
		else:
			dealer_cards.append(encode_card(dealer.hand.cards[index]))
	return {"round": round_id, "revision": revision, "phase": phase, "turn": turn_id, "message": message,
		"session": session.snapshot(phase == "playing"), "configuration": rules.get_configuration(), "settings_revision": settings_revision,
		"active_rules": active_ids(), "round_mode": round_mode, "target": target_total(),
		"players": people, "dealer": dealer_cards, "dealer_total": dealer.hand.get_total() if phase == "settled" else -1}
