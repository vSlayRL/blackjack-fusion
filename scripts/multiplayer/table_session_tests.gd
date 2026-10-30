extends "res://scripts/multiplayer/special_table_tests.gd"
## Complete finite-session stories with known draws, including shared settlement and refunds.


func _ready() -> void:
	_combined_start_is_atomic()
	_lucky_snapshot_markers()
	_setup_and_locking()
	_split_final_and_restart()
	_standings_and_ties()
	_refunds_and_naturals()
	_membership_and_bankruptcy()
	if not failed:
		print("ALL MULTIPLAYER SESSION ENGINE TESTS PASSED")
	get_tree().quit(1 if failed else 0)


func _combined_start_is_atomic() -> void:
	var table := _fresh([10, 10, 10, 7, 8, 7])
	var preferences := table.rules.get_configuration()
	for attempt in [[2, 75, 1, [&"unknown"], 1, 0, 0], [2, 0, 1, [&"lucky_nine"], 1, 0, 0], [2, 75, 1, [&"lucky_nine"], 1, 0, 99]]:
		var selected: Array[StringName] = []
		selected.assign(attempt[3])
		_check(not table.start_configured_session(1, attempt[0], attempt[1], attempt[2], selected, attempt[4], attempt[5], attempt[6]).is_empty(), "Invalid or stale combined draft rejected.")
		_check(table.session.id == 0 and table.members[1].game.player.money == 0 and table.rules.get_configuration() == preferences, "Rejected combined draft changes neither rules nor bankroll.")
	_check(table.start_configured_session(1, 2, 75, RuleManager.RuleMode.ALL_SELECTED, [&"lucky_nine"], 1, 0, 0).is_empty(), "Reviewed combined draft accepted.")
	_check(table.members[1].game.player.money == 75 and table.rules.selected_rule_ids == [&"lucky_nine"] and table.rules.rule_mode == RuleManager.RuleMode.ALL_SELECTED, "One start commits money, length and rule preferences together.")
	print("PASS: Unified console Start validates atomically without partial rule/money changes.")


func _lucky_snapshot_markers() -> void:
	var table := _fresh([4, 10, 10, 5, 8, 7, 4, 6, 7])
	_start(table, 2)
	_enable(table, [&"lucky_nine", &"reroll"])
	_deal(table)
	_check(table.snapshot().players[0].hands[0].lucky_nine_qualified and table.snapshot().players[0].hands[0].lucky_nine_bonus == 5, "Final opening 9 exposes its qualification and original-wager bonus before any win.")
	_play(table, 1, "reroll", 1)
	_check(table.snapshot().players[0].hands[0].lucky_nine_qualified, "Reroll preserves the marker.")
	_play(table, 1, "split")
	for hand in table.snapshot().players[0].hands:
		_check(not hand.lucky_nine_qualified and hand.lucky_nine_bonus == 0, "Splitting removes qualification from all resulting hand displays.")
	_play(table, 1, "stand")
	_play(table, 1, "stand")
	_play(table, 2, "stand")
	table = _fresh([4, 10, 10, 5, 8, 7, 10, 10])
	_start(table, 2)
	_enable(table, [&"lucky_nine", &"second_chance"])
	_deal(table)
	_play(table, 1, "hit")
	_play(table, 1, "hit")
	_play(table, 1, "second_chance")
	_check(table.snapshot().players[0].hands[0].lucky_nine_qualified and table.snapshot().players[0].hands[0].lucky_nine_bonus == 5, "Second Chance preserves the original marker and bonus.")
	_play(table, 1, "stand")
	_play(table, 2, "stand")
	_seed_cards(table, [10, 10, 10, 7, 8, 7])
	_deal(table)
	_check(not table.snapshot().players[0].hands[0].lucky_nine_qualified, "A new nonqualifying opening clears the previous marker.")
	print("PASS: Early Lucky 9 marker, original bonus, reroll/recovery persistence, split removal and next-round reset.")


func _fresh(ranks: Array, four: bool = false) -> ClassicTable:
	var table := ClassicTable.new()
	var records := _records()
	if four:
		records[3] = {"name": "Third", "seat": 2}
		records[4] = {"name": "Fourth", "seat": 3}
	table.sync_members(records)
	_seed_cards(table, ranks)
	return table


