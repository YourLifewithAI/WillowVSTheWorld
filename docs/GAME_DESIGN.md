# Willow VS The World: Game Design Document

*Living document. Version 0.1, the first playable prototype.*

## The pitch

The car pulls out of the driveway. The second the door clicks shut, the **pets**
and the **robots** go to war over the one thing that matters: **the TV remote**.

Two phases, one afternoon:

1. **War for the remote.** Team capture-the-flag in a cozy isometric living room.
   Carry the remote to your base and change the channel to your show.
2. **Cover it up.** A car door slams in the driveway. Truce! Everyone, both teams,
   races to put the house back together before the parents walk in.

The winners of the war only get to watch their show if the house passes inspection.
Trash the place too hard and *everyone* is grounded.

## Design pillars

1. **Cozy chaos.** Soft pixel art, warm colours, nobody gets hurt. Violence is
   slapstick: bonks, boops and KOs that end in a nap, never a death.
2. **Rapid, readable action.** Matches are short, inputs are few (move, attack,
   special, dash, interact) and every character reads at a glance.
3. **Rivals, then roommates.** The same players who just fought have to cooperate.
   Every lamp you knock over in phase 1 is a lamp *someone* has to fix in phase 2.
4. **Every character is a personality.** Cats are fast and chaotic and bad at chores.
   The helper bot was literally built for tidying. Abilities follow from who they are.

## Match flow

| Phase | Default length | What happens |
|---|---|---|
| Countdown | 3 s | "The parents just left..." Everyone at their base. |
| **War** | 3:00, or first to **5** captures | Capture the remote. KOs, knockbacks, mess. |
| Whistle | 3 s | "CAR IN THE DRIVEWAY!" Everyone freezes; KO'd players wake up. |
| **Cleanup** | 0:45 | Both teams fix, sweep and return the remote. |
| Results | until the host continues | The parents' verdict, the TV, the awards. |

All of these are `@export` knobs on `Match` (`game/scenes/match/match.gd`).

## Phase 1: War for the remote

- **The remote** starts on the rug in the middle of the room.
- **Pick it up** by touching it. The carrier is slower (per-character `carry_speed`)
  and **can't attack, use specials, or dash**. That makes the carrier
  vulnerable on purpose, so escorting and passing matter.
- **Pass it:** press *interact* while carrying to throw it. Teammates (or
  enemies!) can catch it mid-air.
- **Score:** stand on your team's rug holding the remote for **2 seconds**
  ("changing the channel"). Taking any hit resets the timer. A score sends the
  remote back to the middle and switches the TV to your team's show.
- **Drops:** a KO'd carrier drops the remote. If nobody touches it for 8 seconds
  it scoots back to the rug.

### Combat

| Input | What it does |
|---|---|
| **Attack** | Short-range swipe in a cone in front of you. ~5-7 hits to KO. |
| **Special** | Your character's signature move, on a cooldown (3.5 to 8 s). |
| **Dash** | A quick burst of speed on a 1.1 s cooldown. Dashing through things knocks them over. |

- **Knockback** is big and floaty. Getting launched into the furniture is half the fun.
- **KO** at 0 HP: the character curls up for a nap (`z z`) for 4 seconds, then
  respawns at their base with a moment of invulnerability. They leave behind
  **debris**: fur tufts for pets, loose bolts for robots.
- Hits are resolved by the host (see *Networking*), so there's no death, no
  permanent loss, and no griefing your own team: friendly fire is off.

### Mess: how the house gets wrecked

Everything under the `Entities` node in the level that is a `MessItem` can be
knocked over (lamps, plants, vases, cushions, books, bookshelves, the laundry basket).

| Source | Light items | Heavy items (bookshelf, basket) |
|---|---|---|
| Basic attacks swinging near it | knocked | only if the attack is strong (>= 200 force) |
| Specials (landings, slams, projectiles) | knocked | usually knocked |
| A character sent tumbling into it | knocked | knocked |
| A character dashing into it | knocked | no |
| **Cats just walking into it** (Willow, Biscuit) | knocked | no |
| Every KO | +1 debris pile | |

Knocked items slide a little, fall on their side and sometimes spill (plants
drop dirt). They stay down until phase 2.

## Phase 2: Cover it up

When the war ends, everyone is friends. No attacking. The goal is to get the
**House tidiness** meter as high as possible before the timer runs out.

| Task | How | Weight |
|---|---|---|
| Stand something back up | Hold *interact* next to it (3 s, faster with helpers) | 1 |
| Heavy things (marked **x2**) | Need **two** helpers at once, or The Claw alone | 3 |
| Sweep debris | Hold *interact* next to it (0.8 s). Zoomba just drives over it | 0.5 |
| Return the remote | Carry it back onto the middle rug | 1 |

