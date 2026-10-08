## Presents the game through responsive card panels, controls, and a rule-settings dialog.
## The view renders engine state, including concealment; BlackjackGame remains responsible for legality and payouts.
extends Control

const INK := Color("eff5f1")
const MUTED := Color("a8bdb3")
const GOLD := Color("e8c36e")
const PANEL := Color("122b25")
const BORDER := Color("305247")
const GAIN := Color("70e59b")
const LOSS := Color("ff8791")

var game: BlackjackGame
var hand_panels: Array[PanelContainer] = []
var _last_active_hand: int = -1
var _last_hand_count: int = -1
var _focus_frames: int = 0
var _selecting_reroll: bool = false
var _selection_hand_index: int = -1
var rule_dialog: AcceptDialog
var rule_mode_option: OptionButton
var random_count_spin: SpinBox
var rule_checkboxes: Dictionary = {}

@onready var money_label: Label = %MoneyLabel
@onready var round_delta_label: Label = %RoundDeltaLabel
@onready var current_bet_label: Label = %CurrentBetLabel
@onready var status_label: Label = %StatusLabel
@onready var dealer_cards: HFlowContainer = %DealerCards
@onready var dealer_total_label: Label = %DealerTotalLabel
@onready var player_total_label: Label = %PlayerTotalLabel
@onready var hands_grid: GridContainer = %HandsGrid
@onready var table_scroll: ScrollContainer = %TableScroll
@onready var bet_spin_box: SpinBox = %BetSpinBox
@onready var deal_button: Button = %DealButton
@onready var hit_button: Button = %HitButton
@onready var stand_button: Button = %StandButton
@onready var double_button: Button = %DoubleButton
@onready var split_button: Button = %SplitButton
@onready var restart_button: Button = %RestartButton
@onready var rules_button: Button = %RulesButton
@onready var reroll_button: Button = %RerollButton
@onready var second_chance_button: Button = %SecondChanceButton
@onready var active_rules_label: Label = %ActiveRulesLabel
@onready var keep_mystery_button: Button = %KeepMysteryButton
@onready var replace_mystery_button: Button = %ReplaceMysteryButton


