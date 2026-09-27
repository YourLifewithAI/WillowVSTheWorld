# Willow VS The World: Game Design Document

*Living document. Version 0.5: four homes, over-the-top weapons, gags, stealth, furniture you can destroy, and sound.*

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
| **Up close** (interact) | Your close-up move (see *Close-up moves* below). While carrying the remote, the same button throws it. |
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

### Close-up moves

Most weapons work at range, so everyone also has a **close-up move** on the
interact button: a short swing in a cone with one twist that fits who they are.
It's how you fight someone who's right on top of you, and several are built to
interrupt a carrier on their rug (any hit resets the channel). Swinging ties up
your weapon for 0.25 s, so it's a choice, not a free extra attack.

| Move | Who | Reach, cone, cooldown | What it does |
|---|---|---|---|
| **Pounce** | Willow | 18 px + a 28 px hop, 90°, 1.4 s | Wiggle, hop forward, swipe where she lands (stops early at the first enemy). 12 damage, 24 plus a daze from hiding. Catches runaway carriers. |
| **Making Biscuits** | Biscuit | 18 px, 110°, 0.5 s | Rapid kneading: 6 damage a knead, heals her for half, never stuns (so just walk away). Shreds furniture (15 each). |
| **Gimme!** | Pepper | 18 px, 70°, 2 s | A 5-damage nip that **steals the remote** from the carrier. Butterfingers means his next bonk drops it again. |
| **Peck Peck Peck** | Kiwi | 16 px, 60°, 0.18 s | Mash it: 3-damage pecks that keep resetting a carrier's channel, and hit things hard enough (260) to topple heavy shelves. |
| **Spot Clean** | Zoomba | 20 px, all round, 1.5 s | Spins in place: 8 damage and a big fling to everyone around it. From under the couch, an ambush on the whole crowd. |
| **Spatula Flip** | Unit-7 | 20 px, 90°, 3.5 s | Flips the target 20 px into the air like a pancake, helpless for 0.6 s. The bouncer's answer to divers. |
| **Yoink!** | The Claw | 26 px, 60°, 2.2 s | Grabs and reels the target in under the gantry, dazed for 0.3 s: set up for the wrecking ball or Claw Drop. |
| **Feedback** | Bass | 22 px, 150°, 2.5 s | A mic-feedback squeal: 4 damage, huge knockback (330). Blows pouncers and pups off a carrier, and topples shelves. |

Numbers live in `"melee"` in `game/scripts/core/roster.gd`; the effects are
`lunge`, `drain`, `steal`, `shove_items`, `knockup` and `pull`.

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

**Furniture has health.** Couches, armchairs, tables, beds, counters, fridges, desks
and bean bags crack as they take damage, then collapse into a heap of rubble.
Inside walls only give way to the heavy hitters (see *The homes*). Rubble isn't solid, so the arena opens up as the war goes on (and
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
| **The Family Home** (default) | 18x18, four rooms | 4-8 | Dining room, kitchen, den and living room in a ring (mirror-symmetric). The pets' base is in the kitchen, the robots' in the den, each behind a door with a second way out through the dining room. The remote sits in the living room, the front-most room, so no wall hides the fight. War 3:00, cleanup 1:05. |
| **Suburban House** | 22x14, five rooms | 6-8 | A long ranch house: kitchen, dining room and mudroom (pets), living room, garage workshop (robots) and den. Four doors into the living room, so eight players never jam one choke. Long runs; passing matters. War 3:30, cleanup 1:10. |
| **The Farmhouse** | 17x17, four rooms and a porch | 4-6 | Pantry, mudroom (pets), workshop (robots) and a farm kitchen around an old stone chimney that never breaks. A porch runs round the outside, so every base has three ways out. Cleanup 1:00. |
| **Studio Apartment** | 12x12, one room | 2-4 | Bed, desk and kitchenette crammed together. Short runs, constant brawling, a milk jug that has escaped the fridge. War 2:30, cleanup 0:45. |
| **The Living Room (classic)** | 16x16, one room | 4-6 | The original: open, symmetric, easy to read. No walls, so it's the place to learn. Cleanup 0:50. |