**Tidiness** = how much of the mess at the start of cleanup you undid.
Each character has a `tidy` speed (cats 0.6-0.75x, Unit-7 1.5x).

### The parents' verdict

| Tidiness | Verdict | TV |
|---|---|---|
| >= 90% | **Spotless!** "Were you all asleep this whole time?" | Phase-1 winners watch their show |
| >= 60% | **Nobody noticed a thing** | Phase-1 winners watch their show |
| < 60% | **GROUNDED!** | TV unplugged. *Everyone* loses |

This is the core tension: winning the war by trashing the house can still lose the
game. A tie in captures means the TV stays on the weather channel.

End-of-match awards: **Remote runner** (most captures), **Most bonks** (most KOs),
**Tidiest** (most things fixed).

## The roster

Each side has the same four archetypes so the teams stay balanced, but every
character plays differently. Numbers live in `game/scripts/core/roster.gd`.

### Team Pets

| | Role | HP | Speed | Attack | Special | Cleanup |
|---|---|---|---|---|---|---|
| **Willow**, tabby cat | Speedster | 80 | 150 | Swipe | **Pounce**: leap forward, AoE bonk on landing | 0.75x, clumsy (knocks things over by walking past) |
| **Biscuit**, chonky cat | Tank | 150 | 115 | Paw Smack | **Belly Flop**: jump up, crash down, huge knockback | 0.6x, clumsy ("mostly supervises") |
| **Pepper**, pup | Bruiser | 110 | 135 | Chomp | **Big Bark**: sound wave that pierces and stuns | 1.25x |
| **Kiwi**, budgie | Flyer | 65 | 145 | Peck | **Feather Flurry**: three-feather spread | 1.0x, flies over furniture |

### Team Robots

| | Role | HP | Speed | Attack | Special | Cleanup |
|---|---|---|---|---|---|---|
| **Zoomba**, robot vacuum | Speedster | 90 | 155 | Bump | **Turbo Suck**: pulls enemies *and a loose remote* toward you | 1.0x, vacuums debris by driving over it |
| **Unit-7**, helper bot | Tank | 140 | 115 | Bonk | **Rocket Fist**: long-range punch | 1.5x |
| **The Claw**, ceiling gantry | Flyer | 70 | 140 | Pinch | **Claw Drop**: telegraphed slam from above, long stun | 1.0x, lifts heavy things alone |
| **Bass**, smart speaker | Support | 100 | 125 | Sound Pulse | **Hype Track**: heals nearby allies and speeds them up | 1.0x |

Ideas waiting in the wings: a hamster in a ball, a goldfish in a rolling bowl,
a smart fridge (immobile turret?), a drone, a robot lawnmower that only works
in the garden map.

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Move | WASD / arrow keys | Left stick / d-pad |
| Attack | J or Z | X (west button) |
| Special | K or X | Y (north button) |
| Dash | Space, L or Shift | A (south button) |
| Interact: throw remote, hold to tidy | E or C | B (east button) |
| Menu | Esc | |

Remap in Godot: *Project > Project Settings > Input Map*.

## Art direction

- **Isometric 2:1 pixel art.** One floor tile is 32x16 px. The game renders at
  **640x360** and scales up with nearest-neighbour filtering, so every pixel is crisp.
  The HUD renders at full resolution so text stays sharp.
- **Characters** are ~12-20 px tall with a 1 px dark outline (`#2b1d2a`), chibi
  proportions, and a flat palette. They face right; the game mirrors them.
- **Readability:** every character has a team-coloured ring at their feet
  (pets peach `#ff9f68`, robots cyan `#62d6ff`), a drop shadow that shrinks with
  height, and a tiny health bar. Your own character gets a white arrow.
- **The room** is warm wood, cream walls, pastel curtains, with the pets' side
  (cat tree, fish painting, peach rug) mirroring the robots' side (charging dock,
  lightning poster, cyan rug).
- **Placeholder art** is generated by `tools/make_sprites.py` from text grids.
  Replace any PNG in `game/assets/sprites/` with real art (Aseprite is the
  usual tool) using the same file name; the furniture is drawn in code and can be
  swapped for sprites later.

**Next art pass:** walk/attack/KO animation frames (2-4 frames each), 4-direction
facing for characters, furniture sprites, a proper pixel font.

## Audio direction (not started)

