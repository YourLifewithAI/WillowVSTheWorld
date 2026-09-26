# Willow VS The World

A cozy, chaotic, isometric pixel-art multiplayer brawler. The parents just left
for the day. The **pets** and the **robots** immediately go to war over the TV
remote... and then have to put the whole house back together before the car
pulls back into the driveway.

![Pets and robots fighting over the remote in the living room](docs/images/war.gif)

**Phase 1: War for the remote.** Team capture-the-flag with over-the-top weapons.
Grab the remote, carry it to your team's rug, and hold it there for two seconds to
change the channel. Blast anyone who tries, and the furniture too. KOs are just naps.

**Phase 2: Cover it up.** *CAR IN THE DRIVEWAY!* Truce. Everyone, both teams,
rebuilds the wrecked furniture, stands lamps back up, scrubs the scorch marks and
returns the remote. The war's
winners only get to watch their show if the house passes inspection. Otherwise
everybody is grounded.

| Pick a side | Clean up together |
|---|---|
| ![Lobby: pick Team Pets or Team Robots](docs/images/lobby.png) | ![Cleanup phase with the tidiness meter](docs/images/cleanup.png) |

### The homes

Pick where the fight happens in the lobby. Each home plays differently.

| Studio Apartment | The Farmhouse | Suburban House |
|---|---|---|
| ![Studio apartment map](docs/images/map_studio.png) | ![Farmhouse map](docs/images/map_farmhouse.png) | ![Suburban house map](docs/images/map_suburbs.png) |
| Tiny, cramped, constant brawling. 2-4 players. | Wood stove, farm table, a pie on the floor. 4-6 players. | Kitchen, living room and den behind knee-walls. 6-8 players. |

...plus **The Living Room**, the original. The design doc has a list of homes
to build next and a step-by-step guide to making your own.

The full design (rules, roster, homes, art direction, networking, roadmap) is in
**[docs/GAME_DESIGN.md](docs/GAME_DESIGN.md)**.

## The characters

Everyone gets a ridiculous weapon, one big strength and one real weakness. The
pets are sneaky and chaotic, the robots have sensors and are great at repairs.

| Team Pets | Weapon | + Strength | - Weakness |
|---|---|---|---|
| **Willow**, tabby cat | Laser Pointer Blaster | Invisible when still; *Vanish*; double-damage ambushes | Fragile |
| **Biscuit**, chonky cat | Catnip Bazooka | Heavy (half knockback), sneaky | Slow |
| **Pepper**, pup | Tennis Ball Gatling | Nose sniffs out hidden enemies | Butterfingers: drops the remote when hit |
| **Kiwi**, budgie | Egg Bombs | Flies over furniture | Featherweight |

| Team Robots | Weapon | + Strength | - Weakness |
|---|---|---|---|
| **Zoomba**, robot vacuum | Dust Cannon | Hides under furniture for ambushes | Flips over when hit hard |
| **Unit-7**, helper bot | Toaster Cannon | X-ray vision; rebuilds twice as fast | Clunky |
| **The Claw**, ceiling gantry | Wrecking Ball | Rides the ceiling; lifts heavy things alone | Long reboot after a KO |
| **Bass**, smart speaker | Subwoofer Cannon | Cleaning playlist speeds up the team's tidying | No legs: tiny dash |

Everyone also has a **gag**: a big, silly, charge-up move themed on what they are,
which also plays to their strengths:

| Gag | Who | What happens |
|---|---|---|
| **Litter Bomb** | the cats | A litter box bursts into a dust cloud; cats stay invisible inside it, everyone else is bogged down |
| **Big Bone** | Pepper | Every whack is a home run, and a dog never drops the remote while holding a bone |
| **Flock Call** | Kiwi | A stampede of budgies bowls over a whole lane; Kiwi rides along at top speed |
| **Mega Suck** | Zoomba | Drags enemies in and swallows them (and the remote), then spits them out |
| **Satellite Laser** | Unit-7 | Orbital strike from space, plus a scan that reveals every hidden pet |
| **Claw Machine** | The Claw | Grabs whoever's underneath and carries them off, remote and all |
| **Dance Party** | Bass | Every enemy nearby has to dance; allies heal |

Furniture has health: the wrecking ball, bazooka and friends reduce couches, tables
and walls to rubble, which has to be rebuilt before the parents get home.

Everything makes a noise: every weapon, gag and KO (each character has their own
voice), the parents' car pulling away and honking back into the driveway, a ticking
clock in the last ten seconds, and a chiptune soundtrack for the menus, the war and
the cleanup. Volume controls are under **Sound** on the title screen and in the
Esc menu.

![All the placeholder sprites](docs/images/sprites.png)

## Play it

1. Download **[Godot 4.7](https://godotengine.org/download)** (free, the standard
   version, not .NET). It's a single ~150 MB program; nothing to install.
2. Open Godot, click **Import**, and select `game/project.godot` from this repo.
3. Press **F5** (or the ▶ button in the top right).

Choose **Practice vs bots** to play alone. Bots fill any empty spots, and you can
add or remove them in the lobby.

### Controls

| | Keyboard | Joy-Con, held sideways | Other controllers |
|---|---|---|---|
| Move | WASD / arrows | stick | left stick or D-pad |
| Attack (hold for automatic weapons) | J | left button | left face button (Xbox X, Switch Y) |
| Special | K | top button | top face button (Xbox Y, Switch X) |
| Dash | Space | bottom button | bottom face button (Xbox A, Switch B) |
| Throw the remote / hold to tidy | E | right button | right face button (Xbox B, Switch A) |
| Gag (when the meter is full) | I or Q | SL or SR | a shoulder button or trigger |
| Menu (pauses in Practice) | Esc | + or - | Start or Back |
| Fullscreen on/off | F11 or Alt+Enter | | |