func _seed_cards(table: ClassicTable, ranks: Array) -> void:
	var fixed := FixedDeck.new()
	for index in range(ranks.size()):
		fixed.draws.append(Card.new((index % 4) as Card.Suit, int(ranks[index]) as Card.Rank))
	table.deck = fixed


func _start(table: ClassicTable, rounds: int, money: float = 100.0) -> void:
	_check(table.start_session(1, rounds, money, table.session.id).is_empty(), "Host starts reviewed session.")


func _setup_and_locking() -> void:
	var table := _fresh([10, 10, 10, 7, 8, 7])
	_check(not table.ready_bet(1, 10, true, 0).is_empty() and table.session.completed == 0, "No betting before host setup.")
	for money in [NAN, INF, 0.0, -1.0, 100001.0, 1.001]:
		_check(not table.start_session(1, 10, money, 0).is_empty(), "Invalid starting balance rejected.")
	for rounds in [-1, 0, 101]:
		_check(not table.start_session(1, rounds, 100, 0).is_empty(), "Invalid round limit rejected.")
	_check(not table.start_session(2, 10, 100, 0).is_empty(), "Guest cannot start.")
	_check(not table.start_session(1, 10, 100, 99).is_empty(), "Stale setup rejected.")
	_check(table.session.id == 0 and table.members[1].game.player.money == 0, "Rejected setup never changes a bankroll.")
	_start(table, 2, 250)
	_check(table.session.entrants.size() == 2 and table.members[2].game.player.money == 250, "Every connected entrant starts equally.")
	_check(not table.start_session(1, 1, 1000, 1).is_empty(), "Starting money and length lock even between deals.")
	_deal(table)
	var round_revision := table.revision
	_enable(table, [&"reroll"])
	_check(table.active_ids().is_empty() and table.revision == round_revision, "Rule changes remain staged for next deal during finite sessions.")
	_play(table, 1, "stand")
	_check(table.session.completed == 0 and table.snapshot().session.current_round == 1, "Count waits for shared settlement.")
	_play(table, 2, "stand")
	_check(table.session.completed == 1 and table.session.status == "active", "One complete deal counts once.")
	table._finish_round()
	table._complete("Repeat")
	_check(table.session.completed == 1, "Repeated settlement observations cannot count again.")
	_deal(table)
	_check(table.active_ids() == [&"reroll"] and table.snapshot().session.current_round == 2, "Round 2 uses saved rule changes.")
	_play(table, 1, "stand")
	_play(table, 2, "stand")
	_check(table.session.status == "finished" and table.session.completed == 2, "Session stops at chosen length.")
	_check(not table.ready_bet(1, 10, true, table.round_id).is_empty(), "No further bets after final payouts.")
	print("PASS: Setup validation, equal bankrolls, locked money/length, staged rules and exactly-once finite counting.")


func _split_final_and_restart() -> void:
	var table := _fresh([8, 10, 10, 8, 8, 7, 3, 10, 10])
	_start(table, 1)
	_deal(table)
	_play(table, 1, "split")
	_play(table, 1, "double")
	_play(table, 1, "stand")
	_check(table.session.completed == 0, "Split and doubled hands still await shared dealer.")
	_play(table, 2, "stand")
	_check(table.session.completed == 1 and table.session.status == "finished", "All split hands count as one round.")
	var places: Array = table.snapshot().session.standings
	_check(places[0].id == 1 and places[0].balance == 130 and places[0].net == 30, "Results use money after all split/double payouts.")
	var old_revision := table.revision
	var old_settings := table.settings_revision
	var old_deal := table.round_id
	_start(table, 2, 25)
	_check(table.session.id == 2 and table.round_id == old_deal and table.revision > old_revision, "New session uses a new epoch without reusing old deal/revision IDs.")
	_check(table.members[1].game.player.money == 25 and not table.members[1].has_result and table.order.is_empty() and table.dealer.hand.cards.is_empty(), "New session clears hands, wagers, net and standings; bankroll resets to chosen money.")
	_check(not table.ready_bet(1, 10, true, old_deal, old_settings).is_empty(), "Previous-session Ready settings cannot arm the new session.")
	_check(not table.start_session(1, 1, 99, 1).is_empty(), "Previous-session Start cannot reset new balances.")
	print("PASS: Split/double final settlement, winner calculation, fresh session and stale-request boundaries.")