Soft lo-fi living-room loop in phase 1 with a sneaky synth layer that rises as the
clock runs down; a frantic ragtime/kazoo remix for cleanup. SFX should be squeaky
and cartoonish: boing, boop, vacuum whirr, dial-up modem for robot KOs, a
car-door slam for the whistle, keys in the lock for the verdict.

## Technology

**Engine: Godot 4.7** (free, open source, MIT licensed, no royalties).
Why Godot over Unity for this game:

- It's excellent at 2D and pixel art, with isometric depth sorting built in.
- Scenes and scripts are plain text, so they diff cleanly in git and are easy to
  build and review with AI assistance.
- High-level multiplayer (ENet, RPCs) ships in the box.
- The editor is a ~150 MB download that opens in seconds, and exports to
  Windows/Mac/Linux/web/mobile. Consoles go through third-party porting partners.

Unity would also work (and has a bigger asset store and console tooling), but its
licensing history, heavier editor and binary-ish scene files make it a worse fit
for a small team starting a 2D game.

### Project layout

```
game/
  project.godot                 engine settings, input map
  scripts/core/                 Iso (projection maths), Roster (balance sheet), UiTheme
  scripts/autoload/net.gd       connections, lobby roster, launch options
  scenes/menu/                  main menu, lobby
  scenes/level/                 the living room and its building blocks
  scenes/match/                 match rules, players, bots, remote, HUD, effects
  assets/sprites/               PNGs (placeholder art)
tools/make_sprites.py           regenerate placeholder sprites
tools/smoke_test.sh             headless end-to-end tests
```

### Networking model

- **Topology:** one player hosts (they are also the server), up to 8 players.
  Everyone else joins by IP on UDP port 7777. Practice mode runs the same code offline.
- **Movement is owner-simulated.** Your machine moves your character immediately
  and streams its position 30 times a second, so controls never feel laggy.
  Other characters are smoothed toward their latest position.
- **The host is the referee.** Health, KOs, the remote, the score, the clock and
  every knocked-over item live on the host. Clients *report* hits
  (`_srv_hit`), throws and specials; the host checks them (right team, not
  KO'd, plausible distance, sender owns that character) before applying and
  broadcasting the result (`_cl_*` RPCs).
- **Bots** run on the host and use the exact same input path as players.
- **Not yet:** late joining, reconnecting, host migration, lag compensation,
  or internet play without port forwarding.

## Balance knobs

| Knob | Where | Now |
|---|---|---|
| Phase lengths, capture limit, respawn time | `Match` exports | 180 s / 45 s / 5 / 4 s |
| Channel time to score | `Match.CHANNEL_TIME` | 2 s |
| Verdict thresholds | `Match.TIDY_PASS`, `TIDY_SPOTLESS` | 60% / 90% |
| Character stats and moves | `Roster.CHARACTERS` | see tables above |
| Fix times, heavy threshold | `MessItem` | 3 s / 5 s, 200 force |

**Playtest notes so far (bots only):** a 3v3 bot war reaches 5 captures in
~60-100 s with 15-40 KOs and 8-9 knocked items. Six bots clean that up in about
10-15 s, so bots are far better at chores than people will be. The 45 s cleanup
needs tuning against **human** playtests.

## Roadmap

| Milestone | Goal |
|---|---|
| **M0: Prototype** (this) | Full loop playable vs bots and over LAN: war, KOs, mess, cleanup, verdict. |
| **M1: Feel** | Sound and music, hit-stop, screen shake, squash-and-stretch animation frames, controller rumble, a juicier whistle moment (car headlights sweep the room). |
| **M2: Real art** | Animated character sprites, furniture sprites, UI art, a pixel font, a title screen. |
| **M3: Content** | More rooms (kitchen, hallway, backyard), 2 more characters per side, room events (the doorbell, a delivery drone, the cat flap). |
| **M4: Online** | Internet play without port forwarding (relay or Steam/Epic networking), invite codes, reconnects, lag compensation for hits. |
| **M5: Couch mode** | Several players on one screen with gamepads. It's a cozy game; this is where it will shine. |
| **M6: Ship** | Steam page, demo, festival builds. |

## Open questions

1. **Who is Willow?** The prototype guesses a tabby cat. If Willow is a real pet, what are they like?
2. **Team size:** 2v2, 3v3 or 4v4? The room is tuned for 3v3.
3. **Online vs couch:** which matters more for the first public build?
4. **Is "everyone gets grounded" too harsh?** An alternative: tidiness is a score
   multiplier instead of a pass/fail gate.
5. **Should cleanup be *entirely* cooperative?** A variant: each team tidies their
   own half, and sneaky players can hide their mess on the other team's side.
