# Multiplayer Lounge — Test Guide

The shared lounge supports **one host plus up to three guests**, with synchronized avatars, seats, and a playable **Blackjack table with all five special rules**. The host chooses Classic, Random, or All Active and the next-round rule pool. Multiplayer now includes finite sessions and final standings. Shared floating toy pickup/physics is playable. Persistent wins and cosmetics remain later milestones. **Solo 3D** includes floating toys and finite sessions.

## Two PCs on different networks — Online mode

1. Give both players this **same updated build** and open it in Godot 4.7.x (or use matching exports).
2. Both select **Online · Room Code** in the launcher. This is the default mode.
3. The first player enters a name and clicks **Host Online Room**. Wait for the room to open, then click **Copy Code** in its top header.
4. Send the entire copied code to the other player using your usual messaging app. Only the public room code is shared.
5. The second player enters their name, pastes the code into **Room code**, and clicks **Join by Code**. Do not enter an IP address or router port.
6. Check both names and **2 / 4 players**, walk/sit in both windows, start a session from the host Console, and complete a deal. Check dealer secrecy, payouts and toy movement from both PCs.
7. Leave as the guest and join again using the same code while the host remains in that room. Closing/rehosting creates a new code; old codes stop working.

No player configures router port forwarding for this mode. Players still need internet access to the relay and may need to allow Godot/the exported game through Windows Firewall. The host remains the game authority; leaving or losing the host closes the room.

