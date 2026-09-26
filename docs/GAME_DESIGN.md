# Willow VS The World: Game Design Document

*Living document. Version 0.4: four homes, over-the-top weapons, gags, stealth, and furniture you can destroy.*

## The pitch

The car pulls out of the driveway. The second the door clicks shut, the **pets**
and the **robots** go to war over the one thing that matters: **the TV remote**.

Two phases, one afternoon:

1. **War for the remote.** Team capture-the-flag in a cozy isometric living room.
   Carry the remote to your base and change the channel to your show.
2. **Cover it up.** A car door slams in the driveway. Truce! Everyone, both teams,
   races to put the house back together before the parents walk in.

The joke: they basically destroy the whole house with ridiculous weapons, and then
somehow put every last piece back together before the parents walk in. The winners
of the war only get to watch their show if the house passes inspection. Trash the
place too hard and *everyone* is grounded.

## Design pillars

1. **Cozy chaos.** Soft pixel art, warm colours, nobody gets hurt. Violence is
   slapstick: toaster cannons, egg bombs and KOs that end in a nap, never a death.
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
| **War** | 3:00, or first to **5** captures | Capture the remote. KOs, explosions, wrecked furniture. |
| Whistle | 3 s | "CAR IN THE DRIVEWAY!" Everyone freezes; KO'd players wake up. |
| **Cleanup** | 0:45 | Both teams rebuild, fix, sweep and return the remote. |
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

**What it's built on.** It's a top-down arena brawler, not a copy of any one game.
It borrows the core loop of twin-stick action games like Hades (one weapon, one
special on a cooldown, a dash), Smash Bros' idea that *knockback*, not damage, is
the real threat, and hero-shooter class design like Overwatch: each side has the
same four jobs, filled by very different characters.

| Input | What it does |
|---|---|
| **Attack** | Fire (or swing) your character's weapon. Holding it keeps automatic weapons going. |
| **Special** | Your signature move, on a cooldown (3.5 to 9 s). |
| **Gag** | Your big, silly, charge-up move (see *Gags* below). |
| **Dash** | A quick burst on a 1.1 s cooldown. Some characters' dashes are shorter. |

- **Weapons are ridiculous on purpose:** a laser pointer blaster, a catnip bazooka, a
  tennis ball gatling gun, egg bombs, a dust cannon, a toaster that fires flaming
  toast, a wrecking ball, a subwoofer cannon. They come in three kinds: *melee*
  (swing in a cone), *shots* (straight projectiles), and *lobbed shells* that sail
  over furniture and explode where they land.
- **Knockback** is big and floaty. Getting launched into the furniture is half the
  fun, and it damages whatever you crash into.
- **KO** at 0 HP: the character curls up for a nap (`z z`) for 4 seconds, then
  respawns at their base with a moment of invulnerability. They leave behind
  **debris**: fur tufts for pets, loose bolts for robots.
- Hits are resolved by the host (see *Networking*): no death, no permanent loss,
  and friendly fire is off.

### Gags

Every character has a **gag**: a big, silly move themed on what they are (cats get
litter, the dog gets a bone, the Roomba sucks) that also plays to their strengths. The
gag meter fills slowly during the war and faster as you deal damage (about 55 seconds
from empty, or ~330 damage). Press **I** (or **Q**, or the right bumper).

| Who | Gag | The joke | Why it's a bonus for them |
|---|---|---|---|
| Cats (Willow, Biscuit) | **Litter Bomb** | Lob a whole litter box; it bursts into a dust cloud and litters the floor | Cats inside their own cloud stay invisible *even while running*; enemies wade through it at 60% speed. Biscuit's box is chonkier (bigger cloud). |
| Pepper | **Big Bone** | The gatling is swapped for a giant bone for 8 s; every whack is a home run | Huge knockback, wrecks furniture, and a dog never lets go of a bone: no butterfingers while holding it |
| Kiwi | **Flock Call** | A stampede of budgies sweeps a wide lane across the room | Bowls over everyone in the lane; Kiwi rides the flock at +60% speed |
| Zoomba | **Mega Suck** | A 3 s vortex drags enemies in; anyone who reaches Zoomba is *swallowed* for 2 s, then spat across the room | If the remote carrier gets swallowed, Zoomba gets the remote |
| Unit-7 | **Satellite Laser** | A targeting reticle, then an orbital beam from space | Massive damage and demolition, *and* a 6 s scan that reveals every hidden pet to the whole robot team |
| The Claw | **Claw Machine** | Like the arcade: grabs whoever's underneath and carries them around the ceiling for 3 s, then drops them | Grab the remote carrier and the remote is the Claw's |
| Bass | **Dance Party** | A disco ball drops; every enemy nearby is forced to dance for 2.8 s | Dancing enemies are sitting ducks; allies on the dance floor heal |

Swallowed and grabbed characters can't be hit (they're safe inside a dust bin, or a
claw), and flyers are too quick for Mega Suck.

### Stealth and detection

