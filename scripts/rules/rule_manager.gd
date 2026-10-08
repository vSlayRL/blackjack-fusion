## Registers rules, stores next-round preferences, and selects active rules.
## Rule selection and individual rule usage are separate: inactive rules are reset every accepted round.
class_name RuleManager
extends RefCounted

enum RuleMode { OFF, ALL_SELECTED, RANDOM_SELECTED }

var rule_mode: RuleMode = RuleMode.OFF
var random_rule_count: int = 1
var selected_rule_ids: Array[StringName] = [&"reroll"]
var active_rules: Array[SpecialRule] = []
var _catalog: Array[SpecialRule] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Register the five supported rules and initialize random selection independently of the deck.
func _init() -> void:
	_rng.randomize()
	register_rule(RerollRule.new())
	register_rule(SecondChanceRule.new())
	register_rule(LuckyNineRule.new())
	register_rule(DoubleTargetRule.new())
	register_rule(MysteryCardRule.new())


## Add a nonempty unique ID; return false rather than overwrite an existing rule.
func register_rule(rule: SpecialRule) -> bool:
	if rule == null or rule.rule_id == &"" or get_rule(rule.rule_id) != null:
		return false
	_catalog.append(rule)
	return true


## Return a copied catalog array for UI construction; its rule objects are shared.
func get_catalog() -> Array[SpecialRule]:
	return _catalog.duplicate()


## Find the registered rule by stable ID, returning null for an unknown ID.
func get_rule(id: StringName) -> SpecialRule:
	for rule in _catalog:
		if rule.rule_id == id:
			return rule
	return null


## Validate and store the next-round mode, unique selected IDs, and positive random count.
func configure(mode: int, selected: Array[StringName], random_count: int = 1) -> bool:
	if mode < RuleMode.OFF or mode > RuleMode.RANDOM_SELECTED or random_count < 1:
		return false
	var unique_ids: Array[StringName] = []
	for id in selected:
		if get_rule(id) == null:
			return false
		if not unique_ids.has(id):
			unique_ids.append(id)
	rule_mode = mode as RuleMode
	selected_rule_ids = unique_ids
	random_rule_count = random_count
	return true


## Expose preferences with a copy of selected IDs, for the dialog and Restart.
func get_configuration() -> Dictionary:
	return {"mode": rule_mode, "selected": selected_rule_ids.duplicate(), "random_count": random_rule_count}


## Reset all rules, then activate every selected rule or a uniformly shuffled subset.
## Clamp the random count to available rules; repeat selections across rounds are allowed.
func prepare_round() -> void:
	active_rules.clear()
	var available: Array[SpecialRule] = []
	for rule in _catalog:
		rule.deactivate()
		rule.reset_round()
		if selected_rule_ids.has(rule.rule_id):
			available.append(rule)
	if rule_mode == RuleMode.OFF:
		return
	if rule_mode == RuleMode.RANDOM_SELECTED:
		# Shuffle only selected rules; select each rule at most once.
		for i in range(available.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var saved := available[i]
			available[i] = available[j]
			available[j] = saved
		available.resize(mini(random_rule_count, available.size()))
	for rule in available:
		rule.activate()
		active_rules.append(rule)


## Check the actual round selection rather than the next-round checkbox preferences.
func is_rule_active(id: StringName) -> bool:
	for rule in active_rules:
		if rule.rule_id == id:
			return true
	return false


## Send the temporary context to active rules implementing the requested lifecycle hook.
func dispatch(event: StringName, context: Dictionary) -> void:
	for rule in active_rules:
		match event:
			&"round_started":
				rule.on_round_started(context)
			&"opening_dealt":
				rule.on_opening_dealt(context)
			&"hand_changed":
				rule.on_hand_changed(context)
			&"before_settlement":
				rule.before_settlement(context)
			&"round_finished":
				rule.on_round_finished(context)
