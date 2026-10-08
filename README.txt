# Blackjack Fusion

## Overview

Blackjack Fusion is a Godot 4.7 project that is being built in iterations. The long-term goal is a 3D social Blackjack game. The current iteration intentionally focuses on a small, dependable Blackjack rules engine and a temporary 2D interface for proving that the game is playable.

Current scope:

* One player versus the dealer
* Standard 52-card deck
* Betting and bankroll
* Hit, stand, double down, and split
* Ace handling
* Natural Blackjack
* Dealer hits below 17 and stands on 17 or higher
* Player/dealer busts
* Wins, losses, and pushes
* 3:2 Blackjack payout
* Re-splitting up to four hands
* Doubling after a split
* Split-Ace restrictions and per-hand payouts
* Optional Reroll and Second Chance, each with one shared use across split hands per round
* Lucky 9 bonus for a winning hand that opened with a two-card total of 9
* Double Target: a random announced bust total from 22–30 with a small exact-match payout
* Mystery Card: keep or replace one hidden starting card before Blackjack and Lucky 9 checks
* Green/red net winnings and losses, including per-hand results
* Pre-round rule settings: Off, Always Active, or Random
* A modular special-rule registry and gameplay hooks
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
    ├── player_hand.gd
    ├── tests.gd
    ├── rules/
    │   ├── special_rule.gd
    │   ├── rule_manager.gd
    │   ├── reroll_rule.gd
    │   ├── second_chance_rule.gd
    │   ├── lucky_nine_rule.gd
    │   ├── double_target_rule.gd
    │   └── mystery_card_rule.gd
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
Stores the player's shared bankroll, list of hands, and active hand index. It handles betting and the win/loss/push/Blackjack payouts. The original hand, bet, and is_standing properties refer to the active hand for compatibility. total_bet() returns every outstanding wager.

### `player_hand.gd`
Stores the cards, wager, turn state, split/Ace flags, doubled/rerolled/rescued flags, result, net gain/loss, and Lucky 9 qualification/bonus for one player hand. Each split hand has its own state while sharing the player bankroll.

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
Automated logic and UI checks for cards, hands, deck behavior, betting, busts, dealer behavior, payouts, pushes, and complete rounds. Deterministic story-style scenarios cover Double, Split, mixed outcomes, re-splits, split Aces, card shortages, and real UI button signals. Reroll scenarios additionally check shared use across splits, bust/21 outcomes, Double/Split interactions, reset, settings locks, lifecycle hooks, actual card input, and responsive controls. Second Chance scenarios cover bust recovery/decline, shared split usage, rescued Double, combinations with Reroll, random selection, and next-round reset. Net-result checks cover ordinary wins/losses, Blackjack, Double, splits, push, and refunds. UI checks cover the bust decision, colored amounts, six-action layouts, and checked/unchecked/focused checkbox bounds. Lucky 9 scenarios cover opening qualification, bonus payouts, Double, Reroll, Second Chance, Split, cents rounding, non-winning outcomes, Random selection, labels, and clearing results after the next deal. Double Target scenarios cover every target 22–30, fixed targets throughout a round, misses, automatic/kept payouts, Second Chance recovery, doubled wagers, independent split payouts, Reroll, Lucky 9 exclusion, Ace handling, natural Blackjack, refunds, next-round target draws, and UI recovery/payout choices. Mystery Card scenarios cover hidden opening choices, 3:2 Blackjack for kept/replaced cards, double Blackjack pushes, delayed dealer priority, final Lucky 9 qualification, later rule combinations, discard/reset, empty decks, Random selection, real UI input, concealment, and five-rule responsive layouts. Headless tests exit with a failing code if any expectation fails.

---

## Temporary Playable Interface

The current UI is deliberately simple. It exists so the team can demonstrate and manually play the game logic before any 3D work begins.

Controls:

* **Bet Amount** - choose a wager before the round begins.
* **Deal Cards** - starts a new round.
* **Hit** - draws another player card.
* **Stand** - finishes the current hand. After all split hands finish, the dealer plays automatically.
* **Double** - adds a matching wager, draws exactly one card, and finishes the current hand.
* **Split** - separates equal-value cards into two hands and adds a matching wager.
* **Restart** - resets the bankroll and starts a fresh game session while retaining the selected rule settings.
* **Rules** - configures special rules between rounds.
* **Reroll** - when active, highlights cards in your current hand; click one to replace it. **Cancel** or **Escape** exits selection without spending the ability.
* **Second Chance** - available when your active hand busts, if this rule is active and unused. Removes the bust-causing card. **Accept Bust** declines recovery and finishes the hand; **Take Payout** appears instead when the bust matches Double Target.
* **Double Target** - automatic when active. The status area announces the target before player actions. An exact matching bust pays the small return; it has no separate action button.