The pets are sneaky, the robots have sensors.

- **Sneaky (both cats):** stand still for a second and you turn invisible to the
  other team. Moving, attacking or getting hit gives you away. Willow's **Vanish**
  keeps her invisible on the move for 4 seconds.
- **Low Profile (Zoomba):** drives *under* furniture and stays hidden while it's there.
- **Ambush:** the first hit out of stealth does **double damage** and dazes. The host
  checks that the attacker really was hidden a moment ago.
- **Seeing hidden enemies:** Pepper's **nose** (short range) and Unit-7's **x-ray
  vision** (long range) reveal hidden enemies near them to their whole team. Revealed
  characters show a red ring and a little eye.
- **What you see depends on your team:** hidden enemies are invisible, hidden
  teammates look ghostly, revealed enemies are drawn normally. Bots play by the same
  rule: they can't target what their team can't see.

### Wrecking the house

This is the joke of the game: they basically destroy the house, then have to
fix it. Two layers of destruction pile up during the war.

**Furniture has health.** Couches, armchairs, tables, beds, counters, fridges, desks,
bean bags and even the half-walls crack as they take damage, then collapse into a
heap of rubble. Rubble isn't solid, so the arena opens up as the war goes on (and
the bots re-plan their routes). Damage comes from:

- every weapon (each has a `demolition` value: the wrecking ball and bazooka are
  the worst),
- straight shots, which stop at the first piece of furniture in the way and chip at
  it (so furniture is *cover* that slowly gets destroyed), except Bass's bass waves,
  which go straight through,
- explosions, which hit everything in the blast,
- characters knocked flying into it.

The TV, the pets' cat tree, the robots' charging dock and the wood stove are
indestructible: something has to be left to fight over.

**Things get knocked over and the floor gets filthy.** Everything that is a
`MessItem` (lamps, plants, vases, cushions, books, pies, trash cans, bookshelves,
laundry) can be knocked over:

| Source | Light items | Heavy items (bookshelf, basket) |
|---|---|---|
| Weapon hits and explosions nearby | knocked | if the hit is strong (>= 200 force) |
| A character sent tumbling into it | knocked | knocked |
| A character dashing into it | knocked | no |
| **Cats just walking into it** (Willow, Biscuit) | knocked | no |
| Every KO | +1 fur tuft or pile of bolts | |
| Every explosion | +1 scorch mark (or egg splat) | |
| Every Litter Bomb | +3 piles of cat litter | |

## Phase 2: Cover it up

When the war ends, everyone is friends. No attacking. The goal is to get the
**House tidiness** meter as high as possible before the timer runs out.

| Task | How | Weight |
|---|---|---|
| **Rebuild wrecked furniture** | Two helpers hold *interact* at the rubble (Unit-7 or The Claw can do it alone) | 2 + its size |
| Stand something back up | Hold *interact* next to it (3 s, faster with helpers) | 1 |
| Heavy things (marked **x2**) | Two helpers at once, or Unit-7 / The Claw alone | 3 |
| Sweep fur and bolts | Hold *interact* next to it (0.8 s). Zoomba just drives over it | 0.5 |
| Scrub scorch marks and egg, sweep litter | Hold *interact* next to it (0.9-1.2 s) | 0.5 |
| Return the remote | Carry it back onto the middle rug | 1 |

**Tidiness** = how much of the mess at the start of cleanup you undid.
The robots are the rebuild specialists: Unit-7 tidies at 2x and counts as two
helpers, The Claw counts as two, Zoomba vacuums, and everyone near Bass works 30%
faster. The cats (0.6-0.75x) mostly get in the way.

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

Each side has four very different characters: the pets lean on stealth, speed
and chaos, the robots on sensors, toughness and repairs. Every character has one
clear strength and one clear weakness. Numbers live in `game/scripts/core/roster.gd`.

### Team Pets

| | Role | HP | Weapon | Special | Strength | Weakness |
|---|---|---|---|---|---|---|
| **Willow**, tabby cat | Assassin | 65 | **Laser Pointer Blaster**: fast, long-range bolts | **Vanish**: invisible on the move for 4 s | **Sneaky**: invisible when still; ambushes do double damage | **Fragile**: lowest health in the house |
| **Biscuit**, chonky cat | Demolisher | 150 | **Catnip Bazooka**: lobbed rockets, big blast, wrecks furniture | **Belly Flop**: jump up, crash down, huge knockback | **Heavy**: takes half knockback (and sneaky, like all cats) | **Slow**: slowest in the house, slow reload |
| **Pepper**, pup | Tracker | 110 | **Tennis Ball Gatling**: hold to spray | **Big Bark**: a wave that pierces and stuns | **Good Nose**: reveals hidden enemies nearby for the team | **Butterfingers**: drops the remote whenever he's hit |
| **Kiwi**, budgie | Bomber | 60 | **Egg Bombs**: dropped from above, splash and splat | **Feather Flurry**: three-feather spread | **Flight**: flies over furniture, can't be slammed or sucked in | **Featherweight**: tiny health, knocked 60% further |

