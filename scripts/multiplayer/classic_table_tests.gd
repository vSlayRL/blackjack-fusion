extends Node
## Repeatable multiplayer flows with known draws, independent of random deck luck.

class FixedDeck extends Deck:
	var draws: Array[Card] = []
	func reset() -> void:
		cards.assign(draws)
		cards.reverse()

var failed: bool = false


func _ready() -> void:
	_betting_and_shared_dealer()
	_double_and_bust()
	_naturals_and_split()
	_departures_and_joining()
	_invalid_bets_and_refund()
	_random_four_player_rounds()
	if not failed:
		print("ALL SHARED CLASSIC TABLE TESTS PASSED")
	get_tree().quit(1 if failed else 0)


func _check(condition: bool, text: String) -> void:
	if not condition:
		failed = true
		push_error(text)


func _records(third: bool = false) -> Dictionary:
	var records := {1: {"name": "Host", "seat": 0}, 2: {"name": "Guest", "seat": 1}}
	if third:
		records[3] = {"name": "Third", "seat": 2}
	return records


func _table(ranks: Array) -> ClassicTable:
	var table := ClassicTable.new()
	table.sync_members(_records())
	_check(table.start_session(1, 100, 100, 0).is_empty(), "Host starts test session.")
	var fixed := FixedDeck.new()
	for index in range(ranks.size()):
		fixed.draws.append(Card.new((index % 4) as Card.Suit, int(ranks[index]) as Card.Rank))
	table.deck = fixed
	return table


func _deal(table: ClassicTable) -> void:
	_check(table.ready_bet(1, 10, true, table.round_id).is_empty(), "Host can ready.")
	_check(table.ready_bet(2, 10, true, table.round_id).is_empty(), "Guest can ready.")


func _act(table: ClassicTable, id: int, action: String) -> void:
	_check(table.act(id, action, table.revision).is_empty(), "Legal action accepted: %d %s" % [id, action])


func _betting_and_shared_dealer() -> void:
	var table := _table([10, 9, 10, 7, 8, 6, 10])
	table.ready_bet(1, 10, true, 0)
	_check(table.phase == "betting" and table.members[1].game.player.money == 100, "Ready locks a bet without charging before everyone confirms.")
	table.ready_bet(1, 0, false, 0)
	_check(not table.members[1].ready, "Ready can be cancelled before the deal.")
	_deal(table)
	var public := table.snapshot()
	_check(table.turn_id == 1 and public.dealer[1] == null and public.dealer_total == -1, "First turn follows seats; snapshot hides hole identity and total.")
	_check(not table.act(2, "hit", table.revision).is_empty(), "Another player cannot act out of turn.")
	var revision := table.revision
	_act(table, 1, "stand")
	_check(table.turn_id == 2 and table.dealer.hand.cards.size() == 2, "Dealer waits until all players finish.")
	_check(not table.act(1, "stand", revision).is_empty(), "A repeated or stale action cannot advance the table twice.")
	_act(table, 2, "stand")
	_check(table.phase == "settled" and table.dealer.hand.cards.size() == 3 and table.dealer.hand.is_bust(), "One shared dealer hits sixteen even when it already beats a hand.")
	_check(table.members[1].game.player.money == 110 and table.members[2].game.player.money == 110, "Both winners receive individual payouts.")
	_check(table.members[1].delta == 10 and table.members[2].delta == 10, "Net results exclude returned principal.")
	table._finish_round()
	_check(table.members[1].game.player.money == 110, "Settlement is exactly once.")
	table.ready_bet(1, 10, true, 1)
	_check(table.members[1].has_result, "Last result remains while preparing the next round.")
	table.ready_bet(2, 10, true, 1)
	_check(not table.members[1].has_result and table.members[1].delta == 0 and table.round_id == 2, "Net indicator clears at the next accepted deal.")
	print("PASS: Ready/cancel, shared dealer, hidden card, turn ownership, payouts, next-round net clearing.")


func _double_and_bust() -> void:
	var table := _table([5, 10, 10, 6, 8, 7, 10])
	_deal(table)
	_act(table, 1, "double")
	_check(table.turn_id == 2 and table.members[1].game.player.hands[0].wager == 20 and table.members[1].game.player.hand.card_count() == 3, "Double reserves a matching stake, draws once and ends the turn.")
	_act(table, 2, "stand")
	_check(table.members[1].game.player.money == 120 and table.members[1].delta == 20, "Doubled win settles full stake and correct net.")
	table = _table([10, 10, 10, 6, 8, 7, 10])
	_deal(table)
	_act(table, 1, "hit")
	_check(table.turn_id == 2, "Bust advances to the next player.")
	_act(table, 2, "stand")
	_check(table.members[1].delta == -10 and table.members[2].delta == 10, "A busted player loses while another wins the same dealer round.")
	print("PASS: Double, bust, individual gains and losses.")


