class_name MysteryCardRule
extends SpecialRule

# The opening choice belongs to the round, never to newly split hands.
var resolved: bool = false
var replaced: bool = false


func _init() -> void:
	super(&"mystery_card", "Mystery Card", "Hide your second starting card and total. Keep it, or discard it for this round and draw one revealed replacement. Your final two cards form the opening hand for Blackjack (3:2) and Lucky 9. Choose once per round before normal actions; this does not spend Reroll or Second Chance.", "Opening choice: keep the hidden card or replace it once. Final cards determine Blackjack and Lucky 9.")


func reset_round() -> void:
	resolved = false
	replaced = false


func apply(player: Player, deck: Deck, replace_card: bool) -> bool:
	if not active or resolved or player.hands.size() != 1 or player.hand.card_count() != 2:
		return false
	if replace_card:
		var replacement := deck.deal_card()
		if replacement == null:
			return false
		# Do not return the discarded card to the shoe or flag this as Reroll.
		player.hand.cards[1] = replacement
	resolved = true
	replaced = replace_card
	return true