The dealer's second card remains hidden during the player's turn and is revealed when the round ends. Split hands show their cards, totals, wagers, and current turn. Double and Split are disabled when unavailable. The interface fills the window and rearranges its controls as the window changes size. Cards are shown as individual high-contrast tiles with ranks and suits. Each hand has a separate panel with a large total, wager, and result. A gold outline marks the active hand. The card/results area scrolls for longer rounds; bankroll, status, and action controls stay visible. Split hands appear in two columns on wider windows and one column on narrower windows. Cards grow on larger windows. Small windows automatically bring the active hand into view. The wager controls appear between rounds, while the play controls stay at the bottom during a hand. The window can be resized down to 640 x 560.

## Double and Split Rules

* Double is allowed on any initial two-card hand, including after a split, if the player can afford another full wager. It draws one card and ends that hand, whether it busts or survives. After hitting, Double is unavailable.
* Split is allowed on two cards with the same Blackjack value (including 10 + King). The second hand requires the same wager. The player must have enough money and the deck must have two replacement cards.
* Non-Ace hands can be re-split, up to four total hands. Newly created hands are inserted immediately after the current hand and played in order.
* Split Aces receive exactly one additional card each and automatically stand. They cannot be hit, doubled, or re-split.
* Any 21 after splitting is a regular 21, pays 1:1 on a win, and automatically finishes the hand. Only an unsplit opening Blackjack pays 3:2.
* Each hand settles separately against the same dealer hand. A bust on one hand does not end other hands. The dealer draws only after every hand finishes, and skips drawing when all hands bust.
* Dealer stands on all 17s, including soft 17. Opening dealer Blackjack ends the round before extra wagers can be placed.
* Each round begins with a fresh shuffled 52-card deck. If a dealer draw cannot complete, all outstanding wagers are refunded.
* Insurance and surrender are not implemented.

For automated checks from a terminal:

```text
godot --headless --path . scenes/tests.tscn
```

---

## Special Rules: Reroll, Second Chance, Lucky 9, and Double Target

Classic is the default: special rules start Off. To try Reroll:

1. Click **Rules** before dealing.
2. Choose **Selected rules - Always active** and leave **Reroll** checked.
3. Click **Apply Rules**, then place a wager and **Deal Cards**.
4. Click **Reroll**, then click a highlighted card in the active hand.
5. The replacement appears immediately. The button changes to **Used** until the next round.

The Rules dialog also offers Random mode and a count of rules to activate per round. Only selected rules enter the random pool; selections are refreshed before each accepted opening deal. Reroll, Second Chance, Lucky 9, Double Target, and Mystery Card are now available. With all five checked and a random count of 1, any one activates with equal probability. A count of 2 activates two different checked rules; a count of 5 activates all five. A single checked rule always activates itself. Selection has no duplicates and stays fixed during a round; consecutive rounds can repeat the same selection.

Rules are locked during a round. The status area displays the active rules and whether each ability is available or used, plus Lucky 9 and the announced Double Target total. Between rounds it displays the next-round configuration. Restart keeps settings but begins a new session.

Reroll behavior:

* Free, once per player per round, shared across every split hand.
* Replace any card in the currently active hand, including after Hit.
* Draw one new card; the removed card remains discarded until the next deck reset.
* Keep the same card count and wager. Totals, Ace values, and action availability are recalculated.
* A replacement bust finishes that hand unless an unused, active Second Chance offers recovery. An exact Double Target match pays its small return when the bust is kept. Other split hands continue normally.
* Reaching 21 automatically finishes that hand. Rerolled 21 pays as a regular 1:1 win, never a natural 3:2 Blackjack.
* A surviving two-card hand can still Double or Split. This does not grant another Reroll.
* Standing/doubled hands and auto-finished split Aces cannot use Reroll.
* Invalid selections and empty decks do not spend the ability. Cancelling selection also does not spend it.
* Natural opening Blackjack resolves after any Mystery Card choice and before normal special actions become available.
* Cards support mouse clicks and Enter/Space when focused during Reroll selection.

Second Chance behavior:

* Free, once per player per round, shared across split hands. Its use is separate from Reroll.
* A bust caused by Hit, Double, or Reroll pauses the round before dealer play or settlement. Other actions lock; choose **Second Chance** or **Accept Bust**. If the total exactly matches an active Double Target, the alternative is **Take Payout**, with the total return shown in the prompt.
* Second Chance removes exactly the card that caused the bust. That card stays discarded until the next deck reset; no replacement is drawn and no additional wager is charged.
* After a rescued Hit or Reroll, continue playing the surviving hand. Double/Split eligibility is recalculated from the resulting hand.
* A rescued Double keeps the doubled wager and still finishes the hand automatically. Recovery does not grant extra draws after Double.
* Recovering a Reroll bust removes the replacement card, even if it was in the middle of the hand. The previously rerolled card remains discarded and Reroll stays used.
* Declining recovery or taking a Double Target payout does not spend Second Chance; it can be saved for a later split hand. After use, later busts finish normally, with exact Double Target matches still paying automatically.
* It cannot change an already finished hand, an opening natural Blackjack, or auto-finished split Aces. It works even if the deck is empty because it does not draw.
* Usage resets only when a new round successfully starts. Restart retains rule settings and resets all ability uses.

