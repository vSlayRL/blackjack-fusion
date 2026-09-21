extends Node


func _ready():
	print("=== BLACKJACK FUSION LOGIC TESTS ===")

	test_card_values()
	test_hand_ace_logic()
	test_deck()
	test_player_betting()
	test_minimum_bet()
	test_player_bust_ends_round()
	test_dealer_turn_and_push()
	test_player_win()
	test_dealer_bust()
	test_complete_random_round()

	print("\n=== ALL LOGIC TESTS PASSED ===")


func test_card_values() -> void:
	var ace := Card.new(Card.Suit.SPADES, Card.Rank.ACE)
	var king := Card.new(Card.Suit.HEARTS, Card.Rank.KING)
	var seven := Card.new(Card.Suit.CLUBS, Card.Rank.SEVEN)

	assert(ace.get_blackjack_value() == 11)
	assert(king.get_blackjack_value() == 10)
	assert(seven.get_blackjack_value() == 7)
	assert(ace.get_card_name() == "Ace of Spades")

	print("PASS: Card values and names")


func test_hand_ace_logic() -> void:
	var hand := Hand.new()
	hand.add_card(Card.new(Card.Suit.HEARTS, Card.Rank.ACE))
	hand.add_card(Card.new(Card.Suit.CLUBS, Card.Rank.SEVEN))
	assert(hand.get_total() == 18)

	hand.add_card(Card.new(Card.Suit.SPADES, Card.Rank.KING))
	assert(hand.get_total() == 18)
	assert(not hand.is_bust())

	hand.clear_hand()
	hand.add_card(Card.new(Card.Suit.HEARTS, Card.Rank.ACE))
	hand.add_card(Card.new(Card.Suit.DIAMONDS, Card.Rank.KING))
	assert(hand.is_blackjack())

	print("PASS: Hand totals, Aces, and Blackjack")


func test_deck() -> void:
	var deck := Deck.new()
	assert(deck.cards_remaining() == 52)

	var card := deck.deal_card()
	assert(card != null)
	assert(deck.cards_remaining() == 51)

	deck.reset()
	assert(deck.cards_remaining() == 52)

	print("PASS: Deck creation, dealing, and reset")


func test_player_betting() -> void:
	var player := Player.new("Test Player", 100.0)
	assert(player.place_bet(20.0))
	assert(player.money == 80.0)
	assert(not player.place_bet(10.0))

	player.win_bet()
	assert(player.money == 120.0)
	assert(player.bet == 0.0)

	assert(player.place_bet(20.0))
	player.lose_bet()
	assert(player.money == 100.0)

	assert(player.place_bet(20.0))
	player.win_blackjack()
	assert(player.money == 130.0)

	assert(not player.place_bet(200.0))
	assert(not player.place_bet(0.0))

	print("PASS: Betting and payouts")


func test_minimum_bet() -> void:
	var game := BlackjackGame.new()

	assert(not game.start_round(0.5))
	assert(game.player.money == 100.0)
	assert(game.status_message == "Minimum bet is $1.00.")

	game.player.money = 0.5
	assert(not game.can_start_round())

	print("PASS: Minimum bet and low-bankroll protection")


func test_player_bust_ends_round() -> void:
	var game := _new_active_game(20.0)

	# Replace the random player hand with a guaranteed 19.
	game.player.hand.clear_hand()
	game.player.hand.add_card(Card.new(Card.Suit.HEARTS, Card.Rank.TEN))
	game.player.hand.add_card(Card.new(Card.Suit.CLUBS, Card.Rank.NINE))

	# The next card is guaranteed to make the player bust.
	game.deck.cards.clear()
	game.deck.cards.append(Card.new(Card.Suit.SPADES, Card.Rank.FIVE))

	var dealer_cards_before := game.dealer.hand.card_count()
	assert(game.player_hit())
	assert(game.player.hand.is_bust())
	assert(game.round_over)
	assert(game.result == BlackjackGame.RoundResult.PLAYER_BUST)
	assert(game.dealer.hand.card_count() == dealer_cards_before)
	assert(game.player.bet == 0.0)
	assert(not game.player_stand())

	print("PASS: Player bust ends the round without a dealer turn")