## Create the engine, build UI styling/settings, and connect controls to action handlers.
func _ready() -> void:
	game = BlackjackGame.new()
	_build_theme()
	_build_rule_dialog()
	deal_button.pressed.connect(_on_deal_pressed)
	hit_button.pressed.connect(_on_hit_pressed)
	stand_button.pressed.connect(_on_stand_pressed)
	double_button.pressed.connect(_on_double_pressed)
	split_button.pressed.connect(_on_split_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	rules_button.pressed.connect(_on_rules_pressed)
	reroll_button.pressed.connect(_on_reroll_pressed)
	second_chance_button.pressed.connect(_on_second_chance_pressed)
	keep_mystery_button.pressed.connect(_on_mystery_choice.bind(false))
	replace_mystery_button.pressed.connect(_on_mystery_choice.bind(true))
	resized.connect(_apply_responsive_layout)
	set_process(false)
	_refresh_ui()


## Exit card selection, request a round at the entered wager, and refresh the view.
func _on_deal_pressed() -> void:
	_selecting_reroll = false
	game.start_round(bet_spin_box.value)
	_refresh_ui()


## Submit Hit to the engine and redraw its resulting state.
func _on_hit_pressed() -> void:
	_selecting_reroll = false
	game.player_hit()
	_refresh_ui()


## Submit Stand or the pending bust/payout decision, then redraw.
func _on_stand_pressed() -> void:
	_selecting_reroll = false
	game.player_stand()
	_refresh_ui()


## Request a matched-wager Double; the engine validates and finishes the action.
func _on_double_pressed() -> void:
	_selecting_reroll = false
	game.player_double()
	_refresh_ui()


## Request Split and rebuild hand panels to reflect the ordered hand list.
func _on_split_pressed() -> void:
	_selecting_reroll = false
	game.player_split()
	_refresh_ui()


## Start a fresh $100 session while preserving rule preferences and resetting UI selection.
func _on_restart_pressed() -> void:
	var settings := game.rules.get_configuration()
	game = BlackjackGame.new()
	game.configure_rules(settings.mode, settings.selected, settings.random_count)
	_selecting_reroll = false
	bet_spin_box.value = 10.0
	_last_active_hand = -1
	_refresh_ui()


## Enter or cancel card selection; selection alone never spends the Reroll allowance.
func _on_reroll_pressed() -> void:
	if _selecting_reroll:
		_selecting_reroll = false
	elif game.can_reroll():
		_selecting_reroll = true
		_selection_hand_index = game.player.active_hand_index
	_refresh_ui()


## Request removal of the recorded bust-causing card and display the new hand.
func _on_second_chance_pressed() -> void:
	_selecting_reroll = false
	game.player_second_chance()
	_refresh_ui()


## Submit Keep/Replace and immediately redraw the finalized, revealed opening hand.
func _on_mystery_choice(replace_card: bool) -> void:
	_selecting_reroll = false
	game.player_choose_mystery_card(replace_card)
	_refresh_ui()


## Accept mouse or Enter/Space selection on an eligible highlighted Reroll card.
func _on_card_gui_input(event: InputEvent, hand_index: int, card_index: int) -> void:
	var clicked: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	var confirmed: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	if clicked or confirmed:
		_choose_reroll_card(hand_index, card_index)
		get_viewport().set_input_as_handled()


## Ignore clicks from other hands, apply the chosen replacement, then exit selection.
func _choose_reroll_card(hand_index: int, card_index: int) -> void:
	if not _selecting_reroll or hand_index != game.player.active_hand_index or hand_index != _selection_hand_index:
		return
	game.player_reroll(card_index)
	_selecting_reroll = false
	_refresh_ui()


## Use Escape to cancel Reroll selection without consuming its use.
func _unhandled_key_input(event: InputEvent) -> void:
	if _selecting_reroll and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_selecting_reroll = false
		_refresh_ui()
		get_viewport().set_input_as_handled()


## Synchronize money, results, cards, prompts, and button eligibility from the engine.
## The opening choice uses separate controls; completed net results stay hidden during a new round.
func _refresh_ui() -> void:
	if not game.can_reroll() or game.player.active_hand_index != _selection_hand_index:
		_selecting_reroll = false
	money_label.text = "$%.2f" % game.player.money
	round_delta_label.visible = game.has_round_result and game.round_over
	round_delta_label.text = "Round: " + _money_delta(game.last_round_delta) if round_delta_label.visible else ""
	round_delta_label.add_theme_color_override("font_color", _delta_color(game.last_round_delta) if game.has_round_result else MUTED)
	current_bet_label.text = "$%.2f" % game.player.total_bet()
	status_label.text = _status_text()
	active_rules_label.text = _get_rules_text()
	dealer_total_label.text = _get_dealer_total_text()
	player_total_label.text = "All hands finished" if game.round_over else "Playing hand %d of %d" % [game.player.active_hand_index + 1, game.player.hands.size()]
	if game.player.hand.cards.is_empty():
		player_total_label.text = "Place a bet to begin"
	elif game.is_awaiting_mystery_card():
		player_total_label.text = "Choose your starting hand"

	_render_dealer_cards()
	_render_player_hands()
	var player_turn := game.is_player_turn()
	var can_deal := game.can_start_round()
	%MysteryActions.visible = game.is_awaiting_mystery_card()
	%ActionsGrid.visible = not game.is_awaiting_mystery_card()
	keep_mystery_button.disabled = not game.is_awaiting_mystery_card()
	replace_mystery_button.disabled = not game.can_replace_mystery_card()
	hit_button.disabled = not player_turn or _selecting_reroll
	stand_button.disabled = (not player_turn and not game.is_awaiting_second_chance()) or _selecting_reroll
	stand_button.text = "Accept Bust" if game.is_awaiting_second_chance() else "Stand"
	stand_button.tooltip_text = "Finish the current hand."
	if game.is_awaiting_second_chance() and game.is_double_target_match(game.player.hands[game.player.active_hand_index]):
		stand_button.text = "Take Payout"
		stand_button.tooltip_text = "Keep total %d. Return: $%.2f, including your $%.2f wager. This hand ends and Second Chance stays unused." % [game.get_double_target(), DoubleTargetRule.total_return(game.player.bet), game.player.bet]
	double_button.disabled = not game.can_double() or _selecting_reroll
	split_button.disabled = not game.can_split() or _selecting_reroll
	rules_button.disabled = not game.round_over
	reroll_button.visible = not game.round_over and game.rules.is_rule_active(&"reroll")
	reroll_button.disabled = not game.can_reroll()
	reroll_button.text = "Cancel" if _selecting_reroll else "Reroll"
	var reroll_rule := game.rules.get_rule(&"reroll") as RerollRule
	if not _selecting_reroll and reroll_rule.has_used(game.player):
		reroll_button.text = "Used"
	second_chance_button.visible = not game.round_over and game.rules.is_rule_active(&"second_chance")
	second_chance_button.disabled = not game.can_second_chance() or _selecting_reroll
	var second_chance_rule := game.rules.get_rule(&"second_chance") as SecondChanceRule
	second_chance_button.text = "Chance Used" if second_chance_rule.has_used(game.player) else "Second Chance"
	deal_button.disabled = not can_deal
	bet_spin_box.editable = can_deal
	if can_deal:
		bet_spin_box.max_value = max(BlackjackGame.MINIMUM_BET, game.player.money)
		bet_spin_box.value = min(bet_spin_box.value, bet_spin_box.max_value)
		deal_button.text = "Deal Cards"
	else:
		deal_button.text = "Playing Round"
	if game.round_over and game.player.money < BlackjackGame.MINIMUM_BET:
		status_label.text += " Restart to play again."
		deal_button.text = "No Funds"

	_apply_responsive_layout()
	# Follow a new split/turn after Godot has measured the hand panels.
	if player_turn and (_last_active_hand != game.player.active_hand_index or _last_hand_count != game.player.hands.size()):
		_request_hand_focus()
	_last_active_hand = game.player.active_hand_index
	_last_hand_count = game.player.hands.size()


## Prioritize pending decisions and card selection, then summarize normal or completed play.
func _status_text() -> String:
	if game.is_awaiting_mystery_card():
		return game.status_message
	if game.is_awaiting_second_chance():
		return game.status_message
	if _selecting_reroll:
		return "Choose a highlighted card to replace, or Cancel."
	if game.player.hand.cards.is_empty():
		return "Choose your wager, then deal the cards."
	if not game.round_over:
		if not game.last_rule_message.is_empty():
			return game.last_rule_message
		return "Your turn. Hit, Stand, Double, Split%s." % (", or Reroll" if game.can_reroll() else "")
	if game.player.hands.size() == 1 or game.result == BlackjackGame.RoundResult.NONE:
		var summary := game.status_message
		if game.player.hands[0].lucky_nine_bonus > 0.0:
			summary += " Lucky 9 bonus: %s." % _money_delta(game.player.hands[0].lucky_nine_bonus)
		return summary
	var wins := 0
	var losses := 0
	var pushes := 0
	for played_hand in game.player.hands:
		match played_hand.result:
			BlackjackGame.RoundResult.PLAYER_WIN, BlackjackGame.RoundResult.DEALER_BUST, BlackjackGame.RoundResult.PLAYER_BLACKJACK, BlackjackGame.RoundResult.DOUBLE_TARGET_WIN:
				wins += 1
			BlackjackGame.RoundResult.PUSH:
				pushes += 1
			_:
				losses += 1
	return "Round complete — %d won / %d lost / %d pushed. Deal to play again." % [wins, losses, pushes]


## Show the dealer opening card while concealing its hole card until round completion.
func _render_dealer_cards() -> void:
	_clear_children(dealer_cards)
	if game.dealer.hand.cards.is_empty():
		var placeholder := _label("Cards appear here after the deal.", 18, MUTED)
		placeholder.autowrap_mode = TextServer.AUTOWRAP_OFF
		dealer_cards.add_child(placeholder)
	for i in range(game.dealer.hand.cards.size()):
		dealer_cards.add_child(_card_tile(game.dealer.hand.cards[i], i == 1 and not game.round_over))


## Rebuild hand panels with active outlines, wagers, totals, bonuses, and card controls.
## Mystery Card conceals the second card and total; qualification is not displayed before the choice.
func _render_player_hands() -> void:
	_clear_children(hands_grid)
	hand_panels.clear()
	for i in range(game.player.hands.size()):
		var played_hand := game.player.hands[i]
		var active := (game.is_player_turn() or game.is_awaiting_second_chance() or game.is_awaiting_mystery_card()) and i == game.player.active_hand_index
		var panel := PanelContainer.new()
		panel.name = "Hand%d" % (i + 1)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.set_meta("active", active)
		panel.add_theme_stylebox_override("panel", _panel_style(PANEL, GOLD if active else BORDER, 3 if active else 1))
		hands_grid.add_child(panel)
		hand_panels.append(panel)
		var layout := VBoxContainer.new()
		layout.name = "HandLayout"
		layout.add_theme_constant_override("separation", 10)
		panel.add_child(layout)
		var heading := HBoxContainer.new()
		heading.add_theme_constant_override("separation", 12)
		layout.add_child(heading)
		var title := _label("HAND %d" % (i + 1), 20, INK)
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(title)
		var total_text := "Total: ?" if game.is_player_card_hidden(i, 1) else "Total: %d" % played_hand.hand.get_total()
		var total := _label(total_text, 24, GOLD if active else INK)
		total.autowrap_mode = TextServer.AUTOWRAP_OFF
		heading.add_child(total)
		var badge := _label(_hand_status(played_hand, active), 16, GOLD if active else MUTED)
		if game.round_over and played_hand.result != BlackjackGame.RoundResult.NONE:
			badge.text += "  " + _money_delta(played_hand.net_result)
			badge.add_theme_color_override("font_color", _delta_color(played_hand.net_result))
		badge.name = "HandStatus"
		if played_hand.lucky_nine_qualified:
			var bonus_text := "LUCKY 9 · %s bonus on a win" % _money_delta(LuckyNineRule.bonus_for_wager(played_hand.lucky_nine_base_wager))
			var bonus_color := GOLD
			if not game.round_over and played_hand.hand.is_bust():
				bonus_text = "LUCKY 9 · recover and win for %s bonus" % _money_delta(LuckyNineRule.bonus_for_wager(played_hand.lucky_nine_base_wager))
			if game.round_over:
				bonus_text = "LUCKY 9 BONUS · " + _money_delta(played_hand.lucky_nine_bonus) if played_hand.lucky_nine_bonus > 0.0 else "LUCKY 9 · no bonus this hand"
				bonus_color = GAIN if played_hand.lucky_nine_bonus > 0.0 else MUTED
			var bonus_label := _label(bonus_text, 14, bonus_color)
			bonus_label.name = "LuckyNineLabel"
			bonus_label.tooltip_text = "Opening total: 9. Winning bonus is 50% of the opening wager."
			layout.add_child(bonus_label)
		var cards := HFlowContainer.new()
		cards.name = "Cards"
		cards.add_theme_constant_override("h_separation", 10)
		cards.add_theme_constant_override("v_separation", 10)
		layout.add_child(cards)
		if played_hand.hand.cards.is_empty():
			var placeholder := _label("Ready for your first hand.", 20, MUTED)
			placeholder.autowrap_mode = TextServer.AUTOWRAP_OFF
			cards.add_child(placeholder)
		for card_index in range(played_hand.hand.cards.size()):
			var tile := _card_tile(played_hand.hand.cards[card_index], game.is_player_card_hidden(i, card_index))
			if active and _selecting_reroll:
				tile.mouse_filter = Control.MOUSE_FILTER_STOP
				tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				tile.focus_mode = Control.FOCUS_ALL
				tile.set_meta("reroll_selectable", true)
				tile.tooltip_text = "Replace " + played_hand.hand.cards[card_index].get_card_name()
				var style := tile.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
				style.border_color = GOLD
				style.set_border_width_all(3)
				tile.add_theme_stylebox_override("panel", style)
				tile.gui_input.connect(_on_card_gui_input.bind(i, card_index))
			cards.add_child(tile)
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		layout.add_child(spacer)
		var wager_text := "Wager: $%.2f" % played_hand.wager
		if played_hand.doubled:
			wager_text += "  •  Doubled"
		var details := HBoxContainer.new()
		details.name = "HandDetails"
		details.add_theme_constant_override("separation", 12)
		badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_child(badge)
		var wager_label := _label(wager_text, 16, MUTED)
		wager_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		details.add_child(wager_label)
		layout.add_child(details)
		layout.move_child(details, 1)


## Choose a badge for the opening choice, active turn, recovery, queued hand, or final result.
func _hand_status(played_hand: PlayerHand, active: bool) -> String:
	if played_hand.hand.cards.is_empty():
		return "WAITING FOR THE DEAL"
	if game.round_over:
		return game.get_hand_result_text(played_hand.result)
	if game.is_awaiting_mystery_card():
		return "KEEP OR REPLACE THE HIDDEN CARD"
	if game.is_awaiting_second_chance() and played_hand == game.player.hands[game.player.active_hand_index]:
		if game.is_double_target_match(played_hand):
			return "TARGET %d · recover or take payout" % game.get_double_target()
		return "BUST — Second Chance available"
	if active:
		return "YOUR TURN"
	if played_hand.hand.is_bust():
		if game.is_double_target_match(played_hand):
			return "TARGET %d · payout secured" % game.get_double_target()
		return "BUST — this hand is finished"
	if played_hand.is_standing:
		return "FINISHED — waiting for the dealer"
	return "UP NEXT"


## Build a scalable card face or generic hidden back; hidden tooltips expose no card identity.
func _card_tile(card: Card, is_hidden: bool = false) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(72, 88)
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	tile.set_meta("hidden", is_hidden)
	tile.tooltip_text = "Hidden Card" if is_hidden else card.get_card_name()
	var style := _panel_style(Color("244f43") if is_hidden else Color("f5f3e9"), Color("739286") if is_hidden else Color("d9dbc9"), 1, 8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	tile.add_theme_stylebox_override("panel", style)
	var labels := VBoxContainer.new()
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	labels.add_theme_constant_override("separation", 0)
	tile.add_child(labels)
	var red := card.suit == Card.Suit.HEARTS or card.suit == Card.Suit.DIAMONDS
	var color := Color("a12d43") if red else Color("172922")
	if is_hidden:
		labels.add_child(_centered_label("?", 36, GOLD))
		labels.add_child(_centered_label("HIDDEN", 12, INK))
	else:
		var rank := card.get_rank_name()
		if card.rank >= Card.Rank.JACK:
			rank = "A" if card.rank == Card.Rank.ACE else rank.left(1)
		labels.add_child(_centered_label(rank, 26, color))
		labels.add_child(_centered_label(["♥", "♦", "♣", "♠"][card.suit], 20, color))
		labels.add_child(_centered_label(card.get_suit_name().to_upper(), 9, color))
	_size_card_tile(tile)
	return tile


## Scale card size and type consistently with the current window width.
func _size_card_tile(tile: PanelContainer) -> void:
	var width := clampi(int(size.x / 16.0), 72, 108)
	tile.custom_minimum_size = Vector2(width, int(width * 1.23))
	var labels := tile.get_child(0)
	labels.get_child(0).add_theme_font_size_override("font_size", int(width * (0.46 if tile.get_meta("hidden") else 0.36)))
	labels.get_child(1).add_theme_font_size_override("font_size", int(width * (0.16 if tile.get_meta("hidden") else 0.28)))
	if not tile.get_meta("hidden"):
		labels.get_child(2).add_theme_font_size_override("font_size", int(width * 0.125))


## Display only the visible opening value while the dealer hole card is concealed.
func _get_dealer_total_text() -> String:
	if game.dealer.hand.cards.is_empty():
		return "Total: ?"
	if game.round_over:
		return "Total: %d" % game.dealer.hand.get_total()
	return "Showing: %d" % game.dealer.hand.cards[0].get_blackjack_value()


## Adapt margins, hand/action columns, card sizes, and rule summaries to the window.
## Center the settings dialog using explicit pixel truncation and keep the active hand in view.
func _apply_responsive_layout() -> void:
	if not is_node_ready():
		return
	# At the smallest width, ability buttons already show Used/Chance Used.
	# Keep all five rule names on one line so the hand total stays readable.
	active_rules_label.text = _get_rules_text()
	active_rules_label.tooltip_text = _get_rules_text(true)
	if rule_dialog.visible:
		rule_dialog.position = Vector2i(maxi(0, int((size.x - rule_dialog.size.x) / 2.0)), maxi(0, int((size.y - rule_dialog.size.y) / 2.0)))
	var narrow := size.x < 900.0
	%BetRow.visible = game.round_over
	$WindowMargin/Layout/Header/TitleGroup/Subtitle.visible = size.x >= 760.0
	$WindowMargin/Layout/Header/TitleGroup/Title.add_theme_font_size_override("font_size", 26 if size.x < 760.0 else 32)
	%Header.columns = 1 if narrow else 2
	%ControlsGrid.columns = 2 if game.round_over and size.x >= 1100.0 else 1
	var action_count := 4 + int(reroll_button.visible) + int(second_chance_button.visible)
	%ActionsGrid.columns = (3 if narrow else action_count) if action_count > 4 else (2 if size.x < 700.0 else 4)
	hands_grid.columns = 2 if size.x >= 900.0 and game.player.hands.size() > 1 else 1
	var margin := clampi(int(size.x * 0.025), 12, 40)
	%WindowMargin.add_theme_constant_override("margin_left", margin)
	%WindowMargin.add_theme_constant_override("margin_right", margin)
	%WindowMargin.add_theme_constant_override("margin_top", 16 if narrow else 20)
	%WindowMargin.add_theme_constant_override("margin_bottom", 16 if narrow else 20)
	for tile in dealer_cards.get_children():
		if tile is PanelContainer:
			_size_card_tile(tile)
	for panel in hand_panels:
		for tile in panel.get_node("HandLayout/Cards").get_children():
			if tile is PanelContainer:
				_size_card_tile(tile)
	if not game.player.hand.cards.is_empty():
		_request_hand_focus()


## Wait several layout frames before scrolling to the measured active hand.
func _request_hand_focus() -> void:
	_focus_frames = 3
	set_process(true)


## Complete the deferred focus request and stop processing until another layout change.
func _process(_delta: float) -> void:
	_focus_frames -= 1
	if _focus_frames <= 0:
		set_process(false)
		_focus_active_hand()


## Scroll the active panel or its first card row into view without double-applying offsets.
func _focus_active_hand() -> void:
	if not game.player.hand.cards.is_empty() and game.player.active_hand_index < hand_panels.size():
		var panel := hand_panels[game.player.active_hand_index]
		if panel.size.y > table_scroll.size.y:
			var area := table_scroll.get_global_rect()
			var offset := panel.get_global_rect().position.y - area.position.y
			var cards := panel.get_node("HandLayout/Cards")
			if cards.get_child_count() > 0:
				offset = maxf(offset, cards.get_child(0).get_global_rect().end.y - area.end.y)
			table_scroll.scroll_vertical += int(offset)
		else:
			table_scroll.ensure_control_visible(panel)


## Apply shared colors, typography, and button states for readable, consistent controls.
func _build_theme() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 20
	ui_theme.set_color("font_color", "Label", INK)
	ui_theme.set_font_size("font_size", "Button", 18)
	ui_theme.set_color("font_color", "Button", INK)
	ui_theme.set_color("font_disabled_color", "Button", Color("788e83"))
	ui_theme.set_stylebox("normal", "Button", _panel_style(Color("204c3e"), Color("48705b"), 1, 8))
	ui_theme.set_stylebox("hover", "Button", _panel_style(Color("32634d"), GOLD, 1, 8))
	ui_theme.set_stylebox("pressed", "Button", _panel_style(Color("14382c"), GOLD, 2, 8))
	ui_theme.set_stylebox("disabled", "Button", _panel_style(Color("152b24"), Color("294238"), 1, 8))
	var focus := _panel_style(Color(0, 0, 0, 0), GOLD, 2, 8)
	ui_theme.set_stylebox("focus", "Button", focus)
	ui_theme.set_font_size("font_size", "LineEdit", 20)
	ui_theme.set_color("font_color", "LineEdit", INK)
	ui_theme.set_stylebox("normal", "LineEdit", _panel_style(Color("10241e"), BORDER, 1, 8))
	ui_theme.set_stylebox("focus", "LineEdit", focus)
	theme = ui_theme
	%DealerPanel.add_theme_stylebox_override("panel", _panel_style(PANEL, BORDER))
	%StatusPanel.add_theme_stylebox_override("panel", _panel_style(Color("1b392d"), BORDER, 1, 8))
	deal_button.add_theme_stylebox_override("normal", _panel_style(GOLD, GOLD, 1, 8))
	deal_button.add_theme_stylebox_override("hover", _panel_style(Color("f1d38d"), GOLD, 1, 8))
	deal_button.add_theme_color_override("font_color", Color("1c2b21"))


## Create a reusable rounded panel/button style with explicit borders and padding.
func _panel_style(color: Color, border: Color, width: int = 1, radius: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


## Create wrapping text with a positive minimum width; parent containers supply its final width.
func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.custom_minimum_size.x = 1.0
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## Create nonwrapping, mouse-transparent rank/suit text inside a card tile.
func _centered_label(text: String, font_size: int, color: Color) -> Label:
	var label := _label(text, font_size, color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label


## Detach old generated controls before queuing them for deletion and rebuilding the view.
func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


## Describe actual active rules during play and saved preferences between rounds.
## A compact five-rule line keeps small-window totals visible; the tooltip retains full usage information.
func _get_rules_text(expanded: bool = false) -> String:
	if not game.round_over:
		if game.rules.active_rules.is_empty():
			return "THIS ROUND — Classic Blackjack"
		var active_rule_names: PackedStringArray = []
		for rule in game.rules.active_rules:
			var title := rule.display_name
			if (rule is RerollRule or rule is SecondChanceRule) and (expanded or size.x >= 760.0 or game.rules.active_rules.size() < 5):
				title += " · used" if rule.has_used(game.player) else " · ready"
			elif rule is DoubleTargetRule:
				title += ": %d" % rule.target_total
			active_rule_names.append(title)
		return "THIS ROUND — " + ", ".join(active_rule_names)
	var settings := game.rules.get_configuration()
	if settings.mode == RuleManager.RuleMode.OFF:
		return "NEXT ROUND — Classic · special rules off"
	var selected_rule_names: PackedStringArray = []
	for id in settings.selected:
		selected_rule_names.append(game.rules.get_rule(id).display_name)
	if selected_rule_names.is_empty():
		return "NEXT ROUND — Classic · no rules selected"
	var mode := "Random" if settings.mode == RuleManager.RuleMode.RANDOM_SELECTED else "Always active"
	return "NEXT ROUND — %s: %s" % [mode, ", ".join(selected_rule_names)]


## Format profit/loss with a sign, reserving an unsigned $0.00 for neutral outcomes.
func _money_delta(amount: float) -> String:
	if is_zero_approx(amount):
		return "$0.00"
	return ("+$%.2f" if amount > 0.0 else "−$%.2f") % absf(amount)


## Use green for profit, red for loss, and muted text for neutral results.
func _delta_color(amount: float) -> Color:
	return GAIN if amount > 0.0 else (LOSS if amount < 0.0 else MUTED)


## Build catalog-driven settings with stable checkbox/text bounds and a scrollable rule list.
func _build_rule_dialog() -> void:
	rule_dialog = AcceptDialog.new()
	rule_dialog.title = "Round Rules"
	rule_dialog.min_size = Vector2i(440, 340)
	rule_dialog.exclusive = true
	rule_dialog.get_ok_button().text = "Apply Rules"
	rule_dialog.add_cancel_button("Cancel")
	rule_dialog.confirmed.connect(_on_rules_confirmed)
	add_child(rule_dialog)
	var margin := MarginContainer.new()
	margin.custom_minimum_size.x = 480
	margin.size = Vector2(480, 320)
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	rule_dialog.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)
	var intro := _label("Choose rules for the next round. Settings lock while playing.", 16, MUTED)
	intro.max_lines_visible = 2
	intro.size.x = 460
	layout.add_child(intro)
	rule_mode_option = OptionButton.new()
	rule_mode_option.add_item("Off — Classic Blackjack", RuleManager.RuleMode.OFF)
	rule_mode_option.add_item("Selected rules — Always active", RuleManager.RuleMode.ALL_SELECTED)
	rule_mode_option.add_item("Selected rules — Random each round", RuleManager.RuleMode.RANDOM_SELECTED)
	rule_mode_option.item_selected.connect(_on_rule_mode_selected)
	layout.add_child(rule_mode_option)
	var random_row := HBoxContainer.new()
	random_row.add_theme_constant_override("separation", 12)
	layout.add_child(random_row)
	var random_label := _label("Rules per random round", 16, INK)
	random_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	random_row.add_child(random_label)
	random_count_spin = SpinBox.new()
	random_count_spin.custom_minimum_size.x = 80
	random_count_spin.min_value = 1
	random_count_spin.max_value = maxi(1, game.rules.get_catalog().size())
	random_count_spin.value = 1
	random_row.add_child(random_count_spin)
	layout.add_child(HSeparator.new())
	var rules_scroll := ScrollContainer.new()
	rules_scroll.custom_minimum_size.y = 180
	rules_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rules_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(rules_scroll)
	var rule_list := VBoxContainer.new()
	rule_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule_list.add_theme_constant_override("separation", 8)
	rules_scroll.add_child(rule_list)
	for rule in game.rules.get_catalog():
		# The icon and text have separate bounds, so toggling/focus styles cannot
		# move the rule name into the checkmark.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		rule_list.add_child(row)
		var checkbox := CheckBox.new()
		checkbox.custom_minimum_size = Vector2(36, 36)
		checkbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		checkbox.tooltip_text = rule.display_name + ": " + rule.description
		var checkbox_style := StyleBoxFlat.new()
		checkbox_style.bg_color = Color(0, 0, 0, 0)
		checkbox_style.content_margin_left = 6
		checkbox_style.content_margin_right = 6
		checkbox_style.content_margin_top = 6
		checkbox_style.content_margin_bottom = 6
		for state_name in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			checkbox.add_theme_stylebox_override(state_name, checkbox_style)
		checkbox.add_theme_stylebox_override("focus", _panel_style(Color(0, 0, 0, 0), GOLD, 1, 4))
		rule_checkboxes[rule.rule_id] = checkbox
		row.add_child(checkbox)
		var text_group := VBoxContainer.new()
		text_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_group)
		var title := _label(rule.display_name, 18, INK)
		title.custom_minimum_size.y = 36
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.mouse_filter = Control.MOUSE_FILTER_STOP
		title.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		title.gui_input.connect(_on_rule_title_input.bind(checkbox))
		text_group.add_child(title)
		var details := _label(rule.short_description, 14, MUTED)
		details.max_lines_visible = 4
		details.size.x = 400
		text_group.add_child(details)
	var note := _label("Random picks from checked rules each round.", 14, MUTED)
	note.max_lines_visible = 2
	note.size.x = 460
	layout.add_child(note)


## Let clicking the separate title toggle its checkbox without moving text into the icon.
func _on_rule_title_input(event: InputEvent, checkbox: CheckBox) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		checkbox.button_pressed = not checkbox.button_pressed
		checkbox.get_viewport().set_input_as_handled()


## Restore saved preferences into the dialog so Cancel never changes engine settings.
func _populate_rule_settings() -> void:
	var settings := game.rules.get_configuration()
	rule_mode_option.select(settings.mode)
	random_count_spin.value = settings.random_count
	for id in rule_checkboxes:
		rule_checkboxes[id].button_pressed = settings.selected.has(id)
	_on_rule_mode_selected(rule_mode_option.selected)


## Open editable settings between rounds only, clamped to the available window size.
func _on_rules_pressed() -> void:
	if not game.round_over:
		return
	_populate_rule_settings()
	rule_dialog.popup_centered_clamped(Vector2i(540, 420), 0.9)


## Enable the rule-count control only when Random mode is selected.
func _on_rule_mode_selected(_index: int) -> void:
	random_count_spin.editable = rule_mode_option.get_selected_id() == RuleManager.RuleMode.RANDOM_SELECTED


## Collect checked IDs, commit validated next-round preferences, and refresh the summary.
func _on_rules_confirmed() -> void:
	var selected: Array[StringName] = []
	for id in rule_checkboxes:
		if rule_checkboxes[id].button_pressed:
			selected.append(id)
	game.configure_rules(rule_mode_option.get_selected_id(), selected, int(random_count_spin.value))
	_refresh_ui()