**The whole house fits on one screen.** The game draws at 640x360 and scales by
whole numbers (2x in a window, 3x on a 1080p TV), so a home can be at most 36 tiles
across (width + depth), with 48 px back walls. More rooms, not more floor.

**Inside walls** (`WallRun`, under a map's `Walls` node) are drawn 20 px tall with a
dark "cut" on top, like a dollhouse, so you can see over them. Each is built into
one-tile `WallPanel`s (furniture, so damage, cracks, rubble, rebuilding, the bots'
map and the network sync all work as for a couch), drawn by half-tile slices so
they depth-sort correctly against people. A wall fades when someone this screen can
see (or the remote) is in the strip it hides; hidden enemies never make it fade.
During cleanup every inside wall is see-through, so no mess is ever hidden.

- **What breaks them:** plain painted walls (drywall, 150 hp) ignore any hit under
  50 demolition. So only the heavy hitters get through: the bazooka (3 shells), the
  belly flop (2), the wrecking ball (3 swings), the claw drop, the rocket fist (3),
  the Big Bone (3 whacks) and the satellite laser (1 strike). Stone and outside
  walls never break.
- **One hit, one panel:** a blast or swing damages only the nearest panel, so a
  hole is exactly as big as what was really broken. A swing that lands on someone
  doesn't dent the wall behind them.
- **What they stop:** shots (except Bass's waves), blasts, swings, gags that reach
  across the floor (Mega Suck, the Claw Machine, the Flock Call), a thrown remote,
  and picking the remote up. Lobbed shells sail over while they're higher than the
  wall (as drawn) and burst on it when they're lower.
- **Flyers** (Kiwi, the Claw) fly over the walls, but carrying the remote they fly
  low and use the doors.
- **Breaking one** makes a hole everyone can use (the bots re-plan through it), a
  feed line naming who did it, and plaster dust. Mending it takes two helpers (or
  Unit-7 or the Claw alone), and it only turns solid again once nobody is standing
  in the gap. Bots knock through a wall on purpose when the way round is much
  longer, at most twice per team per war.

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
   nodes for kitchens, carpets and rugs, and give each room's floor a
   `room_name`.
4. For several rooms, add a `Walls` node and a **WallRun** under it for each
   straight wall: its line (`plane`, `at`), its span (`from`, `to`), its doors
   (at least 2 tiles wide; 2.5 is standard) and the paint of the room it faces.
   Stone stretches (`stone_spans`) and outside walls never break. On the Room,
   set `wall_joins_left/right` where walls meet the back walls, and each room's
   back-wall paint. Keep bases and the remote's rug out of the strip each wall
   hides (1.3 tiles behind it); `tests/walls_test.gd` checks.
5. Add an entry to `game/scripts/core/maps.gd` (name, blurb, scene, and any
   timing overrides) and add its id to `ORDER`.
6. Run `tools/smoke_test.sh` after adding the map name to `MAPS` in the script.
   It plays a bot match on every home and fails if nobody manages to score.

## Controls

| Action | Keyboard | Joy-Con, held sideways | Other controllers |
|---|---|---|---|
| Move | WASD / arrow keys | stick | left stick / D-pad |
| Attack | J or Z | left button | west button |
| Special | K or X | top button | north button |
| Gag | I or Q | SL or SR | shoulder buttons / triggers |
| Dash | Space, L or Shift | bottom button | south button |
| Interact: throw remote, hold to tidy | E or C | right button | east button |
| Menu | Esc | + or - | Start / Back |

Keys can be remapped in Godot (*Project > Project Settings > Input Map*). Those
actions are keyboard-only; controllers are read one by one by the `Seats` autoload
(`scripts/autoload/seats.gd`), so each person drives their own character.

### Shared screen ("couch mode")

Several people on one computer, one screen, a controller each.

- **Seats.** Seat 0 is this machine's own player (the same roster entry online play
  uses). People join in the lobby with the Switch's own gestures: SL + SR on a sideways
  Joy-Con, L + R on a pair held together or a gamepad (gamepads and lone Joy-Cons also
  take any face button; a pair's face buttons belong to two people, so they don't
  join), J on the keyboard. The first takes seat 0 (then called "P1"), the rest become
  guests. Until anyone joins with a controller, seat 0 hears the keyboard and every
  controller (solo play needs no joining); after that each seat hears only its own, and
  the keyboard only its own seat. If the house is full, a bot makes room. Guests are roster entries owned by the
  host, like bots (negative ids from the same counter, plus `owner` and `seat`), so
  the rules, the referee checks and online sync treat them like anyone else. Online
  friends can still join the same lobby.
- **Joy-Cons.** A lone Joy-Con already reports as a sideways mini-gamepad. A left + right
  pair is always merged into one controller by the engine (SDL), and that can't be
  switched off from inside the game, so `Seats` splits the pair back into two halves and
  turns each half's stick and buttons a quarter turn. `tests/couch_test.gd` checks those
  turns against a model of SDL's own code for lone Joy-Cons.
- **Drop-outs.** When a controller disconnects, its seat keeps its character, and the
  game pauses (when everyone playing is on this screen; online, a bot fills in, and
  hands the character back when the controller returns). SDL reports a lone Joy-Con's
  Bluetooth address but gives a pair none at all, and it swaps two lone Joy-Cons for a
  pair (or back) whenever one wakes or sleeps. So a returning lone Joy-Con goes to
  whoever had that address, and a pair's halves go to the people waiting on that side
  (left or right); when that's ambiguous, any button on the half picks it up. A spare
  controller of the same kind can stand in with the join gesture, and J puts a P1 whose
  controller died back on the keyboard.
- **Who's who.** Seat colours (P1 red, P2 blue, P3 yellow, P4 green, P5 purple, P6 pink,
  P7 teal, P8 white) on each character's ring and "P2" tag, their lobby pick, and a card
  per person along the bottom of the screen.
