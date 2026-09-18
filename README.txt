# Blackjack Fusion

## Overview

**Blackjack Fusion** is a casual 3D multiplayer blackjack game designed around playing blackjack with friends.

The goal of the project is to create a simple, approachable blackjack experience where players can play against the dealer while keeping the game social and easy to understand.

The project is being developed using the **Godot Engine** and **GDScript**.

---

## Project Goals

The main goals of Blackjack Fusion are:

* Create a functional game of blackjack.
* Provide a 3D environment for the game.
* Allow multiple players to participate in a game.
* Implement standard blackjack rules and game flow.
* Keep the game simple and accessible for players.
* Use object-oriented programming principles throughout the project.

---

## Technology

* **Game Engine:** Godot 4.7.2
* **Programming Language:** GDScript
* **Game Type:** 3D Multiplayer / Social Blackjack
* **Version Control:** Git / GitHub

---

# Project Structure

The project separates the blackjack system into multiple GDScript files. Each script has a specific responsibility so that the entire game does not have to be controlled by one large script.

```text
Blackjack Fusion/
│
├── main.tscn
├── game.tscn
│
├── blackjack_game.gd
├── card.gd
├── deck.gd
├── dealer.gd
├── hand.gd
└── player.gd
```

---

# GDScript Responsibilities

## `card.gd`

**Purpose:** Represents an individual playing card.

The `Card` class will contain the information needed to identify a card, such as:

* Rank
* Suit
* Value

Examples of cards include:

```text
Ace of Spades
King of Hearts
7 of Diamonds
```

The card script focuses on the **data and properties of an individual card**.

---

## `deck.gd`

**Purpose:** Manages the deck of playing cards.

The `Deck` class will be responsible for:

* Creating a standard 52-card deck
* Storing the available cards
* Shuffling the deck
* Dealing cards
* Tracking cards that have already been dealt
* Resetting the deck for a new round

The general process is:

```text
Create 52 Cards
      ↓
Shuffle Deck
      ↓
Deal Cards
      ↓
Cards are removed from available deck
      ↓
Round Ends
      ↓
Reset / Rebuild Deck
      ↓
Shuffle
      ↓
New Round
```

---

## `hand.gd`

**Purpose:** Represents the cards currently held by a player or dealer.

The `Hand` class will handle operations such as:

* Adding cards
* Removing/clearing cards
* Calculating the hand's blackjack value
* Checking for blackjack
* Checking for a bust

Both players and the dealer can have their own `Hand`.

For example:

```text
Player
  └── Hand
       ├── Card
       └── Card
```

---

## `player.gd`

**Purpose:** Represents an individual player.

The `Player` class will contain information and functionality related to a player, including:

* Player name
* Money/balance
* Current bet
* Current hand
* Player actions

A player's basic structure can be thought of as:

```text
Player
├── Name
├── Money
├── Bet
└── Hand
```

---

## `dealer.gd`

**Purpose:** Represents the blackjack dealer.

The `Dealer` class will manage the dealer's blackjack-specific behavior.

This includes:

* The dealer's hand
* Drawing cards
* Following the dealer's blackjack rules
* Checking the dealer's final hand value
* Determining when the dealer's turn is finished

The dealer's turn occurs after the players have completed their turns.

---

## `blackjack_game.gd`

**Purpose:** Controls the overall blackjack game and round flow.

This is the central script responsible for connecting the other blackjack classes together.

It will manage the overall sequence of a round:

```text
Betting
   ↓
Initial Deal
   ↓
Player Turn
   ↓
Dealer Turn
   ↓
Determine Results
   ↓
Update Money
   ↓
End Round
   ↓
Start New Round
```

`blackjack_game.gd` should coordinate the game rather than containing every piece of functionality itself.

For example, the game controller can tell the `Deck` to deal a card and then give that card to a player's `Hand`.

---

# Game Flow

A typical blackjack round will follow this general structure:

### 1. Betting

Players place their bets before cards are dealt.

### 2. Initial Deal

Players and the dealer receive their starting cards.

### 3. Player Turns

Players can perform standard blackjack actions such as:

* Hit
* Stand

Additional actions may be added as the project develops.

### 4. Dealer Turn

After the players finish, the dealer plays according to the game's blackjack rules.

### 5. Determine Results

The game compares the players' hands against the dealer's hand.

Possible results include:

* Player wins
* Dealer wins
* Push/tie
* Blackjack
* Bust

### 6. Update Player Money

The player's balance is updated based on the result of the round.

### 7. Reset

Once the round is complete:

```text
Player Hands → Cleared
Dealer Hand → Cleared
Deck → Reset
Deck → Shuffled
```

The next round can then begin.

---

# Object-Oriented Design

The project is divided into separate classes so that each class has a specific responsibility.

A simplified relationship between the classes is:

```text
              BlackjackGame
                    │
        ┌───────────┼───────────┐
        ↓           ↓           ↓
      Deck       Player       Dealer
                   │            │
                   ↓            ↓
                 Hand         Hand
                   │            │
                   └─────┬──────┘
                         ↓
                       Card
```

This structure allows different parts of the game to be developed and tested independently.

For example, the deck should be responsible for dealing cards, while the hand should be responsible for calculating the value of those cards.

---

# Scenes

## `main.tscn`

The main entry point for the project.

This scene will be responsible for starting the game and loading the appropriate game environment.

## `game.tscn`

The primary game scene where the blackjack table and gameplay environment will be located.

The exact scene structure may change as development continues.

---

# Multiplayer

Blackjack Fusion is intended to support multiple players playing together.

The multiplayer portion of the project will build on top of the core blackjack system.

The blackjack logic is being kept separate from the visual/gameplay scenes so that the underlying rules can be managed independently from the 3D environment and multiplayer functionality.

---

# Development Notes

The project is currently under development. Some features described in this README represent the intended structure and functionality of the game and may change as development continues.

When adding new functionality, try to keep each script focused on its intended responsibility rather than placing unrelated logic into `blackjack_game.gd`.

For example:

```text
Card information       → card.gd
Deck management        → deck.gd
Hand calculations      → hand.gd
Player information     → player.gd
Dealer behavior        → dealer.gd
Game/round flow        → blackjack_game.gd
3D presentation        → Godot scenes
```

This makes the project easier for group members to understand, debug, and expand.

---

# Current Development Philosophy

The project is being developed incrementally.

The initial focus is on getting the **core blackjack functionality** working correctly before expanding into more advanced visual, multiplayer, and presentation features.

The intended progression is:

```text
Core Blackjack Logic
        ↓
Player / Dealer System
        ↓
Round Management
        ↓
3D Game Environment
        ↓
Multiplayer Features
        ↓
Additional Gameplay / Presentation Features
```

The final implementation may differ from this planned structure as development progresses.
