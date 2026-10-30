extends "res://scripts/multiplayer/classic_table_tests.gd"
## Known draws verify shared round rules without relying on a lucky shuffle.

const ALL_RULES: Array[StringName] = [&"reroll", &"second_chance", &"lucky_nine", &"double_target", &"mystery_card"]


func _ready() -> void:
	_settings_and_random()
	_mystery_openings()
	_lucky_and_reroll()
	_recovery_and_targets()
	_split_and_departure()
	_four_player_rules()
	if not failed:
		print("ALL SHARED SPECIAL RULE TESTS PASSED")
	get_tree().quit(1 if failed else 0)


func _enable(table: ClassicTable, ids: Array[StringName], mode: int = RuleManager.RuleMode.ALL_SELECTED, count: int = 1) -> void:
	_check(table.configure(1, mode, ids, count, table.settings_revision).is_empty(), "Host configures next deal.")


func _play(table: ClassicTable, id: int, action: String, index: int = -1) -> void:
	_check(table.act(id, action, table.revision, index).is_empty(), "Special action accepted: %d %s" % [id, action])


func _settings_and_random() -> void:
	var table := _table([10, 10, 10, 7, 8, 7])
	_check(not table.configure(2, 1, ALL_RULES, 1, 0).is_empty(), "Guest cannot change settings.")
	_check(not table.configure(1, 9, ALL_RULES, 1, 0).is_empty(), "Invalid mode rejected.")
	_check(not table.configure(1, 1, [&"unknown"], 1, 0).is_empty(), "Unknown rule rejected.")
	_check(not table.configure(1, 1, ALL_RULES, 6, 0).is_empty(), "Invalid random count rejected.")
	table.ready_bet(1, 10, true, 0)
	_enable(table, [&"reroll"])
	_check(not table.members[1].ready and table.members[1].game.player.money == 100, "Saving clears ready without charging money.")
	_check(not table.ready_bet(1, 10, true, 0, 0).is_empty(), "Old-settings ready rejected.")
	_check(not table.configure(1, 1, ALL_RULES, 1, 0).is_empty(), "Stale console cannot overwrite new preferences.")
	_deal(table)
	var revision := table.revision
	_enable(table, [&"second_chance"])
	_check(table.revision == revision and table.active_ids() == [&"reroll"], "Mid-round settings leave gameplay revision and active rules unchanged.")
	_play(table, 1, "stand")
	_play(table, 2, "stand")
	_deal(table)
	_check(table.active_ids() == [&"second_chance"], "Staged settings take effect at next deal.")
	for count in range(1, 6):
		for attempt in range(8):
			table = _table([10, 10, 10, 7, 8, 7])
			_enable(table, ALL_RULES, RuleManager.RuleMode.RANDOM_SELECTED, count)
			_deal(table)
			_check(table.active_ids().size() == count, "Random honors host count.")
			var seen: Array[StringName] = []
			for id in table.active_ids():
				_check(not seen.has(id), "Random never duplicates a rule.")
				seen.append(id)
			for member in table.members.values():
				_check(member.game.rules.active_rules.size() == count, "Every player gets same rule count.")
				for rule in member.game.rules.active_rules:
					_check(table.active_ids().has(rule.rule_id), "Every player gets same rule selection.")
				_check(member.game.get_double_target() == table.target_total(), "One shared Double Target.")
			if table.active_ids().has(&"double_target"):
				_check(table.target_total() >= 22 and table.target_total() <= 30, "Target stays in 22–30.")
	table = _table([10, 10, 10, 7, 8, 7])
	_enable(table, [&"reroll", &"lucky_nine"], RuleManager.RuleMode.RANDOM_SELECTED, 5)
	_deal(table)
	_check(table.active_ids().size() == 2, "Random clamps to checked pool.")
	print("PASS: Host-only settings, Ready consent, next-deal staging, 40 random selections, count clamp and shared targets.")


