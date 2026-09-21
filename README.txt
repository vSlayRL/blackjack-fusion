# Blackjack Fusion

## Overview

Blackjack Fusion is a Godot 4.7 project that is being built in iterations. The long-term goal is a 3D social Blackjack game. The current iteration intentionally focuses on a small, dependable Blackjack rules engine and a temporary 2D interface for proving that the game is playable.

Current scope:

* One player versus the dealer
* Standard 52-card deck
* Betting and bankroll
* Hit and stand
* Ace handling
* Natural Blackjack
* Dealer hits below 17 and stands on 17 or higher
* Player/dealer busts
* Wins, losses, and pushes
* 3:2 Blackjack payout
* No splitting
* No doubling down
* No multiplayer yet
* No 3D presentation yet

---

## Run the Project

Open `project.godot` in Godot 4.7.x and press **F5**.

The main project scene is:

```text
scenes/main.tscn
```

It loads the temporary playable interface from:

```text
scenes/game.tscn
```

The logic test scene is:

```text
scenes/tests.tscn
```

Run that scene with **F6** when you want to verify the Blackjack rules without the UI.

---

## Current Project Structure

```text
blackjack-fusion/
├── project.godot
├── README.txt
├── assets/
├── scenes/
│   ├── main.tscn
│   ├── game.tscn
│   └── tests.tscn
└── scripts/
    ├── blackjack_game.gd
    ├── card.gd
    ├── dealer.gd
    ├── deck.gd
    ├── hand.gd
    ├── player.gd
    ├── tests.gd
    └── ui/
        └── game_ui.gd
```

---

## Script Responsibilities

### `card.gd`
Represents one playing card. Stores rank and suit and provides the card's Blackjack value and display name.

### `deck.gd`
Creates, shuffles, deals, and resets the standard 52-card deck.

### `hand.gd`
Stores cards belonging to a player/dealer and calculates the hand total. It also handles flexible Ace values, Blackjack, 21, and bust checks.

### `player.gd`
Stores the player's bankroll, current bet, and hand. It handles placing bets and the win/loss/push/Blackjack payouts.

### `dealer.gd`
Stores the dealer's hand and applies the current dealer rule: hit below 17 and stand on 17 or higher.

### `blackjack_game.gd`
The central game controller. It owns the deck, player, and dealer and controls round state:

```text
Waiting for Bet
      ↓
Initial Deal
      ↓
Player Turn
      ↓
Dealer Turn
      ↓
Resolve Result
      ↓
Round Over
```

This script contains the Blackjack game flow but does not contain UI or 3D presentation code.

### `ui/game_ui.gd`
Temporary playable interface controller. Button presses call the public functions in `BlackjackGame`, then the interface refreshes from the resulting game state.

The UI does not decide Blackjack rules. That separation is intentional so the same game logic can later power 3D cards, animations, and table interactions.

### `tests.gd`
Automated logic checks for cards, hands, deck behavior, betting, busts, dealer behavior, payouts, pushes, and complete rounds.

---

## Temporary Playable Interface

The current UI is deliberately simple. It exists so the team can demonstrate and manually play the game logic before any 3D work begins.

Controls:

* **Bet Amount** - choose a wager before the round begins.
* **Deal Cards** - starts a new round.
* **Hit** - draws another player card.
* **Stand** - ends the player turn and lets the dealer finish automatically.
* **Restart Game** - resets the bankroll and starts a fresh game session.

The dealer's second card remains hidden during the player's turn and is revealed when the round ends.

---

## Why the Logic Is Separate from the UI

The project is structured so future presentation code does not need to rewrite Blackjack rules.

Current version:

```text
Button Press
    ↓
BlackjackGame
    ↓
Game State Changes
    ↓
Text UI Refreshes
```

Future 3D version:

```text
3D Table Interaction
    ↓
BlackjackGame
    ↓
Game State Changes
    ↓
Card Models / Animations / HUD Refresh
```

This lets the team replace the temporary interface later while keeping the tested game engine.

---

## Future Work

Future iterations may add:

* 3D blackjack table
* 3D card models and card animations
* Player avatars/seating
* Multiplayer/networking
* Sound and visual feedback
* Menus and game settings

Those features are intentionally outside the current logic-focused iteration.
