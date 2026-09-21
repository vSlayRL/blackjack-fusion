class_name Card
extends Resource


enum Suit {
	HEARTS,
	DIAMONDS,
	CLUBS,
	SPADES
}

enum Rank {
	TWO = 2,
	THREE = 3,
	FOUR = 4,
	FIVE = 5,
	SIX = 6,
	SEVEN = 7,
	EIGHT = 8,
	NINE = 9,
	TEN = 10,
	JACK = 11,
	QUEEN = 12,
	KING = 13,
	ACE = 14
}

var suit: Suit
var rank: Rank


func _init(card_suit: Suit = Suit.HEARTS, card_rank: Rank = Rank.TWO):
	suit = card_suit
	rank = card_rank


func get_blackjack_value() -> int:
	if rank == Rank.ACE:
		return 11

	if rank >= Rank.TEN:
		return 10

	return int(rank)


func get_rank_name() -> String:
	match rank:
		Rank.TWO:
			return "2"
		Rank.THREE:
			return "3"
		Rank.FOUR:
			return "4"
		Rank.FIVE:
			return "5"
		Rank.SIX:
			return "6"
		Rank.SEVEN:
			return "7"
		Rank.EIGHT:
			return "8"
		Rank.NINE:
			return "9"
		Rank.TEN:
			return "10"
		Rank.JACK:
			return "Jack"
		Rank.QUEEN:
			return "Queen"
		Rank.KING:
			return "King"
		Rank.ACE:
			return "Ace"

	return "Unknown"


func get_suit_name() -> String:
	match suit:
		Suit.HEARTS:
			return "Hearts"
		Suit.DIAMONDS:
			return "Diamonds"
		Suit.CLUBS:
			return "Clubs"
		Suit.SPADES:
			return "Spades"

	return "Unknown"


func get_card_name() -> String:
	return get_rank_name() + " of " + get_suit_name()
