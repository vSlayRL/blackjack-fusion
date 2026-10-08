## Common interface for optional rules, independent of scene nodes.
## Lifecycle contexts are temporary; retaining the game reference would create ownership cycles.
class_name SpecialRule
extends RefCounted

# Stable IDs connect rules to settings; names/descriptions are for the UI.
var rule_id: StringName
var display_name: String
var description: String
var short_description: String
var active: bool = false


## Set the stable rule ID, full explanation, and compact settings description.
func _init(id: StringName = &"", title: String = "Special Rule", details: String = "", summary: String = "") -> void:
	rule_id = id
	display_name = title
	description = details
	short_description = details if summary.is_empty() else summary


## Enable this rule for the selected round.
func activate() -> void:
	active = true


## Remove active status before the manager selects the next round rules.
func deactivate() -> void:
	active = false


## Override to clear per-round usage or target state; the base has none.
func reset_round() -> void:
	pass


# Subclasses can react at these points without placing their behavior in UI.
# Context is temporary; rules should not retain a reference to the game.
## Hook after wager acceptance and rule selection, before the opening cards are dealt.
func on_round_started(_context: Dictionary) -> void:
	pass


## Hook for a playable finalized opening, after Mystery Card and natural Blackjack checks.
func on_opening_dealt(_context: Dictionary) -> void:
	pass


## Hook after Hit, Double, Split, Reroll, or Second Chance changes player cards.
func on_hand_changed(_context: Dictionary) -> void:
	pass


## Hook to compute rule contributions after outcomes are assigned, before money is paid.
func before_settlement(_context: Dictionary) -> void:
	pass


## Hook after settlement or cancellation and final net-result recording.
func on_round_finished(_context: Dictionary) -> void:
	pass
