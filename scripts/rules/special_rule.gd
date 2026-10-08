class_name SpecialRule
extends RefCounted

# Stable IDs connect rules to settings; names/descriptions are for the UI.
var rule_id: StringName
var display_name: String
var description: String
var short_description: String
var active: bool = false


func _init(id: StringName = &"", title: String = "Special Rule", details: String = "", summary: String = "") -> void:
	rule_id = id
	display_name = title
	description = details
	short_description = details if summary.is_empty() else summary


func activate() -> void:
	active = true


func deactivate() -> void:
	active = false


func reset_round() -> void:
	pass


# Subclasses can react at these points without placing their behavior in UI.
# Context is temporary; rules should not retain a reference to the game.
func on_round_started(_context: Dictionary) -> void:
	pass


func on_opening_dealt(_context: Dictionary) -> void:
	pass


func on_hand_changed(_context: Dictionary) -> void:
	pass


func before_settlement(_context: Dictionary) -> void:
	pass


func on_round_finished(_context: Dictionary) -> void:
	pass
