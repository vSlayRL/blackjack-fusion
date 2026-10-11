class_name TableCard3D
extends Node3D
## One physical card view. Only the engine decides identity, concealment, or Reroll eligibility.

var source_card: Card
var concealed: bool = true
var selectable: bool = false
var hand_index: int = -1
var card_index: int = -1
var _motion: Tween

@onready var face: Node3D = $Face
@onready var rank_label: Label3D = $Face/Rank
@onready var suit_label: Label3D = $Face/Suit
@onready var outline: MeshInstance3D = $SelectionOutline
@onready var body: StaticBody3D = $PickBody


## Move dealt/replaced cards from the shoe and flip only when concealment changes.
func present(card: Card, is_concealed: bool, can_select: bool, target: Vector3, card_scale: float, shoe: Vector3, delay: float) -> void:
	var changed := source_card != card
	var revealed := concealed and not is_concealed and not changed
	if _motion != null and _motion.is_running():
		_motion.kill()
	source_card = card
	concealed = is_concealed
	face.visible = not concealed
	# Do not put a hidden card's rank or suit in any displayed label.
	rank_label.text = ""
	suit_label.text = ""
	if not concealed:
		var rank := card.get_rank_name()
		if card.rank >= Card.Rank.JACK:
			rank = {Card.Rank.JACK: "J", Card.Rank.QUEEN: "Q", Card.Rank.KING: "K", Card.Rank.ACE: "A"}[card.rank]
		var suit: String = ["♥", "♦", "♣", "♠"][card.suit]
		rank_label.text = rank + suit
		suit_label.text = suit
		var ink := Color("c7354e") if card.suit in [Card.Suit.HEARTS, Card.Suit.DIAMONDS] else Color("132c42")
		rank_label.modulate = ink
		suit_label.modulate = ink
	set_selectable(can_select)
	if changed:
		position = shoe
		scale = Vector3.ONE * card_scale * 0.6
		rotation.z = PI if concealed else 0.0
		_motion = create_tween().set_parallel(true)
		_motion.tween_property(self, "position", target, 0.22).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_motion.tween_property(self, "scale", Vector3.ONE * card_scale, 0.22).set_delay(delay)
	else:
		position = target
		scale = Vector3.ONE * card_scale
		if revealed:
			_motion = create_tween()
			_motion.tween_property(self, "rotation:z", 0.0, 0.24).set_trans(Tween.TRANS_SINE)
		else:
			rotation.z = PI if concealed else 0.0


## Restrict physics picking to the active, gold-outlined Reroll cards.
func set_selectable(can_select: bool) -> void:
	selectable = can_select
	outline.visible = can_select
	body.collision_layer = 2 if can_select else 0


## Brighten the selectable card under the cursor without changing gameplay state.
func set_hovered(hovered: bool) -> void:
	outline.scale = Vector3(1.045, 1.0, 1.045) if hovered and selectable else Vector3.ONE