func test_dealer_turn_and_push() -> void:
	var game := _new_active_game(10.0)

	game.player.hand.clear_hand()
	game.player.hand.add_card(Card.new(Card.Suit.HEARTS, Card.Rank.TEN))
	game.player.hand.add_card(Card.new(Card.Suit.CLUBS, Card.Rank.EIGHT))

	game.dealer.hand.clear_hand()
	game.dealer.hand.add_card(Card.new(Card.Suit.DIAMONDS, Card.Rank.TEN))
	game.dealer.hand.add_card(Card.new(Card.Suit.SPADES, Card.Rank.SIX))

	# Dealer has 16 and must draw this 2, ending on 18.
	game.deck.cards.clear()
	game.deck.cards.append(Card.new(Card.Suit.HEARTS, Card.Rank.TWO))

	assert(game.player_stand())
	assert(game.dealer.hand.get_total() == 18)
	assert(game.result == BlackjackGame.RoundResult.PUSH)
	assert(game.player.money == 100.0)

	print("PASS: Dealer hits below 17 and push returns the bet")


func test_player_win() -> void:
	var game := _new_active_game(10.0)

	game.player.hand.clear_hand()
	game.player.hand.add_card(Card.new(Card.Suit.HEARTS, Card.Rank.KING))
	game.player.hand.add_card(Card.new(Card.Suit.CLUBS, Card.Rank.NINE))

	game.dealer.hand.clear_hand()
	game.dealer.hand.add_card(Card.new(Card.Suit.DIAMONDS, Card.Rank.TEN))
	game.dealer.hand.add_card(Card.new(Card.Suit.SPADES, Card.Rank.EIGHT))

	assert(game.player_stand())
	assert(game.result == BlackjackGame.RoundResult.PLAYER_WIN)
	assert(game.player.money == 110.0)

	print("PASS: Higher player total wins and pays correctly")


func test_dealer_bust() -> void:
	var game := _new_active_game(10.0)

	game.player.hand.clear_hand()
	game.player.hand.add_card(Card.new(Card.Suit.HEARTS, Card.Rank.TEN))
	game.player.hand.add_card(Card.new(Card.Suit.CLUBS, Card.Rank.EIGHT))

	game.dealer.hand.clear_hand()
	game.dealer.hand.add_card(Card.new(Card.Suit.DIAMONDS, Card.Rank.TEN))
	game.dealer.hand.add_card(Card.new(Card.Suit.SPADES, Card.Rank.SIX))

	# Dealer has 16 and must draw the King, causing a bust.
	game.deck.cards.clear()
	game.deck.cards.append(Card.new(Card.Suit.HEARTS, Card.Rank.KING))

	assert(game.player_stand())
	assert(game.dealer.hand.is_bust())
	assert(game.result == BlackjackGame.RoundResult.DEALER_BUST)
	assert(game.player.money == 110.0)

	print("PASS: Dealer bust pays the player")


func test_complete_random_round() -> void:
	var game := BlackjackGame.new()
	assert(game.start_round(10.0))

	print("\n--- RANDOM ROUND DEMO ---")
	print("Player money after bet: $", game.player.money)
	print("Player hand: ", _hand_to_string(game.player.hand), " = ", game.player.hand.get_total())
	print("Dealer showing: ", game.dealer.hand.cards[0].get_card_name())

	# A starting Blackjack may have already ended the round.
	while game.is_player_turn() and game.player.hand.get_total() < 17:
		game.player_hit()

	if game.is_player_turn():
		game.player_stand()

	assert(game.round_over)
	assert(game.player.bet == 0.0)

	print("Dealer hand: ", _hand_to_string(game.dealer.hand), " = ", game.dealer.hand.get_total())
	print("Result: ", game.get_result_text())
	print("Player money: $", game.player.money)
	print("PASS: Complete round reaches a valid finished state")


func _new_active_game(bet_amount: float) -> BlackjackGame:
	# Opening Blackjacks can legitimately end a random round immediately.
	# For tests that need an active player turn, create a fresh game until
	# the opening deal produces a normal playable hand.
	for attempt in range(100):
		var game := BlackjackGame.new()

		if game.start_round(bet_amount) and game.is_player_turn():
			return game

	assert(false, "Could not create an active test round.")
	return null


func _hand_to_string(hand: Hand) -> String:
	var names: Array[String] = []

	for card in hand.cards:
		names.append(card.get_card_name())

	return ", ".join(names)