### Team Robots

| | Role | HP | Weapon | Special | Strength | Weakness |
|---|---|---|---|---|---|---|
| **Zoomba**, robot vacuum | Ambusher | 90 | **Dust Cannon**: close-range shotgun | **Turbo Suck**: pulls enemies *and a loose remote* in | **Low Profile**: hides under furniture; ambushes do double damage | **Flips Over**: a big hit leaves it upside down and helpless |
| **Unit-7**, helper bot | Engineer | 140 | **Toaster Cannon**: lobbed flaming toast | **Rocket Fist**: long-range punch | **X-Ray Vision** (long-range reveal) and **Handy** (2x rebuild speed, fixes big things alone) | **Clunky**: slow, stiff short dash |
| **The Claw**, ceiling gantry | Wrecker | 75 | **Wrecking Ball**: huge swing, flattens furniture | **Claw Drop**: telegraphed slam, long stun | **Ceiling Rider + Strong**: glides over furniture, lifts heavy things alone | **Long Reboot**: +3 s before respawning |
| **Bass**, smart speaker | Support | 100 | **Subwoofer Cannon**: bass waves that pass through enemies *and* furniture | **Hype Track**: heals and speeds up nearby allies | **Cleaning Playlist**: allies nearby tidy 30% faster | **No Legs**: hops, so its dash is tiny |

Each character's **gag** is listed in *Gags* above.

Ideas waiting in the wings: a hamster in a ball, a goldfish in a rolling bowl,
a smart fridge (immobile turret?), a drone, a robot lawnmower that only works
in the garden map. Household **weapon pickups** (a leaf blower, a garden hose, a
fire extinguisher) that spawn mid-war would add even more chaos.

## The homes (maps)

Every map is a different kind of home, and the home shapes the fight: how far
the runs are, where the chokepoints are, how much stuff there is to break.

| Home | Size | Best for | What makes it different |
|---|---|---|---|
| **The Living Room** | 16x16, one room | 4-6 | The classic. Open, symmetric, easy to read. Armchairs give cover on the lanes. |
| **Studio Apartment** | 12x12, one room | 2-4 | Bed, desk and kitchenette crammed together. Short runs, constant brawling, a milk jug that has escaped the fridge. War 2:30, cleanup 0:35. |
| **The Farmhouse** | 18x16, one big room | 4-6 | Wood stove, farm table with benches that split the pets' lane, muddy boots by the door, a pie on the floor. Cleanup 0:50. |
| **Suburban House** | 22x14, three rooms | 6-8 | Kitchen, living room and den divided by knee-walls with doorways. The pets hold the kitchen, the robots hold the den. Long runs; passing matters. War 3:30, cleanup 0:55. |

**Design rules for a home:**

- **Mirror the important stuff.** Bases sit in opposite corners, the same distance
  from the remote. Decoration can be asymmetric, but lanes and cover should be fair.
- **Put breakables in the lanes.** Items along the walls rarely get knocked over;
  the mess comes from what's in the path of the fighting.
- **Everyone can reach everything.** Bots use a navigation mesh baked from the
  furniture, so if they can't find a path, players will feel it too.
- **Each home tells a story in its props:** the studio's guitar and laundry pile,
  the farmhouse's boots and pie, the suburbs' toy blocks and bean bags.

**Homes to build next:** a beach house (sand gets everywhere and counts as mess),
a city loft with a spiral staircase, a log cabin in the snow, a mansion with way too
many vases, a trailer (the smallest map yet), grandma's house (the plastic-covered
couch can't be touched), a college dorm, a houseboat that rocks, and a
smart-home-of-the-future where the robots have home advantage.

**Making a new home** (about an hour in the editor):

1. Duplicate `game/scenes/maps/living_room.tscn`.
2. Select **Room** and set its size, floor style, wall colours, windows and doors
   in the inspector.
3. Move the `PetsBase`, `RobotsBase` and `RemoteHome` markers, and arrange
   **Furniture** and **MessItem** nodes under `Entities`. Use **FloorZone**
   nodes for kitchens, carpets and rugs.
4. Add an entry to `game/scripts/core/maps.gd` (name, blurb, scene, and any
   timing overrides) and add its id to `ORDER`.
5. Run `tools/smoke_test.sh` after adding the map name to `MAPS` in the script.
   It plays a bot match on every home and fails if nobody manages to score.

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Move | WASD / arrow keys | Left stick / d-pad |
| Attack | J or Z | X (west button) |
| Special | K or X | Y (north button) |
| Gag | I or Q | Right bumper |
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
  scenes/level/                 building blocks: Room, Furniture, MessItem, BaseZone, FloorZone
  scenes/maps/                  the homes (one scene each)
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
| **M3: Content** | More homes (see the list above), a backyard, 2 more characters per side, home events (the doorbell, a delivery drone, the cat flap, the smart home's lights turning off). |
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
