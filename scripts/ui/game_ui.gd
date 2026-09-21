extends Control


var game: BlackjackGame


@onready var money_label: Label = $CenterContainer/GamePanel/MarginContainer/MainLayout/HeaderRow/MoneyLabel
@onready var current_bet_label: Label = $CenterContainer/GamePanel/MarginContainer/MainLayout/HeaderRow/CurrentBetLabel
@onready var status_label: Label = $CenterContainer/GamePanel/MarginContainer/MainLayout/StatusLabel

@onready var dealer_cards_label: Label = $CenterContainer/GamePanel/MarginContainer/MainLayout/DealerSection/DealerCardsLabel
@onready var dealer_total_label: Label = $CenterContainer/GamePanel/MarginContainer/MainLayout/DealerSection/DealerTotalLabel

@onready var player_cards_label: Label = $CenterContainer/GamePanel/MarginContainer/MainLayout/PlayerSection/PlayerCardsLabel
@onready var player_total_label: Label = $CenterContainer/GamePanel/MarginContainer/MainLayout/PlayerSection/PlayerTotalLabel

@onready var bet_spin_box: SpinBox = $CenterContainer/GamePanel/MarginContainer/MainLayout/BetRow/BetSpinBox
@onready var deal_button: Button = $CenterContainer/GamePanel/MarginContainer/MainLayout/BetRow/DealButton

@onready var hit_button: Button = $CenterContainer/GamePanel/MarginContainer/MainLayout/ActionRow/HitButton
@onready var stand_button: Button = $CenterContainer/GamePanel/MarginContainer/MainLayout/ActionRow/StandButton
@onready var restart_button: Button = $CenterContainer/GamePanel/MarginContainer/MainLayout/ActionRow/RestartButton


func _ready() -> void:
	game = BlackjackGame.new()

	deal_button.pressed.connect(_on_deal_pressed)
	hit_button.pressed.connect(_on_hit_pressed)
	stand_button.pressed.connect(_on_stand_pressed)
	restart_button.pressed.connect(_on_restart_pressed)

	_refresh_ui()


func _on_deal_pressed() -> void:
	var bet_amount := bet_spin_box.value

	if not game.start_round(bet_amount):
		_refresh_ui()
		return

	_refresh_ui()


func _on_hit_pressed() -> void:
	game.player_hit()
	_refresh_ui()


func _on_stand_pressed() -> void:
	game.player_stand()
	_refresh_ui()


func _on_restart_pressed() -> void:
	game = BlackjackGame.new()
	bet_spin_box.value = 10.0
	_refresh_ui()


func _refresh_ui() -> void:
	money_label.text = "Money: $%.2f" % game.player.money
	current_bet_label.text = "Current Bet: $%.2f" % game.player.bet
	status_label.text = game.status_message

	player_cards_label.text = _get_player_cards_text()
	player_total_label.text = "Total: %d" % game.player.hand.get_total()

	dealer_cards_label.text = _get_dealer_cards_text()
	dealer_total_label.text = _get_dealer_total_text()

	var player_turn := game.is_player_turn()
	var can_deal := game.can_start_round()

	hit_button.disabled = not player_turn
	stand_button.disabled = not player_turn
	deal_button.disabled = not can_deal
	bet_spin_box.editable = can_deal

	if can_deal:
		bet_spin_box.max_value = max(BlackjackGame.MINIMUM_BET, game.player.money)
		bet_spin_box.value = min(bet_spin_box.value, bet_spin_box.max_value)
		deal_button.text = "Deal Cards"
	else:
		deal_button.text = "Round In Progress"

	if game.round_over and game.player.money < BlackjackGame.MINIMUM_BET:
		status_label.text = "You do not have enough money for the $%.2f minimum bet. Restart the game to play again." % BlackjackGame.MINIMUM_BET
		deal_button.text = "No Money Remaining"


func _get_player_cards_text() -> String:
	if game.player.hand.cards.is_empty():
		return "No cards"

	var card_names: PackedStringArray = []

	for card in game.player.hand.cards:
		card_names.append(card.get_card_name())

	return "  |  ".join(card_names)


func _get_dealer_cards_text() -> String:
	if game.dealer.hand.cards.is_empty():
		return "No cards"

	var card_names: PackedStringArray = []

	for i in range(game.dealer.hand.cards.size()):
		var card := game.dealer.hand.cards[i]

		if i == 1 and not game.round_over:
			card_names.append("[Hidden Card]")
		else:
			card_names.append(card.get_card_name())

	return "  |  ".join(card_names)


func _get_dealer_total_text() -> String:
	if game.dealer.hand.cards.is_empty():
		return "Total: ?"

	if game.round_over:
		return "Total: %d" % game.dealer.hand.get_total()

	var visible_card := game.dealer.hand.cards[0]
	return "Showing: %d" % visible_card.get_blackjack_value()