Lucky 9 behavior:

* Enable **Lucky 9** in Rules with Always Active, or include it in the Random pool. It is automatic and has no action button.
* Only the finalized opening two-card hand with a calculated total of exactly **9** qualifies. When Mystery Card is active, qualification is checked after Keep/Replace; replacing into 9 qualifies, and replacing away from 9 does not. For example, 4 + 5 qualifies; Ace + 8 is soft 19 and does not qualify. A later total of 9 created by Hit, Reroll, or Split does not qualify.
* A qualifying hand receives an extra **50% of its opening wager** if it wins against the dealer or the dealer busts. Bonus money is rounded to the nearest cent.
* Example: wager $10, open with 4 + 5, Hit to 19, and beat the dealer's 17. Receive the $10 wager back, $10 normal winnings, and a $5 Lucky 9 bonus. Net gain: **+$15**.
* Double increases the normal wager/winnings but keeps the bonus based on the original opening wager. A $10 qualifying hand doubled to $20 earns a $5 bonus on a win, for a net gain of $25.
* Reroll and Second Chance preserve an already qualified hand even if its current cards/total change. They cannot make a nonqualifying opening eligible.
* Splitting removes qualification from the original hand; neither split hand inherits or earns a Lucky 9 bonus. This includes pairs made using Reroll and split hands that start at 9.
* Loss, bust, push, opening dealer Blackjack, and canceled/refunded rounds pay no bonus. A winning recovered hand can still receive its bonus.
* The hand shows a gold **LUCKY 9** marker with its potential bonus during play. On settlement it shows the actual bonus in green, or a neutral no-bonus message.
* Qualification, bonus state, and all hand/result displays reset when a new round starts.

Double Target behavior:

* Enable **Double Target** in Rules with Always Active, or include it in the Random pool. It is automatic and has no separate action button.
* Each accepted active round uniformly chooses **one integer from 22 through 30, inclusive**. The status area shows **Double Target: N** before any player action. All split hands share that number, and it stays fixed until the next round. Consecutive rounds can repeat a target.
* **21 remains the normal goal.** Ace values, natural Blackjack payouts, dealer play, Hit, Stand, Double, and Split retain their existing rules.
* A hand that busts at exactly the announced target receives **1.25 times that hand's wager returned total**, rounded to the nearest cent. This is **0.25 times the wager in profit**, not 1.25 times in profit. There is no extra success roll, and the hand does not need to beat the dealer.
* Example: target 25, wager $10, cards total 18, draw 7. Keeping the resulting 25 returns **$12.50**, for a **+$2.50** net gain. A doubled $20 wager returns $25, for a +$5 net gain.
* Other busts lose normally. You cannot continue hitting after a bust to reach the target. For example, busting at 24 when the target is 25 ends that hand unless Second Chance recovers it.
* When Second Chance is active and unused, **every bust still offers recovery**. At a matching target, choose **Second Chance** to remove the bust-causing card and continue, or **Take Payout** to keep the bust and finish the hand. Recovering a doubled hand still finishes it automatically with its doubled wager.
* Taking the payout leaves Second Chance unused for later split hands. If Second Chance is unavailable or already used, the exact-match payout happens automatically.
* Each split hand is assessed separately. Multiple hands may receive the payout in one round. A finished matching hand shows **payout secured** while other hands play; amounts settle together when the round completes.
* A bust caused by Reroll can qualify. Recovery removes the changed card normally and does not preserve a claim to that discarded bust total.
* Lucky 9 never adds a bonus to a Double Target payout. A recovered Lucky 9 hand can still earn its ordinary win bonus if it wins later.
* Opening natural Blackjack resolves after any Mystery Card choice and before normal special actions. If all hands bust, the dealer does not draw; matching hands receive the small payout and other busts lose. If dealer play cannot complete for surviving hands, the existing cancellation policy refunds every wager and pays no special winnings.
* The finished hand displays **Double Target N! Small win.** and its green net gain. The round net includes all special and ordinary results and clears on the next accepted deal.

Net winnings/losses:

* **Round: +$X.XX** appears in green below the bankroll for a gain; **Round: −$X.XX** appears in red for a loss. Push/refund totals show neutral **$0.00**.
* The amount is final bankroll minus bankroll before the opening wager. It includes all wagers, Double, Split, the 3:2 natural Blackjack payout, and special-rule bonuses. Returned wagers are not counted as profit.
* Every finished hand also shows its individual net result, using the same colors. Their totals match the round amount.
* The green/red round result disappears as soon as a new round successfully starts and reappears after settlement. A rejected wager preserves the finished result. An instant opening Blackjack displays its newly completed result immediately. Restart also clears it.
* Rule names and checkbox icons occupy separate controls, keeping their bounds stable when checked, unchecked, hovered, or focused. Clicking a rule name also toggles its checkbox.

### Rule scripts

* `rules/special_rule.gd` is the common RefCounted base. It supplies stable rule IDs, display metadata, activation/reset behavior, and lifecycle hooks.
* `rules/rule_manager.gd` owns the catalog, selected IDs, activation mode, random selection, and per-round reset. The UI reads this catalog to build its rule checkboxes.
* `rules/reroll_rule.gd` owns shared per-player Reroll usage and card replacement.
* `rules/second_chance_rule.gd` owns shared per-player Second Chance usage and removal of the bust-causing card.
* `rules/lucky_nine_rule.gd` records the finalized opening two-card qualification, removes it on Split, and calculates a winning bonus before settlement. BlackjackGame adds each hand's `bonus_payout` during settlement before recording net results.
* `rules/double_target_rule.gd` chooses the per-round target using its own random generator, checks exact matching busts, and computes the total return. BlackjackGame assigns `DOUBLE_TARGET_WIN` and settles that return before recording net results. It also owns the pending bust decision, action eligibility, hand progression, and payouts.

BlackjackGame creates the RuleManager and exposes `configure_rules()`, `can_reroll()`, and `player_reroll(card_index)`, `is_awaiting_second_chance()`, `can_second_chance()`, and `player_second_chance()`. `player_stand()` keeps a pending bust; UI labels that action Accept Bust or Take Payout depending on whether it matches Double Target. `get_double_target()` returns the active target (or 0 when inactive), and `is_double_target_match(played_hand)` checks a hand against it. `has_round_result` and `last_round_delta` expose a completed net result and clear on the next accepted deal, while each PlayerHand stores `net_result`. It sends temporary context to active rules at round start, after a finalized playable opening (including any Mystery Card choice), after player card changes, before settlement, and at round completion. Rules should not retain that context, which contains a reference to the game.

To add a future rule, create a SpecialRule subclass with a unique ID, register it in RuleManager, and implement its hooks/action. Registered metadata then supplies the corresponding settings checkbox. These objects stay independent of scene nodes so the same rules can power the eventual 3D interface.

Mystery Card behavior:

* Enable **Mystery Card** in Rules with Always Active, or include it in the Random pool.
* Hide the player's **second starting card**, including rank, suit, tooltip, and contribution to the displayed total. The hand displays **Total: ?**; Lucky 9 is not shown before the choice.
* Normal actions wait while the player chooses **Keep Card** or **Replace Card**. Keep immediately reveals the original card. Replace discards it for the rest of the round, draws one replacement, and immediately reveals that replacement. There is no extra wager or second replacement.
* The final two cards become the official opening hand. A kept or replaced Ace plus a 10-value card is **natural Blackjack, paying 3:2**. Two opening Blackjacks push; only dealer Blackjack loses; only player Blackjack wins. Both opening checks wait until the player chooses, even when both original hands are Blackjack.
* Lucky 9 checks the final two-card total after the choice. Replacing into 9 qualifies; replacing away from 9 does not. Qualification then locks in, and later Reroll/Second Chance preserve it while Split removes it as before. Ace + 8 is 19 and does not qualify.
* If neither opening hand is Blackjack, the dealer's hole card remains hidden until normal dealer play/settlement. The opening choice never reveals dealer information early.
* One choice per player per round, shared across any later split hands. Split creates no new hidden cards or replacements. Reroll and Second Chance remain unused by this choice.
* Afterward, Hit, Stand, Double, Split, Reroll, Second Chance, and Double Target work as usual. Later Reroll/Hit/split 21 remains ordinary 21; only the finalized unsplit opening earns natural Blackjack.
* Failed replacement draws leave the choice available, the original card hidden, and the wager unchanged. Keep remains available even with an empty deck. Discards return only when the next round resets the deck.
* New rounds hide a fresh opening card and clear the previous net result. Restart retains rule settings and resets the session.

`rules/mystery_card_rule.gd` owns the one-time opening replacement without flagging it as Reroll. BlackjackGame exposes `is_awaiting_mystery_card()`, `is_player_card_hidden(hand_index, card_index)`, `can_replace_mystery_card()`, and `player_choose_mystery_card(replace_card=false)`. Its separate opening-choice state prevents normal actions and postpones opening Blackjack checks and the playable `opening_dealt` hook until the choice is final.

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