func _mystery_openings() -> void:
	var table := _table([14, 10, 14, 10, 9, 10, 14])
	_enable(table, [&"mystery_card"])
	_deal(table)
	var public := table.snapshot()
	for person in public.players:
		_check(person.hands[0].cards[1] == null and person.hands[0].total == -1, "No hidden player identity or total in snapshot.")
	_check(public.dealer[1] == null and public.dealer_total == -1, "Dealer natural stays concealed throughout choices.")
	_check(not table.act(1, "hit", table.revision).is_empty(), "Mystery choice blocks Hit.")
	_check(not table.act(1, "stand", table.revision).is_empty(), "Mystery choice blocks Stand.")
	_check(not table.act(2, "keep_mystery", table.revision).is_empty(), "Opening choices follow seat order.")
	_play(table, 1, "keep_mystery")
	_check(table.phase == "playing" and table.snapshot().dealer[1] == null, "First natural does not end choices or reveal dealer.")
	_play(table, 2, "replace_mystery")
	_check(table.phase == "settled" and table.members[1].delta == 0 and table.members[2].delta == 0, "Kept and replacement opening naturals both push dealer Blackjack.")
	_check(not table.act(2, "replace_mystery", table.revision).is_empty(), "Opening choice cannot repeat.")
	table = _table([14, 10, 10, 2, 8, 7, 10])
	_enable(table, [&"mystery_card"])
	_deal(table)
	_play(table, 1, "replace_mystery")
	_play(table, 2, "keep_mystery")
	_check(table.turn_id == 2 and table.snapshot().dealer[1] == null, "Replacement natural waits for other player's ordinary turn.")
	_play(table, 2, "stand")
	_check(table.members[1].delta == 15 and table.members[2].delta == 10, "Mystery replacement natural receives 3:2.")
	print("PASS: Concealed opening identities/totals, keep/swap, both-natural pushes, replacement 3:2 and dealer privacy.")


func _lucky_and_reroll() -> void:
	var table := _table([4, 10, 10, 10, 8, 6, 5, 10])
	_enable(table, [&"mystery_card", &"lucky_nine", &"reroll"])
	_deal(table)
	var removed := table.members[1].game.player.hand.cards[1] as Card
	_play(table, 1, "replace_mystery")
	_play(table, 2, "keep_mystery")
	_check(table.members[1].game.player.hands[0].lucky_nine_qualified and not table.deck.cards.has(removed), "Finalized opening 9 qualifies and old card stays discarded.")
	_play(table, 1, "stand")
	_play(table, 2, "stand")
	_check(table.members[1].delta == 15, "Opening 9 adds 50% base wager on ordinary dealer-bust win.")
	table = _table([14, 10, 10, 2, 8, 7, 10, 3])
	_enable(table, [&"reroll"])
	_deal(table)
	_play(table, 1, "reroll", 1)
	_check(table.turn_id == 2 and not table.members[1].game.player.hands[0].is_natural_blackjack(), "Rerolled two-card 21 is ordinary and advances turn.")
	_play(table, 2, "reroll", 1)
	_check(table.snapshot().players[0].reroll_used and table.snapshot().players[1].reroll_used, "Every player has an independent Reroll.")
	_check(not table.act(2, "reroll", table.revision, 0).is_empty(), "Same player cannot Reroll twice.")
	_play(table, 2, "stand")
	_check(table.members[1].delta == 10, "Rerolled 21 pays ordinary win, not 3:2.")
	print("PASS: Mystery-finalized Lucky 9, discarded cards, independent Rerolls and ordinary rerolled 21.")


func _set_target(table: ClassicTable, total: int) -> void:
	(table.rules.get_rule(&"double_target") as DoubleTargetRule).target_total = total
	for member in table.members.values():
		(member.game.rules.get_rule(&"double_target") as DoubleTargetRule).target_total = total