**Service:** the default is the public Noray development instance documented by Fox’s Sake Studio: `foxssake.studio`, TCP 8890 and UDP registration 8809, plus dynamically assigned UDP relay ports. It is a shared test service with no uptime/capacity guarantee. School/work networks may block its UDP traffic. If the service cannot be reached, the launcher should show an error and unlock Host/Join; Cancel remains available during setup. Both players can choose the same team-owned Noray service under **Advanced online settings**. See [hosting documentation](https://foxssake.github.io/netfox/latest/hosting/) and [Noray deployment instructions](https://github.com/foxssake/noray).

**Verification boundary:** automated checks route real independent Godot game processes through a local Noray-compatible relay. They exercise the actual registration, UDP handshake and forwarded ENet game packets, but do not certify the public service or every real router/ISP. The two-PC, two-network steps above are the acceptance test for your setup.

## First LAN test: two windows on your computer

1. Import this build's `project.godot` in Godot 4.7.x.
2. In the **Game** toolbar menu, disable **Embed Game on Next Play**. Separate windows make testing input and resizing easier.
3. Open **Debug → Customize Run Instances…** and configure Godot to launch **two instances**.
4. Press **F5** and choose **LAN / Direct IP** in both windows. In one, enter **Host** as your name, leave the port at **24567**, and select **Host LAN Room**.
5. In the other window, enter **Guest**, use **127.0.0.1** as the host address, and use the same port (**24567**). Select **Join by IP**.
6. Both windows should show **2 / 4 players**, both names, and one visible remote egg avatar. Each window controls its own player.
7. Keep the window you are controlling in focus. Click the room to capture the mouse; **Escape** releases it so you can switch windows.

You can also launch the Godot executable twice with `--path` pointing at this project, or use two exported game instances. Only one instance should host on a given port. For a four-player test, stop the games, configure **four run instances**, then relaunch with one Host and three Guests. All instances must use this same build.

If Windows asks whether the game may communicate on your **Private network**, allow it for local-network testing. No router port forwarding is needed for two windows on one computer or two devices on the same LAN.

## Start a competition

1. Connect everyone who will compete **before starting**. The host clicks **Console** in the header, or approaches the physical side console and presses **E**. Session setup and rules share this one scrolling form; there is no separate Session button.
2. Choose **1–100 rounds** and **$1–$100,000 starting money per player**, in cents. Defaults are **10 rounds and $100**. Guests can inspect setup but cannot edit or start it.
3. Set the mode, checked rules and random count in the same form, then select **Start Session**. The complete draft commits together. Every currently connected player enters with the same bankroll, including players who are walking. No betting is allowed before the host starts. Closing setup without starting discards draft changes.
4. Starting money and round limit stay locked until the session ends. Open **Console** during play to inspect progress and locked session settings. The rule section remains editable by the host; saved rule changes still affect the next deal and clear Ready confirmations.

## Play a shared Classic round

1. **Sit both players before readying** (G). Seated session entrants who can afford the $1 minimum participate in the next deal. Walking entrants and spectators do not hold up betting.
2. Everyone has the host-selected starting balance. Choose a bet in each window, then click **Ready · Next Deal [B]**. You can **Cancel Ready** before the last player confirms. No money is deducted until the cards are dealt.
3. The last required Ready automatically starts one round. The host handles the deck, turn order and payouts. It does not manually approve actions.
4. Players act in chair order, from left to right. The active table display turns gold and the bottom status names the current player/hand. Only that player's **Hit, Stand, Double, Split** buttons are enabled. Split hands finish before the next player's turn.
5. While seated, **hold RMB** to look freely and release it to use the buttons. **C** or **Table [C]** frames the table again. Dealer/player totals and wagers are on the table; your balance and green/red net result are on the HUD.
6. After everyone finishes, the dealer reveals its hole card, hits below 17 and stands on every 17. Each player's hands settle independently. Natural Blackjack pays 3:2; two naturals push; split 21 pays the ordinary win rate. Double draws exactly once, and split Aces receive one card each. Other split behavior matches Solo, including up to four hands and doubling after a split.
7. The HUD shows **Round X of Y**. Ready everyone again while rounds remain. The previous net indicator remains between rounds and clears when the next deal actually starts. A completed shared deal counts **once**, including every split hand, opening Blackjack and rule decision. Refunded interrupted deals do not consume a round.

**Leaving your seat during play (G or Leave Seat):** your remaining hands automatically stand and settle normally; already dealt wagers are not refunded. Disconnecting also auto-stands remaining hands and releases the chair, allowing the next turn to continue. An existing session entrant who sits during a round waits for the next deal. New arrivals and reconnecting peers spectate until the next session. Returning to a chair on the same connection keeps the entrant's current bankroll.

## Results and playing again

After the final shared dealer payout, **Session Results** opens for everyone. It shows the winner(s), five columns: **Place, Player Name, Starting Balance, Ending Balance, Net Profit**. Net profit/loss is green/red. Players with equal displayed cent balances share a place, using **1, 1, 3** ranking. Scores include all split/double and rule payouts. No further bets are accepted after the session ends.

**Back to Room** lets you keep exploring. Use **Console → View Results** to reopen the results. The host's **New Session** button opens setup with the previous values as defaults; choosing **Start Session** resets all currently connected players to the new starting money and clears old hands, wagers, net indicators, card lifting and progress. Closing that draft leaves the completed results intact.

Entrants who disconnect keep their last settled score in the results; outstanding dealt hands auto-stand and settle first. Reconnecting uses a new connection and **does not create another competitive bankroll**: the player watches until the next session. Late spectators are excluded from this session's standings and join when the host next starts. The original disconnected entry remains marked **left**. If no connected entrant can afford the $1 minimum, the session ends early after settlement; walking away from the table alone does not end it.

**Current scope:** sessions and bankrolls last while the room is running; there is no account save or reconnect restoration. The host leaving closes the room. Toys share host-owned physics and exclusive pickup ownership across the room. The Solo game retains its existing rules, toys and session behavior.


## Shared toys and bet focus

- Aim at the die, token or orb near the table. **F** grabs the toy named in the prompt; F again drops it. Use the cursor while seated, or the center dot during mouse-look. **Click** pushes a free toy; pushing the orb also toggles its glow. **Click while holding throws** the toy forward.
- Look around while carrying: the toy follows the center reticle and still collides with walls, furniture, other toys and other players. Drop it to preserve its carrying momentum, or click to throw with extra speed/spin. Walking into a free toy nudges it; toys do not block the player capsule.
- Try catching a nearby fast-moving toy. A small forgiving grab area and short timing tolerance should keep the Grab prompt usable as it crosses the reticle. Distant objects and toys behind walls/furniture remain unavailable.
- Throw at a walking or seated player: the toy should physically bounce, while their movement/camera stays stable.
- Watch from the other window: both players should see the same body motion and glow. Try grabbing the same object: the first accepted grab wins. One toy per player; the prompt names another holder.
- Join a third window while carrying a toy: it should show the current location and holder. Stand/sit, reset with walking R, or leave as the holder: the toy releases where it was, without teleporting to the player spawn.
- In a bet field, type a number or expression, press **Enter**, then immediately press **B** to Ready. The value should commit and shortcuts should work without another click. Enter only confirms the field; B/Ready commits the wager.
- Toys work during or between rounds and cannot alter cards, balances, rule allowances or standings.

## Room leaderboard

A physical **Session Leaderboard** is mounted on the **left wall near the table**. Walk over or look toward it between rounds. It shows place, player name, starting balance, current balance and net profit. All players see the same host-owned standings.

Balances/ranks update only after complete shared settlement. While bets are on the table, the screen keeps the previous settled balances instead of temporarily subtracting wagers. Once the session ends, the current-balance heading changes to **Ending Balance** and matches the final results. A new session replaces the old standings with equal fresh balances. HUD hiding and table-info hiding do not hide this physical screen.

## Try multiplayer special rules

1. Open **Console** in the header, or walk to the lit side console and press **E**. Session settings and the complete rule form are together; scroll to the rule section. The host can edit; guests can inspect the saved next-deal settings. Closing or Cancel discards the draft. The form scrolls in small windows, with fixed Apply/Cancel buttons.
2. Choose **Classic**, **Random**, or **All Active (checked rules)**. Check the rules that may participate. Random chooses **1–5 distinct rules** from that pool each deal, clamped to the number checked; combinations can repeat. No checked rules means Classic behavior.
3. During a session, select **Apply · Next Deal**. Before starting, **Start Session** saves the whole form together. Saving clears previous Ready confirmations without charging money. A change during play affects the next deal only; the current rules and target remain fixed. All players must Ready again under the saved settings.
4. The same active rules and **Double Target number** appear for every player. Personal usage is independent: one player's Reroll or recovery does not spend another player's allowance. Split hands share that player's allowances.

| Rule | Multiplayer behavior |
| --- | --- |
| Reroll | On your normal turn, click **Reroll [R]** to enter selection mode. Your eligible active-hand cards gain gold outlines. Click one physical card (flat or lifted), or explicitly choose a card in the dropdown and click **Replace Selected**. No card is chosen by default. **Esc**, **R**, or Cancel Reroll exits without spending the use. Replace one card once per player per round. The discarded card stays out of the deck. A rerolled 21 is ordinary 21. |
| Second Chance | After a bust, remove the exact bust-causing card once per player per round, or accept the bust. Recovery from a Double still ends the hand with its doubled stake. |
| Lucky 9 | A finalized two-card opening of 9 qualifies for a bonus of 50% of the original wager if the hand wins normally. Mystery Card runs first. Reroll/recovery preserve qualification; splitting removes it. Doubling does not increase the bonus. A gold **Lucky 9 · +$X on a win** marker appears on the qualifying hand as soon as its opening is finalized; your current-rules text also says **qualified**. Split/new nonqualifying openings clear the marker. |
| Double Target | One shared random number from **22–30** per deal. An exact kept bust returns **1.25× the hand's wager in total** ($10 returns $12.50). If recovery is available, choose **Second Chance** or **Take Target Win [E]**. Other busts lose normally; Lucky 9 does not boost target payouts. |
| Mystery Card | The second opening card and total stay hidden for every viewer, even while lifting the hand. Players take **Keep · Reveal [K]** or **Replace · Reveal [N]** choices in chair order before ordinary turns. Replacement is one-time, with the old card discarded. The finalized two cards qualify for opening Blackjack and Lucky 9. Dealer Blackjack waits for all choices; two naturals push. |

The dealer hole card remains concealed until settlement, including while local **D** presentation is raised. A player who leaves their seat/disconnects during a Mystery Card choice automatically keeps the card and stands; the remaining players can continue. No dealt wager is refunded merely for leaving. Existing entrants who reseat wait for the next deal; new connections wait for the next session.

Suggested test: enable all five, connect four players, and verify Mystery Card choices/reveals, each player's separate Reroll/recovery, the shared target, and separate green/red results. Save Random with two checked rules during that round, then verify the next deal uses exactly those two and restores each player's allowances. Try changing settings after somebody Readies: everyone should confirm again.

## Read cards and reduce overlays

The balance, green/red round result and **C/D/V/L/H/G** controls share one compact area above the action buttons. Complete controls wrap onto another line in a smaller window. The permanent bottom instruction bar is removed; nearby-chair/console prompts and temporary notices appear only when relevant. Reroll's card selector appears only while choosing a card. Keyboard labels match the action buttons; shortcuts are ignored while typing, during a modal console, out of turn, or when the action is unavailable.

- **Lift My Cards [V] / Lower My Cards [V]:** animate your original 3D cards up into a readable fan in front of you. Press again to lower them onto the table. Other players see the hand lift too. You can keep looking around and using Hit/Stand/Double while it is raised; new cards join the fan.
- With split hands, lifting follows the active hand when play advances. The **Hand** dropdown lets you inspect another of your own split hands. Inspection never spends an action or changes money. Leaving the seat/room or starting a new deal lowers old cards automatically.
- **L / Info:** cycle the physical name/total displays through **Faint → Hidden → Solid**. Faint uses a translucent background; Hidden removes the displays, including the dealer total. This is a personal display preference.
- **H / Hide HUD:** hide the screen overlays for a clear room view. A small **Show HUD** button stays at the upper right; click it or press H to restore controls. The on-screen panels also use a more transparent background by default.
- **Raise Dealer Cards [D] / Lower Dealer Cards [D] (while seated):** dealer cards start flat on the table. D raises a smaller, upright row at the dealer’s side **only in your view**; other players continue seeing their own chosen view. D again lowers them. It does not move/zoom the camera, lower your own held hand, or send a network action. C also lowers them while returning to the table-facing view. Leaving the seat or starting a new deal resets them to flat. The hole card stays concealed until settlement.

The multiplayer table is wider and has **four playable chairs**, in addition to the dealer chair. Its larger cards and raised-card view leave more room for individual hands. Solo retains its original room layout.

## Controls

| Control | Action |
| --- | --- |
| Click the world while walking | Capture mouse for looking/movement. |
| WASD | Walk. |
| Shift | Sprint. |
| Space | Grounded spacey jump; no repeated jumping while held. |
| Mouse / hold RMB when seated | Look around; release RMB for table buttons. |
| C / Table [C] | Return to the normal table view. |
| D / Raise Dealer Cards [D] (seated) | Raise/lower dealer cards locally, without camera zoom. |
| V / Lift My Cards [V] | Raise/lower your own hand in 3D. |
| L / Info | Faint, Hidden or Solid table displays. |
| H / Hide HUD | Hide/restore the screen overlays. |
| G / Sit or Leave Seat [G] | Sit in the nearby chair you are looking toward, or leave your current chair. |
| Q / Hit [Q] | Draw a card on your turn. |
| E / Stand [E] | Finish the active hand; accept a pending bust or target payout. Never leaves the chair. While walking, E opens the nearby rule console. |
| Z / Double [Z] | Double the active hand when available. |
| X / Split [X] | Split the active pair when available. |
| R / Reroll [R] (seated) | Enter/cancel card selection. Click a gold card, or choose a dropdown card and confirm. |
| T / Second Chance [T] | Recover a pending bust when available. |
| K / Keep · Reveal [K] | Keep and reveal the Mystery Card. |
| N / Replace · Reveal [N] | Replace and reveal the Mystery Card once. |
| B / Ready [B] | Ready/cancel your next bet. |
| Console | Unified session setup and next-deal rules; View Results reopens final standings. |
| R (walking only) | Return to the entrance. F remains reserved for future multiplayer toy pickup/drop. |
| Escape | Cancel Reroll selection without spending it, or release the mouse cursor. |
| F11 / Alt+Enter | Toggle fullscreen in a standalone window. |
| Leave Room | Return to the launcher. If the host leaves, guests also return. |

## What to check

- Walk, sprint, jump, and turn in one window. Verify that the other window sees that same player move.
- As both Host and Guest, walk or sprint into each of the four walls. Keep moving against the wall while looking around, then walk away. Collision should hold you steadily, looking should stay free, and the other window should see your movement without snapping.
- Verify the colored nameplate identifies the remote player; controlling one window must not move the other player's camera.
- Approach a front chair, look toward it, and press G. The other window should see your egg seated, and the roster should name the occupied chair.
- Try taking the same chair from the other window. It should stay with its original occupant and show an occupied-seat message.
- Leave the chair with G or its button. The chair should immediately become available to the other player. During a round, remaining hands auto-stand and settle normally.
- Add third and fourth instances to verify **4 / 4 players**, distinct names/colors, all four playable chairs, and turns for all four players. Test V in each window: the owner should see readable faces, and the others should see those same cards lift.
- Leave as a guest. Their egg and chair entry disappear; their original settled score stays in session results. Rejoin and verify only one egg appears, with the new connection spectating until the next session.
- Start a two-round session with $150, play both deals, and verify Round X of 2, blocked betting after settlement, sorted final money and tied placements. Check the left-wall leaderboard between deals, reopen results through Console, then use New Session and confirm everyone resets equally.
- Leave as the host. Guests should return to the launcher with a message. If the host process crashes instead, the snapshot timeout also returns guests to the launcher.
- Try joining an unused port. After several seconds, a connection error should appear and Host/Join should become available again. Cancel Connection should also work.
- Open Solo 3D or Solo 2D from the launcher and check the existing game still starts. Stop and rerun F5 to return to the launcher after Solo play.

## Two computers on the same network

Use this **same build** on both computers and select **LAN / Direct IP** in both launchers. Host on the first computer. Its room header lists candidate **Join IP** addresses; you can also find the LAN IPv4 address with Windows `ipconfig`. On the second computer, enter the first computer's LAN address and the matching port, then Join. **127.0.0.1 only refers to the computer running that window**, so do not use it to join another computer.

If multiple addresses are listed, choose the address for the Wi-Fi/Ethernet connection shared by both computers. Some school or guest Wi-Fi networks isolate devices; try a private LAN if peers cannot reach each other. LAN / Direct IP mode uses direct UDP. For different houses without router configuration, use **Online · Room Code**, which sends the existing ENet game through a Noray relay. There is no public matchmaking/server browser or account system.

## Automated checks

Online launcher/cleanup and complete games through actual relayed UDP sockets:

```text
python tools/run_online_tests.py --godot "C:\path\to\Godot_v4.7.2-stable_win64.exe"
python tools/run_online_tests.py --four --godot "C:\path\to\Godot_v4.7.2-stable_win64.exe"
```

These use a local protocol fixture, not the public service. The fixture registers each UDP endpoint, allocates per-player relay sockets and forwards from the sender’s relay port just like Noray. Tests include fragmented TCP replies, room-code validation, cancellation, fresh codes on rehost, hidden private IDs, invalid rooms, service loss, timeout recovery and LAN fallback. Three-peer table flows cover split/double payouts, hole-card privacy, UI actions, replay rejection and disconnecting during a turn; four-peer flows cover the fourth chair, lifted cards, turns and complete rounds. Successful runs print **ALL ONLINE RELAY TABLE TESTS PASSED** and a count of forwarded packets/bytes.


Shared toy physics, ownership and bet-focus flow (host, guest and mid-carry late observer):

```text
python tools/run_toy_tests.py --godot "C:\path\to\Godot_v4.7.2-stable_win64.exe"
```

For additional lively motion, fast catch and player throw cases, add `--physics` to that command. Both flows end with **ALL MULTIPLAYER TOY TESTS PASSED**. It checks real F/click input, stale ownership rejection, guest carrying/drop, late-join state, shared glow, physical wall/floor/ceiling/toy bounces, free drift, reset/disconnect release, seated host pickup, unchanged Blackjack state, and an Enter-confirmed bet followed immediately by B.


Shared table flows (known-card cases plus three- and four-peer scenarios):

```text
python tools/run_table_tests.py --godot "C:\path\to\Godot_v4.7.2-stable_win64.exe"
```

This checks Ready/cancellation, one shared dealer, hole-card privacy, turn ownership, ordinary/natural/split/double payouts, busts, stale/duplicate action rejection, next-deal net clearing, and disconnecting during the current turn. The four-peer scenario checks the fourth seat, visible card lifting, split-hand inspection, invalid/stale inspection requests, hiding/restoring HUD and table labels, lowering on standing/new deals, flat-by-default dealer cards, independent local raising/lowering, smaller card size, unchanged camera/zoom, and concealment in both presentations. It also simulates twelve complete four-player rounds to check that all cards belong to one shared deck. Additional known-card and four-peer flows verify all five special rules, guest read-only settings, stale-settings Ready rejection, next-deal configuration, hidden player cards/totals, independent allowances, the target/recovery decision, Lucky 9 and Mystery natural payouts. The rule peers also verify local gold outlines, no default Reroll target, direct ray/cursor picking on flat/lifted cards, selecting a second card through the dropdown, free Escape cancellation, disabled-action shortcuts, typing/repeat protection, E versus G behavior and nonoverlapping HUD controls at 640×560, 960×640 and 1920×1080. It also completes 24 four-player all-rule rounds. Session cases add setup validation, locked settings, exact counting after split/natural/rule settlement, refunded retries, early bankruptcy, tied placements, a real disconnect/reconnect spectator, departed score retention, old-session request rejection and two fresh competitions through the production setup/results controls. Additional checks verify atomic combined Start, five result columns, stable wall standings while wagers are reserved, immediate Lucky 9 qualification without leaking Mystery Card values, reroll/recovery persistence and split reset. Success ends with **ALL MULTIPLAYER SESSION TESTS PASSED**, after the Classic/presentation and special-rule markers. You can run `scenes/multiplayer/classic_table_tests.tscn` or `scenes/multiplayer/special_table_tests.tscn` or `scenes/multiplayer/table_session_tests.tscn` directly with F6 for deterministic engine flows; the RPC scene requires the Python runner.

Room movement/connection regression checks:

From the project folder, with Python and Godot available:

```text
python tools/run_multiplayer_tests.py --godot "C:\path\to\Godot_v4.7.2-stable_win64.exe"
```

On Linux/macOS, provide the relevant Godot executable path. The runner starts **three real ENet processes** on loopback, checks avatars/movement, physical wall contact and camera freedom for Host and Guest at all four walls, exclusive chairs, invalid and stale movement packets, reset and seat release, guest disconnect/rejoin, graceful and abrupt host shutdown, and an unreachable-host timeout. Successful runs end with **ALL MULTIPLAYER ROOM TESTS PASSED**. Running `network_tests.tscn` alone explains how to invoke the multi-process runner.

The existing `scenes/tests.tscn`, `scenes/room/session_tests.tscn`, and `scenes/room/room_tests.tscn` remain available for Solo regression checks. Run the room tests in a standalone window with embedding disabled.