func _standings_and_ties() -> void:
	var table := _fresh([10, 10, 10, 10, 10, 10, 10, 8, 7, 8], true)
	_start(table, 1)
	for id in [1, 2, 3, 4]:
		table.ready_bet(id, 10, true, 0)
	for id in [1, 2, 3, 4]:
		_play(table, id, "stand")
	var places: Array = table.session.standings()
	_check(places[0].place == 1 and places[1].place == 1 and places[2].place == 3 and places[3].place == 4, "Equal balances share placement: 1,1,3,4.")
	_check(places[0].balance == 110 and places[2].balance == 100 and places[3].balance == 90, "Final standings sort descending bankrolls.")
	_check(places[0].rounds == 1 and places[3].rounds == 1, "Each entrant records completed participation.")
	places[0].balance = -999
	_check(table.session.standings()[0].balance == 110, "Snapshots cannot mutate the host's results ledger.")
	print("PASS: Four-player standings, shared first place, skipped ranks and immutable result snapshots.")


func _refunds_and_naturals() -> void:
	var table := _fresh([10, 10, 10, 7, 8, 6])
	_start(table, 1)
	_deal(table)
	_play(table, 1, "stand")
	_play(table, 2, "stand")
	_check(table.session.completed == 0 and table.session.status == "active" and table.members[1].game.player.money == 100, "Exhausted dealer refunds and does not consume a round.")
	_seed_cards(table, [10])
	_deal(table)
	_check(table.session.completed == 0 and table.phase == "settled", "Interrupted opening is refunded without consuming round.")
	_seed_cards(table, [14, 10, 14, 10, 9, 10, 14])
	_enable(table, [&"mystery_card"])
	_deal(table)
	_play(table, 1, "keep_mystery")
	_check(table.session.completed == 0 and table.session.status == "active", "Mystery choice against dealer natural does not prematurely finish session.")
	_play(table, 2, "replace_mystery")
	_check(table.session.completed == 1 and table.session.status == "finished", "Both-natural push counts once after all opening choices.")
	_check(table.session.standings()[0].place == 1 and table.session.standings()[1].place == 1, "Two-natural pushes preserve tied starting balances.")
	print("PASS: Refunded opening/dealer retries and final Mystery/dealer Blackjack choices.")


func _membership_and_bankruptcy() -> void:
	var table := _fresh([10, 10, 10, 7, 8, 7])
	_start(table, 2)
	_deal(table)
	var records := _records(true)
	table.sync_members(records)
	_check(not table.snapshot().players[2].enrolled and not table.ready_bet(3, 1, true, 1).is_empty(), "Late arrival spectates and never enters readiness quorum.")
	records.erase(2)
	table.sync_members(records)
	_play(table, 1, "stand")
	_check(table.session.entrants.has(2) and not table.session.entrants[2].connected and table.session.entrants[2].balance == 110, "Disconnected wager settles once and remains in standings.")
	records[4] = {"name": "Guest", "seat": 1}
	table.sync_members(records)
	_check(not table.session.entrants.has(4) and table.members[4].game.player.money == 0, "Rejoining with the same name cannot obtain a fresh competitive balance.")
	_seed_cards(table, [10, 10, 7, 7])
	table.ready_bet(1, 10, true, table.round_id)
	_play(table, 1, "stand")
	_check(table.session.status == "finished" and table.session.standings().size() == 2, "Spectators never appear in this session's final competition.")
	_start(table, 1, 40)
	_check(table.session.entrants.size() == 3 and not table.members.has(2) and table.members[4].game.player.money == 40, "Next session enrolls current connections and drops departed entries.")
	table = _fresh([10, 10, 10, 6, 6, 7, 10, 10])
	_start(table, 10, 1)
	table.ready_bet(1, 1, true, 0)
	table.ready_bet(2, 1, true, 0)
	_play(table, 1, "hit")
	_play(table, 2, "hit")
	_check(table.session.status == "finished" and table.session.completed == 1 and table.session.standings()[0].balance == 0, "All bankrupt entrants end the session early after settlement.")
	print("PASS: Late joins, departed score retention, rejoin spectating, next-session enrollment and bankruptcy ending.")