func _recovery_and_targets() -> void:
	var table: ClassicTable
	for recover in [true, false]:
		table = _table([10, 10, 10, 8, 8, 7, 7])
		_enable(table, [&"double_target", &"second_chance", &"lucky_nine"])
		_deal(table)
		_set_target(table, 25)
		_play(table, 1, "hit")
		_check(table.turn_id == 1 and table.snapshot().players[0].can_second_chance and table.snapshot().players[0].target_match, "Target bust still offers Second Chance.")
		_play(table, 1, "second_chance" if recover else "stand")
		if recover:
			_check(table.members[1].game.player.hand.get_total() == 18 and table.turn_id == 1, "Recovery removes the bust card and resumes play.")
			_play(table, 1, "stand")
		_play(table, 2, "stand")
		_check(table.members[1].delta == (10.0 if recover else 2.5), "Recover or accept exact-target 1.25x total return, with no extra bonus.")
	table = _table([5, 10, 10, 6, 8, 7, 14])
	_enable(table, [&"second_chance"])
	_deal(table)
	_play(table, 1, "double") # 11 + Ace = 12, no bust; use a separate actual bust.
	_play(table, 2, "stand")
	table = _table([10, 10, 10, 8, 8, 7, 10, 10])
	_enable(table, [&"second_chance"])
	_deal(table)
	_play(table, 1, "double")
	_play(table, 1, "second_chance")
	_check(table.turn_id == 2 and table.members[1].game.player.hands[0].wager == 20, "Rescued Double retains doubled wager and ends hand.")
	_play(table, 2, "hit")
	_play(table, 2, "second_chance")
	_play(table, 2, "stand")
	_check(table.members[1].delta == 20 and table.members[2].delta == 10, "Each player has an independent recovery.")
	table = _table([2, 10, 10, 10, 8, 7, 5, 10])
	_enable(table, [&"reroll", &"second_chance"])
	_deal(table)
	_play(table, 1, "hit") # 2,10,5 = 17
	_play(table, 1, "reroll", 0) # 10,10,5 = 25
	_play(table, 1, "second_chance")
	_check(table.members[1].game.player.hand.get_total() == 15 and table.members[1].game.player.hand.cards[0].rank == 10, "Recovery removes the indexed Reroll bust card, not the last hit.")
	_play(table, 1, "stand")
	_play(table, 2, "stand")
	print("PASS: Target payout/recovery choice, independent Second Chance, rescued Double and indexed Reroll recovery.")


func _split_and_departure() -> void:
	var table := _table([8, 10, 10, 8, 8, 7, 3, 2, 10, 10])
	_enable(table, [&"reroll", &"second_chance"])
	_deal(table)
	_play(table, 1, "split")
	_play(table, 1, "reroll", 1)
	_play(table, 1, "hit")
	_play(table, 1, "stand") # accept bust rather than consume recovery
	_check(table.members[1].game.player.active_hand_index == 1 and not table.members[1].game.is_awaiting_second_chance(), "Accepting bust clears pending recovery before next split hand.")
	_check(not table.act(1, "reroll", table.revision, 0).is_empty(), "Split hands share player's Reroll use.")
	_play(table, 1, "stand")
	_play(table, 2, "stand")
	table = _table([10, 10, 10, 7, 8, 7])
	_enable(table, [&"mystery_card"])
	_deal(table)
	var records := _records()
	records.erase(1)
	table.sync_members(records)
	_check(table.turn_id == 2 and table.snapshot().dealer[1] == null, "Disconnect keeps opening and advances choice without revealing dealer.")
	_play(table, 2, "keep_mystery")
	_play(table, 2, "stand")
	_check(table.phase == "settled" and table.members[1].game.player.money == 100, "Departed opening remains wagered and settles normally.")
	print("PASS: Split-shared allowance, split bust cleanup and abandoned opening recovery.")


func _four_player_rules() -> void:
	var table := ClassicTable.new()
	var records := _records(true)
	records[4] = {"name": "Fourth", "seat": 3}
	table.sync_members(records)
	_check(table.start_session(1, 100, 100, 0).is_empty(), "Host starts all-rule test session.")
	_enable(table, ALL_RULES)
	for round_index in range(24):
		for id in [1, 2, 3, 4]:
			table.ready_bet(id, 1, true, table.round_id)
		var actions := 0
		while table.phase == "playing" and actions < 100:
			actions += 1
			var id := table.turn_id
			var game: ClassicTableHand = table.members[id].game
			if game.is_awaiting_mystery_card():
				_play(table, id, "replace_mystery" if id % 2 == 0 else "keep_mystery")
			elif game.can_second_chance():
				_play(table, id, "second_chance")
			elif game.can_reroll() and round_index % 2 == 0:
				_play(table, id, "reroll", 0)
			else:
				_play(table, id, "hit" if game.player.hand.get_total() < 17 else "stand")
		_check(table.phase == "settled", "Four-player all-rule rounds finish without stalls.")
		for member in table.members.values():
			_check(is_equal_approx(member.delta, member.game.player.money - member.game._round_start_money), "Each player's net matches their bankroll.")
	print("PASS: 24 full four-player rounds with all five rules and independent bankrolls.")