- **Stealth on a shared screen.** If everyone on the sofa is on one team, stealth looks
  the same as online (teammates ghostly, enemies invisible). If both teams share the
  screen, hidden characters look the way teammates see them (see-through) for everyone:
  nothing can be hidden from half a sofa. Bots and players on other machines still
  can't see them, and ambushes still do double damage.
- **Menus.** Controllers never move menu focus: the ui_* joypad events are removed at
  start, and menus hear controllers through `Seats`. Any seat's + or - opens the menu
  (pausing the game when everyone playing is on this screen; online, that seat's
  character stands still instead) and that seat steers it; anyone's + or - closes it.
  From a controller the menu offers only "Keep playing" and "Back to lobby": ending the
  session is for the keyboard or mouse. In the lobby, + or - starts a 3-second countdown
  that another press calls off. The results card ignores everything for 3 s, then + or -
  means rematch. On the main menu, any controller button means Practice.
- **Input edges.** Quick taps are latched as events arrive, and a seat that hasn't been
  read for a tick (paused, captured, just joined) starts from what's already held, so
  resuming or joining never fires a stray dash.
- **Not yet:** guests on client machines (only the host's screen can share), rumble,
  a pausable clock (the satellite scan and the ambush window run on wall-clock time).

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

## Audio direction

**Now (placeholders):** everything is synthesized by `tools/make_sounds.py` out of
square, triangle, saw and noise waves, like an old console. That gives a
consistent chiptune palette, nothing to license, and a sound for every event
today, but none of it has been tuned by ear against real play yet.

| Moment | What you hear |
|---|---|
| Menus and lobby | "Lazy Afternoon": swung, jazzy music box over a walking bass (88 BPM loop) |
| Countdown | The front door closes and the parents' car pulls away |
| War | Referee whistle, then "Remote Control": bouncy A-minor chiptune (150 BPM) |
| Car in the driveway | Music cuts, *honk honk* |
| Cleanup | Whistle, then "Hide the Evidence": a frantic chase with a ticking-clock woodblock (176 BPM) |
| Last 10 seconds of either phase | The clock ticks (louder for the final three) |
| Verdict | A fanfare (spotless), a happy "ok!" (fine) or a sad trombone (grounded), then the menu music returns |
| Scoring | TV static, then a fanfare |
| Changing the channel | A rising blip every quarter of the 2-second hold |
| Weapons, specials, gags | One sound each: *pew* laser, catnip *fwoomp*, tennis-ball *thock*, egg whistle and *splat*, dust *pff*, toaster spring and *ding*, wrecking-ball whoosh, subwoofer *womp*; bark, feathers, suction, rocket fist, belly-flop *boing* and landing *thud*, claw servo and *clank*, hype arpeggio; litter *poof*, "ta-da!" for the Big Bone, a flock of tweets, a 3-second vacuum roar, satellite lock-on beeps and beam, the claw-machine jingle, a disco groove |
| Getting hit | *Bop* for small hits, *BONK* for 20+ damage, a sting on ambushes, a spring *boing* when Zoomba flips |
| KOs | Each character has a voice: meow (pitched up for Willow, down for Biscuit), yelp, tweet, robot power-down, vacuum spin-down, claw servo droop, and a tape-stop for Bass |
| Picking a character | Their happy hello: meow, *woof woof*, tweet, beep-boop, motor rev, servo whirr, bass drop + chime |
| The house | Wood cracks, a big crash when furniture breaks, a ratchet and *ding* when it's rebuilt, clatter when things get knocked over, sparkles when they're fixed |

**How it works:** the `Audio` autoload plays sounds by name (`res://assets/sounds/<name>.wav`
or `.ogg`) and music from `res://assets/music/`. World sounds are positional, so they
pan with where they happened. Every machine plays its own sounds from the same events
that draw the effects, so audio adds no network traffic. The roster names each move's
sound (`sfx`, `hit_sfx`, `land_sfx`, `swing_sfx`) and each character's `voice`. When
lots is going on, gunfire and small hits are dropped first so the important cues
always get through. Volumes (everything / music / effects) live in the main menu's
**Sound** panel and the in-match Esc menu, and are saved to `user://settings.cfg`.

**Where real audio should go next:** a composer pass on the three loops (the war
track could add a sneaky layer that rises as the clock runs down; cleanup wants a
ragtime/kazoo feel), recorded or designed SFX for the character voices (animal noises are the
hardest thing to fake with a synthesizer), a dial-up modem gag for robot KOs, keys in the lock
before the verdict. Replace any sound by overwriting the file with the same name in
`game/assets/sounds/` and deleting its recipe from `tools/make_sounds.py`.

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
  scripts/autoload/audio.gd     sound effects, music, volume settings
  scenes/menu/                  main menu, lobby
  scenes/level/                 building blocks: Room, Furniture, MessItem, BaseZone, FloorZone
  scenes/maps/                  the homes (one scene each)
  scenes/match/                 match rules, players, bots, remote, HUD, effects
  assets/sprites/               PNGs (placeholder art)
  assets/sounds/, assets/music/ WAV effects and OGG music loops (placeholder audio)
tools/make_sprites.py           regenerate placeholder sprites
tools/make_sounds.py            regenerate placeholder sounds and music
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
| **M1: Feel** | ~~Sound and music~~ (placeholder chiptune in; needs an ear and real playtests), hit-stop, screen shake, squash-and-stretch animation frames, controller rumble, a juicier whistle moment (car headlights sweep the room). |
| **M2: Real art** | Animated character sprites, furniture sprites, UI art, a pixel font, a title screen. |
| **M3: Content** | More homes (see the list above), a backyard, 2 more characters per side, home events (the doorbell, a delivery drone, the cat flap, the smart home's lights turning off). |
| **M4: Online** | Internet play without port forwarding (relay or Steam/Epic networking), invite codes, reconnects, lag compensation for hits. |
| **M5: Couch mode** | ~~Several players on one screen with gamepads~~ (in: join from the lobby, split Joy-Con pairs, per-seat cards; needs real-hardware playtests). Next: guests on client machines, per-seat rumble, "ready" checks. |
| **M6: Ship** | Steam page, demo, festival builds. |

## Open questions

1. **Who is Willow?** The prototype guesses a tabby cat. If Willow is a real pet, what are they like?
2. **Team size:** 2v2, 3v3 or 4v4? The room is tuned for 3v3.
3. **Online vs couch:** which matters more for the first public build?
4. **Is "everyone gets grounded" too harsh?** An alternative: tidiness is a score
   multiplier instead of a pass/fail gate.
5. **Should cleanup be *entirely* cooperative?** A variant: each team tidies their
   own half, and sneaky players can hide their mess on the other team's side.