Buttons go by position, not by the letter printed on them, so a Joy-Con works the
same whichever way round it is.

### Everyone on one screen (Joy-Cons and a TV)

Up to 8 people can play on one computer, each with their own controller, all on
one screen (cast or plug the laptop into the TV).

1. **Pair each Joy-Con with the computer.** Windows: *Settings > Bluetooth & devices >
   Add device > Bluetooth*. Mac: *System Settings > Bluetooth*. Hold the small round sync
   button on the Joy-Con's inner edge (between SL and SR) until its lights run, then pick
   "Joy-Con (L)" or "Joy-Con (R)" from the list. Other controllers pair the same way or
   just plug in.
2. **Start the game** and choose **Practice vs bots** (or **Host a game** if friends
   elsewhere are joining too).
3. **In the lobby, everyone presses any button** on their controller. The first person
   becomes P1, the next P2, and so on. Each person's tag (P1 red, P2 blue, P3 yellow,
   P4 green...) marks their character on the character list, over their character's head
   and on their card at the bottom of the screen.
4. **Push the stick left or right** to change character. Anyone's **+ or -** starts
   the match. Add bots with the buttons on the left to fill out the teams.

Good to know:
- **A left and right Joy-Con count as two players** even though the computer merges
  them into one controller. Each half is held sideways by a different person.
- **If a Joy-Con disconnects** (they doze off after a while), wake it and press any
  button: its player gets it back. Any spare controller works too.
- **+ or - opens the menu**, and in Practice it pauses the game. The stick picks, the
  bottom button chooses.
- **Invisible cats and hidden Zoombas** can't be invisible to only half a sofa, so on a
  shared screen they show as a faint shimmer that you have to watch for.
- **Playing alone?** No joining needed: the keyboard and any controller just work.

### Playing with friends

- **Same Wi-Fi / LAN:** one person clicks **Host a game**. The lobby shows their
  local IP address. Everyone else types that IP into the box next to **Join**.
- **Over the internet:** the host must forward **UDP port 7777** on their router,
  and friends join with the host's public IP. The easier route is a free virtual
  LAN like [Tailscale](https://tailscale.com) or ZeroTier: everyone joins the same
  network and uses the host's Tailscale IP. Proper online matchmaking is on the roadmap.
- **Testing alone:** in the Godot editor, *Debug > Customize Run Instances...*,
  enable multiple instances, and run 2. Host in one window and join `127.0.0.1` in the other.

## Working on it

```
game/                     the Godot project (open game/project.godot)
  scenes/maps/            the homes: open one and drag furniture around
  scenes/level/           the building blocks every home is made of
  scenes/match/           rules (match.gd), characters (player.gd), bots, HUD
  scripts/core/roster.gd  every character's stats and moves (the balance sheet)
  assets/sprites/         pixel art (placeholders)
docs/GAME_DESIGN.md       the game design document
tools/make_sprites.py     regenerates the placeholder sprites from text grids
tools/make_sounds.py      synthesizes the placeholder sound effects and music
tools/smoke_test.sh       headless end-to-end tests
```

- **Tweak balance** in `game/scripts/core/roster.gd` and the `@export` values on
  the `Match` node (war/cleanup length, capture limit, respawn time).
- **Rearrange a home** by opening its scene in `game/scenes/maps/`. The room and
  furniture draw themselves right in the editor; change sizes, colours, windows and
  doors in the inspector. To add a new home, see *Making a new home* in the design doc.
- **Replace the art:** drop a PNG with the same name into `game/assets/sprites/`
  (for example `willow.png`). Characters face right, and the bottom of the image
  is where they touch the floor. [Aseprite](https://www.aseprite.org) is the go-to
  pixel-art tool. The placeholders come from `python3 tools/make_sprites.py`
  (needs `pip install pillow`); delete an entry there once you have real art for it.
- **Replace the sounds** the same way: overwrite the `.wav` with the same name in
  `game/assets/sounds/` (or swap it for an `.ogg`, deleting the `.wav`). Music lives in
  `game/assets/music/` as `menu`, `war` and `cleanup`. The placeholders come from `python3 tools/make_sounds.py`
  (needs `pip install numpy soundfile`). Each move's sound is named in the roster
  (`sfx`, `hit_sfx`, ...), so you can also point a move at a different sound there.

### Tests

```
tools/smoke_test.sh path/to/godot
```

Runs headless (no window): imports the project, checks that every sound the game
asks for exists, plays a full 3v3 bot match on every home at top speed (checking the
phase sounds and music fire), then plays a real host + client network match over
localhost and checks that both machines agree on the map and the result. Takes
about a minute and a half. The same
checks run on GitHub for every push (`.github/workflows/smoke-test.yml`).

The game also takes launch options after `--`, which the tests use:
`--practice`, `--host`, `--join=IP`, `--map=studio`, `--bots=N`, `--char=willow`, `--autostart=N`,
`--autopilot`, `--war=SECONDS`, `--cleanup=SECONDS`, `--quit-after=SECONDS`,
`--screenshot=PATH@SECONDS`, `--mute`, `--audio-log` (prints every sound as it plays). For example, `godot --path game -- --practice --bots=5 --autostart=1`
drops you straight into a 3v3 match.