func _naturals_and_split() -> void:
	var table := _table([14, 10, 14, 12, 9, 13])
	_deal(table)
	_check(table.phase == "settled" and table.members[1].delta == 0 and table.members[2].delta == -10, "Dealer natural pushes player natural and beats the other player immediately.")
	table = _table([14, 10, 10, 12, 8, 6, 10])
	_deal(table)
	_check(table.turn_id == 2, "Opening player Blackjack skips that player's turn.")
	_act(table, 2, "stand")
	_check(table.members[1].delta == 15 and table.members[2].delta == 10, "Natural earns 3:2 while the other hand earns ordinary winnings.")
	table = _table([14, 10, 10, 14, 7, 7, 10, 9])
	_deal(table)
	_act(table, 1, "split")
	_check(table.turn_id == 2 and table.members[1].game.player.hands.size() == 2, "Split Aces receive one card each and end automatically.")
	_act(table, 2, "stand")
	_check(table.members[1].delta == 20, "Split two-card twenty-one receives an ordinary payout.")
	table = _table([8, 10, 10, 8, 8, 7, 3, 10, 10])
	_deal(table)
	_act(table, 1, "split")
	_act(table, 1, "double")
	_check(table.turn_id == 1 and table.members[1].game.player.active_hand_index == 1, "Each split hand gets its own turn before the next player.")
	_act(table, 1, "stand")
	_act(table, 2, "stand")
	_check(table.members[1].delta == 30 and table.members[1].game.player.money == 130, "Split and doubled stakes settle separately without losing a wager.")
	print("PASS: Naturals, two-Blackjack push, split Aces, split ordinary 21 and split/double settlement.")


func _departures_and_joining() -> void:
	var table := _table([10, 10, 10, 7, 8, 7])
	_deal(table)
	var records := _records(true)
	table.sync_members(records)
	_check(table.snapshot().players[2].hands.is_empty(), "A newly seated player waits for the next deal.")
	records[1].seat = -1
	table.sync_members(records)
	_check(table.turn_id == 2 and table.members[1].game.player.money == 90, "Standing up auto-stands the hand without refunding a dealt wager.")
	records.erase(2)
	table.sync_members(records)
	_check(table.phase == "settled" and table.turn_id == 0, "Disconnect during the final turn completes the round without getting stuck.")
	_check(table.members[1].game.player.money == 100 and table.members[3].game.player.money == 0, "Standing player's push settles; late arrival watches without a new bankroll.")
	print("PASS: Mid-round joins, standing and disconnected turn recovery.")


func _invalid_bets_and_refund() -> void:
	var table := _table([10, 10, 10, 7, 8, 6])
	for amount in [NAN, INF, -1.0, 0.0, 0.5, 101.0, 1.001, 50.0001]:
		_check(not table.ready_bet(1, amount, true, 0).is_empty(), "Reject invalid or unaffordable wager.")
	_check(table.members[1].game.player.money == 100 and not table.members[1].ready, "Rejected wagers cannot change the bankroll or readiness.")
	_deal(table)
	_check(not table.ready_bet(1, 10, true, 0).is_empty(), "Old ready cannot ready a new round.")
	_act(table, 1, "stand")
	_act(table, 2, "stand")
	_check(table.members[1].game.player.money == 100 and table.members[2].game.player.money == 100, "Exhausted dealer deck refunds everyone instead of trapping the table.")
	print("PASS: Invalid wager rejection and incomplete-deal recovery.")


func _random_four_player_rounds() -> void:
	var table := ClassicTable.new()
	var records := _records(true)
	records[4] = {"name": "Fourth", "seat": 3}
	table.sync_members(records)
	_check(table.start_session(1, 100, 100, 0).is_empty(), "Host starts four-player test session.")
	for round_index in range(12):
		for id in [1, 2, 3, 4]:
			table.ready_bet(id, 1, true, table.round_id)
		while table.phase == "playing":
			var id := table.turn_id
			var game: ClassicTableHand = table.members[id].game
			_act(table, id, "hit" if game.player.hand.get_total() < 16 else "stand")
		var seen: Array[int] = []
		for card in table.dealer.hand.cards:
			seen.append(ClassicTable.encode_card(card))
		for member in table.members.values():
			for card in member.game.player.hand.cards:
				var code := ClassicTable.encode_card(card)
				_check(not seen.has(code), "A shared deck must never deal the same card twice in one round.")
				seen.append(code)
		_check(seen.size() + table.deck.cards_remaining() == 52, "All dealt and remaining cards account for one complete deck.")
		_check(table.round_id == round_index + 1, "Completed rounds advance once.")
	print("PASS: Twelve full four-player rounds conserve a shared 52-card deck.")
