<p align="center"><img src="assets/icon.png" width="160" alt="TECTICA"></p>

# TECTICA

A tactical military shooter for **Godot 4.7** (GDScript, Forward+), playable in top-down or first person —
campaign chapters, zombie survival, online co-op and PvP deathmatch.
Soldiers, the forest map, FX and sound are generated in code; the other maps, most guns and some props come from asset packs.

## 🎬 Trailers

| Gameplay trailer (30 s, 4K 60 fps) | Rifle reveal (30 s, 4K 60 fps) |
|---|---|
| [![Watch the TECTICA gameplay trailer](docs/screenshots/v139-gameplay-trailer-thumb.jpg)](https://github.com/Ai-Sukmoren/TECTICA/releases/download/v1.39.0-beta/tectica-gameplay-trailer.mp4) | [![Watch the TECTICA rifle reveal](docs/screenshots/v139-rifle-reveal-thumb.jpg)](https://github.com/Ai-Sukmoren/TECTICA/releases/download/v1.39.0-beta/tectica-rifle-reveal.mp4) |
| Weapon inspect, then the gunsmith in one take: attachments installed and swapped, attachment skins, gun skins, ending on the exact P90 from the gameplay. Through its reflex sight into real Backrooms combat: a 120 fps slow-motion headshot, a tactical reload, a weapon switch and a scoped kill. | The battle rifle in a dark studio: macro details, the gun taken apart, its bolt cycled, and a 360° orbit. Specs are the game's own values. |

## 🆕 What's new in v1.52.3

**[Download the latest version](https://github.com/Ai-Sukmoren/TECTICA/releases/latest/download/TECTICA-Windows.zip)** · [release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.52.3-beta)

- **Less kick on four more guns:** the SIG MCX Spear, Q Honey Badger, FN SCAR-H and FN SCAR-SC now recoil like SMGs (short, flat, quick to settle); the MCX Spear and both SCARs climb much less per shot. They still handle like rifles.

## What came in v1.52.2

[release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.52.2-beta)

- **Iron sights fold down under an optic:** on the AUG A4, CZ Bren 2, SCAR-SC, Q Honey Badger, SIG MCX Spear and Magpul PDR-C the flip-up irons stand on iron sights and lie flat on the rail once a sight is fitted.
- **Assault rifles kick like SMGs:** a shorter, flatter kick that settles faster (AUG A4, AUG A1, CZ Bren 2, HK33, AS VAL); they still handle like rifles.

![Irons standing, then folded under a reflex sight (AUG A4, Magpul PDR-C)](docs/screenshots/v1522-iron-fold.jpg)

## What came in v1.52.1

[release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.52.1-beta)

- **Skins sit on the gun's body:** the receiver, upper and rail housing take the skin; plastic and wood furniture, bare steel, the magazine and every attachment keep their factory look (your own part skins still apply).

## What came in v1.52

[release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.52.0-beta)

- **Seven new guns:** AUG A4, CZ Bren 2, SCAR-SC, Q Honey Badger, SIG MCX Spear, HK MP7 A1 and Magpul PDR-C, in the loadout and the Zombie Survival shop.
- **Side-rail laser:** the laser clamps to the side rail in its own slot, so it works together with an underbarrel part; saved lasers move over automatically.
- **Two foregrips:** angled and vertical, fitted to each gun's handguard, less recoil, take any finish.
- **Laser fix:** a holstered gun no longer draws a second laser beam.
- **Weapon light** lies straight on every gun and sits on the side rail of the P90 and MGP7.

## What came in v1.51

[release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.51.0-beta)

- **No first-wave hitches:** every first-wave infected body is built under the loading screen (worst arrival frame 42 -> 15 ms in wave 1).
- **Smoother loading screen:** weapon and infected warm-ups are built a few per frame instead of in one freeze.
- **Multiplayer:** a teammate's gun now points where they aim, up and down, including hip fire.
- **Zombie Survival opening:** pick the mode on one loading screen, arcade map marker, controller prompts, no ammo refill when full, controls shown earlier.
- **Range:** vault hints, and a clean handoff out of the wave shop.

## What came in v1.50

[release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.50.0-beta)

- **Big infected fights run much faster:** 28 infected 118 -> 185 fps; 45 infected no longer drop to 15 fps (now a steady 60 with the cap on).
- **New physics engine (Jolt):** movement and hits feel the same, at less than half the cost per infected.
- **Faster loading:** Forest loads in 2.27 s (was 2.53 s), the game boots in 4.5 s (was 5.0 s).

## What came in v1.49

[release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.49.0-beta) · [watch before / after](https://github.com/Ai-Sukmoren/TECTICA/releases/download/v1.49.0-beta/tectica-light-reload-1.49.mp4)

- **Weapon light fits every gun:** straight under the handguard or frame, ahead of the hand, never floating or tilted.
- **Reloads:** back to the v1.46 motion, and switching weapons cancels a reload.
- **Easier rifles:** 25 % less recoil on all nine rifles.
- **Auto vault** while sprinting can be turned off in Settings > Game.
- **Online hosting:** fixed "FUNNEL FAILED" when hosting right after start-up.

## What came in v1.48

[release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.48.0-beta)

- **Gunsmith without hitches:** changing an attachment went from up to 351 ms to at most 18 ms.
- **Faster loading:** no more half-second freeze in every map load; Backrooms loads in 1.2 s instead of 4 s and Tokyo in 1.2 s instead of 3.3 s, with half the video memory.
- **Startup** to the menu is 4.8 s instead of 6.4 s, and the loading screen no longer freezes while the forest grass is made.

## What came in v1.47

[release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.47.0-beta) · [watch the animation update](https://github.com/Ai-Sukmoren/TECTICA/releases/download/v1.47.0-beta/tectica-update-1.47.mp4)

- **Classic operators back:** multicam, plate carriers, packs and NVG helmets; deathmatch bots are militia again.
- **Reloads you can see:** the magazine change happens in view, with the gun side-on instead of pointing at the sky.
- **Sprint, bolt actions, recoil:** a high-port sprint carry, bolts worked off the cheek, and recoil that differs by gun type.
- **Climbing with a rifle:** both hands on the ledge, rifle slung. **Zombies** swipe one arm at a time.
- **Phones:** lighter graphics and physics, at most 16 infected at once, and a download less than half the size (Backrooms and Tokyo are PC-only).

| Reload, before and after | Sprint carry |
|---|---|
| ![Reload](docs/screenshots/v147-reload.jpg) | ![Sprint](docs/screenshots/v147-sprint.jpg) |

## What came in v1.46

[release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.46.0-beta) · [watch the trailer (60 s)](https://github.com/Ai-Sukmoren/TECTICA/releases/download/v1.46.0-beta/tectica-update-1.46.mp4)

[![Watch the 1.46 trailer](docs/screenshots/v146-devlog-thumb.jpg)](https://github.com/Ai-Sukmoren/TECTICA/releases/download/v1.46.0-beta/tectica-update-1.46.mp4)

- **Climbing:** Space at a 0.5–2 m ledge climbs onto it; jump and hold Space to grab a higher one. Tested on every map.
- **New operators:** every character in the Task Force kit, each outfit with its own visor colour; bots wear operator outfits.
- **Knives:** a real grip round the handle, a reverse-grip karambit, and forehand, backhand and thrust attacks.
- **Zombie Survival:** 28 infected hold 60 fps, no freeze when the first wave arrives, and a new wave HUD with a countdown.
- **Loading:** a new loading screen with real progress; the longest load freeze dropped from 4.5 s to about 1 s.
- **Also:** SCAR-H iron sights line up, and the gunsmith rebuilds only the gun you change.

![The operators](docs/screenshots/v146-characters.jpg)

## What came in v1.45

[release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.45.3-beta) · [watch the update (2.5 min)](https://github.com/Ai-Sukmoren/TECTICA/releases/download/v1.45.0-beta/tectica_v145_update.mp4)

### Story cutscenes
Both chapters open with an in-engine cinematic that glides straight into play: **Chapter 1** flies KILO-1 into the
valley at dawn and leaves him alone on the pad; **Chapter 2**, twelve hours later, reveals the radio outpost on the
ridge while the camp still burns. Letterboxed, with subtitled radio dialogue and synthesised ambience. Hold SPACE to
skip; SETTINGS > GAME > STORY CUTSCENES turns them off.

### Stealth
Guards notice you gradually (a ring over each one fills), investigate noises, find and radio in bodies, and search
as a squad. Sneak up behind one: **V** is a knife takedown, **F** a silent choke-out. **F** drags a body by the collar into bushes or shadows,
**J** throws a decoy, **Alt** slow-walks. Suppressors cut how far shots carry; walls muffle sound.

### v1.45.2: real carbon fibre
The **Carbon Weave** and **Mythic Carbon** skins now use a photographed twill weave under clear lacquer (v1.45.3: Mythic Carbon too). ![Carbon Weave](docs/screenshots/v1452-carbon-weave.png)

### v1.45.1: smarter cover
Guards lean out round cover to shoot (and can be hit where they lean), grade cover by how exposed the route to it is,
only pick spots they can fire from, spread out as a squad, and re-grade when you move.

| Chapter 1 cutscene | Chapter 2 cutscene | Takedown |
|---|---|---|
| ![Chapter 1](docs/screenshots/v145-ch1-cutscene.jpg) | ![Chapter 2](docs/screenshots/v145-ch2-cutscene.jpg) | ![Takedown](docs/screenshots/v145-stealth-takedown.jpg) |

## Earlier: v1.44

[Release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.44.0-beta)

### A better first five minutes
- **Play as guest.** A PC with no accounts goes straight to the title menu as GUEST, with no username or password. The
  sign-in screen also has **PLAY AS GUEST**, and the guest's **CREATE ACCOUNT** keeps everything it earned.
- **New players start in Training.** Until you finish Training or a chapter, DEPLOY starts THE RANGE, and the title
  screen shows its own mission card.
- **Chapter 1 starts hot.** Gunfire carries from the logging camp in the first seconds and the radio calls it in.
- **A cleaner HUD.** The briefing bars sit under the HUD, so ammo, health and the compass stay readable. The objective
  marker never covers the weapon panel or the radar, and the controls hint fits between the panels.
- **A shorter title menu.** GRAPHICS and MUSIC moved into SETTINGS (M still mutes the music).

| Play as guest | Training first | Chapter 1 opening |
|---|---|---|
| ![Guest sign-in](docs/screenshots/v144-guest-signin.jpg) | ![Training by default](docs/screenshots/v144-training-default.jpg) | ![Chapter 1 opening](docs/screenshots/v144-chapter1-opening.jpg) |

## Earlier: v1.43

[Release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.43.1-beta)

### v1.43.1: attachment fit
Under-barrel rails now sit flush on every gun: no more floating bars, they follow sloped handguards and slide to
the nearest flat spot. Guns where a rail never looked right (VP9, P90, AUG A1, L96A1, Mosin, Marlin, MGP7) no longer
take one, and the P90 no longer takes a laser. Saved loadouts with those parts simply drop them.
Skinned suppressors are solid again: under a skin the normal suppressor looked hollow and partly see-through.

### Training mode
New to TECTICA? Pick **MODE → TRAINING** on the title screen. A guided course on its own map, THE RANGE, teaches every
move in 16 steps: look, walk, sprint, vault, crouch, slide, shoot, aim down sights, reload, peek, switch weapons, throw a
grenade, dropkick, bullet time, and finally a live-fire kill house. Each step shows your own keys (or gamepad buttons);
range targets stand still and don't shoot, and going down puts you back at the last step. Finish it once for
**+250 credits**, then Enter goes straight into Chapter 1.

| A step with its keys | Live fire | Done |
|---|---|---|
| ![Training step](docs/screenshots/v143-training-step.jpg) | ![Kill house](docs/screenshots/v143-training-killhouse.jpg) | ![Training complete](docs/screenshots/v143-training-complete.jpg) |

## Earlier: v1.42

[Release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.42.0-beta)

### New first-person animation
Both hands stay on the gun while running and sprinting, with the wrists in line with the forearms. Aiming no longer
swings the right arm up into view or twists the forearm. Every gun class has its own weight: pistols are quick,
rifles and heavy guns lag behind fast turns, and the gun breathes at rest and dips on landing. Checked on every
weapon at 30, 60 and 144 fps.

| Rifle sprint, before (left) and now (right) |
|---|
| ![Sprint before and after](docs/screenshots/v142-sprint-before-after.jpg) |

### Bullet time
A **FOCUS** meter (above health) for solo and vs-AI play: aim or fire while vaulting, sliding, jumping or kicking
to slow time. Kills fill it, headshots more. You can now shoot in the middle of a vault.

### Smoother vaults, smarter bots
The vault lifts the body over the obstacle itself, so no more floating in mid-air or clipping through the edge, and
it always lands on solid floor (93 vaults checked across every map). Under fire, bots run to cover, crouch and peek
around corners; in deathmatch they leave cover when things go quiet.

| Bullet time | Vault |
|---|---|
| ![Bullet time](docs/screenshots/v142-bullet-time.jpg) | ![Vault](docs/screenshots/v142-vault.jpg) |

### Real gun sounds
Recorded gunshots, magazine and bolt sounds for every gun (CC0 libraries, see Credits), with an echo indoors.

### Also new
- **Mythic Ruby** (admin skin): its sticker now wraps the whole gun, printed into the surface. **EDIT STICKER** in
  the ARMORY moves it (drag), sizes it (wheel) and turns it (right-drag); **FULL WRAP** resets it. Admins can put it
  on any skin.
- Fixed: rail attachments on the AS VAL and P90 showed as a short stub; the ARMORY dropped your attachments (the optic
  disappeared) while placing a sticker.

| Editing the sticker | On another skin (admin) |
|---|---|
| ![Sticker editor](docs/screenshots/v142-sticker-edit.jpg) | ![Sticker on Gilded Royale](docs/screenshots/v142-sticker-any-skin.jpg) |

## Earlier: v1.41

[Release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.41.0-beta)

### Solid maps, smooth stairs
Stairs and kerbs walk without jumping (for bots and zombies too), map collision no longer lets you fall through
bridges or into walls, and the Shift + Space vault can't pass through walls or out of the map any more. TOKYO's
west edge, long stair and planters are fixed.

### Arcade shop
The shop now looks like the gunsmith, with the item's gun on a turntable. Upgrade any gun you carry, and pick which
gun your attachments go on with **FIT TO**.

| FIT TO on the pistol | Attachment preview |
|---|---|
| ![FIT TO](docs/screenshots/v141-shop-fit-to.jpg) | ![Preview](docs/screenshots/v141-shop-preview.jpg) |

## Earlier: v1.40

[Release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.40.0-beta)

### New map: TOKYO
A walled-in Tokyo back street by a canal and a rail line, for Zombie Survival and matches against AI.

| From above | The west plaza |
|---|---|
| ![TOKYO from above](docs/screenshots/v140-tokyo-overview.jpg) | ![TOKYO west plaza](docs/screenshots/v140-tokyo-plaza.jpg) |

### Zombie Survival: arcade shop, bought attachments
The shop is an arcade cabinet near the start of every zombie map: walk up between waves and press **F**.
Guns start bare; attachments for the gun in hand are bought with points and last for the run.

| The arcade | Attachments in the shop |
|---|---|
| ![Arcade shop](docs/screenshots/v140-arcade-shop.jpg) | ![Shop attachments](docs/screenshots/v140-shop-attachments.jpg) |

### Also new
- **Remington 700** bolt-action rifle with its own scope.
- Title menu: one **MODE** choice (campaign, zombie, TDM vs AI, FFA vs AI) with only its MAP / AI BOTS rows; all text in a 16-bit pixel font.
- Gunsmith preview zooms with the mouse wheel, **R** resets it.
- DEAD END and ATOMIC ACRES removed.

| Title menu | Gunsmith zoom |
|---|---|
| ![Menu](docs/screenshots/v140-menu.jpg) | ![Gunsmith zoom](docs/screenshots/v140-gunsmith-zoom.jpg) |

## Earlier: v1.39

[Release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.39.0-beta)

### New first-person hands
The original TECTICA arms are back in first person, with a rebuilt glove: rounded palm, jointed fingers with knuckles,
a two-part thumb, hard knuckle pads and a slim cuff with a wrist strap. Every gun and knife keeps its grip.

<p align="center"><img src="docs/screenshots/v139-hands-scar.gif" width="560" alt="New hands on the FN SCAR-H: fire, aim and reload"></p>

| Before (left) and after (right) |
|---|
| ![Old glove next to the new glove](docs/screenshots/v139-glove-before-after.jpg) |

The green glow that lit the operator's body (also on the title menu) is gone; the chem sticks on the vest still glow.

### Newest guns (v1.34)
| Gun | Type |
|---|---|
| **FN SCAR-H** | 7.62 battle rifle |
| **FN P90** | SMG with a 50-round top magazine |
| **L96A1** | Bolt-action sniper with a built-in 10x scope |
| **Mosin-Nagant 91/30** | Bolt-action rifle on iron sights, 5 rounds |

All four take gunsmith attachments, cycle their bolts after every shot and are in the Zombie Survival shop.

![FN SCAR-H, FN P90, L96A1 and Mosin-Nagant in first person](docs/screenshots/v139-new-guns.jpg)

### Every weapon, every animation
All 17 weapons with the new hands: draw, walk, hip fire, aim, reloads, inspect, sprint and grenade throw (about 4½ minutes).

[![Watch all 17 weapons with the new hands](docs/screenshots/v139-all-guns-thumb.jpg)](https://github.com/Ai-Sukmoren/TECTICA/releases/download/v1.39.0-beta/all_guns_new_hands.mp4)

## Earlier: v1.21

[Release notes](https://github.com/Ai-Sukmoren/TECTICA/releases/tag/v1.21.0-beta)

### Nine new attachments
Prism 2.5x, pistol mini red dot, heavy suppressor, muzzle booster, stubby grip, handstop, hollow points, taped dual mag and folding stock. Every attachment now sits flush on every gun.

![Guns built with the new attachments](docs/screenshots/v121-attachments.jpg)

| Looking through the Prism 2.5x | Zombie Survival shop (v1.18) |
|---|---|
| ![Prism sight picture](docs/screenshots/v121-prism-ads.jpg) | ![Zombie shop](docs/screenshots/v118-shop.jpg) |

### Custom crosshair
Nine styles (including a dot), eight colours, size, opacity, outline and spread, with a live preview in **Settings → GAME**.

| Settings with live preview | Styles in game |
|---|---|
| ![Crosshair settings](docs/screenshots/v121-crosshair-settings.jpg) | ![Crosshair styles](docs/screenshots/v121-crosshair-styles.jpg) |

### Night vision goggles
Press **N** to see in the dark. Left: night vision off, right: on (Dead End, Pinewood Valley, top-down).

![Night vision off and on](docs/screenshots/v121-nvg.jpg)

### Carbon Phantom
An all-black carbon-weave combat suit and the Mythic Carbon gun skin.

![Carbon Phantom outfit](docs/screenshots/v121-carbon.jpg)

## ▶ Promo video

### Gameplay trailer (v1.24)

[![Watch the TECTICA gameplay trailer](docs/screenshots/gameplay-trailer-thumb.jpg)](https://github.com/Ai-Sukmoren/TECTICA/releases/download/v1.24.2-beta/TECTICA_gameplay_trailer.mp4)

*Real play on Pinewood Valley and Dead End: night vision, the supply shop, boss waves, the DB-2 Twirler and the Juggernaut (MP4, 47 s).*

### First promo

[![Watch the TECTICA promo video](docs/screenshots/promo-thumb.jpg)](https://github.com/Ai-Sukmoren/TECTICA/releases/download/v1.16.0-beta/TECTICA-promo.mp4)

*Click the image to watch the promo (MP4, 36 s).*

### 13 November update (v1.15 - v1.17)

[![Watch the TECTICA update promo](docs/screenshots/update-promo-thumb.jpg)](https://github.com/Ai-Sukmoren/TECTICA/releases/download/v1.17.0-beta/TECTICA_v1.17_update_promo.mp4)

*Visual upgrade, running animation, knives, co-op zombies on every map and phone touch controls (MP4, 49 s).*

### Knife showcase (v1.16)

[![Watch the TECTICA knife showcase](docs/screenshots/knife-showcase-thumb.jpg)](https://github.com/Ai-Sukmoren/TECTICA/releases/download/v1.16.0-beta/TECTICA-knife-showcase.mp4)

*Combat knife, karambit and butterfly knife with their inspect animations (MP4, 24 s).*

### Screenshots (v1.17 visual upgrade)

| Dead End, first person | Dead End, top-down | Pinewood Valley, first person |
|---|---|---|
| ![Dead End first person](docs/screenshots/town-fp-v1.17.jpg) | ![Dead End top-down](docs/screenshots/town-td-v1.17.jpg) | ![Pinewood Valley first person](docs/screenshots/forest-fp-v1.17.jpg) |

*Brick, siding and plaster facades, worn asphalt and road paint, weeds, detailed cars, lit city skyline, matte helmets and leather boots, star-shaped muzzle flash.*

## ⬇ Download & play (Windows)

**[Download TECTICA for Windows (.zip)](https://github.com/Ai-Sukmoren/TECTICA/releases/latest/download/TECTICA-Windows.zip)**

1. Unzip the download anywhere and run **`TECTICA.exe`**.
2. If Windows SmartScreen warns about an *unknown publisher*, click **More info → Run anyway** (the game isn't code-signed).
3. Create an account (username + 4-digit password) — accounts stay on your PC and keep your credits, skins and progress.

Needs a 64-bit Windows 10/11 PC with a Vulkan-capable graphics card.

### Play together
- **Open rooms:** the host chooses **MULTIPLAYER → ONLINE · TAILSCALE FUNNEL** and hosts a match.
  Other players choose **OPEN ROOMS** and click the host's room. Joining players only need the game.
  The online host needs Tailscale with Funnel enabled. Rooms expire after 45 seconds without a host update.
- **Community service:** the room directory and global sign-in dashboard run on the owner's PC.
  That PC must stay awake, online, and signed into Windows. Updated clients report successful local
  sign-ins with the username, timestamp, game version, and a random installation ID. Offline reports
  are queued for retry. The global dashboard requires the owner's private key on the server PC.
- **Host:** **MULTIPLAYER**, then **HOST CO-OP** or **HOST PVP DEATHMATCH**. Your **join code** (5 characters, for
  example `B7AHG`) is shown on the multiplayer screen, in the top-left corner while you play, and under
  **Esc → COPY JOIN CODE**. Tell it to your friends.
- **Co-op zombies on any map:** on **HOST CO-OP**, press A/D (or ←/→) to pick a chapter or
  **ZOMBIE SURVIVAL** on any map (Pinewood Valley, Dead End). Friends who join load the same map.
- **PvP on any map:** on **HOST PVP DEATHMATCH**, press A/D (or ←/→) to pick Pinewood Valley or Dead End.
- **Join a friend:** **MULTIPLAYER → JOIN**, type the code, press **Enter**.
- A 5-character code works for friends on the **same Wi-Fi / network** or on the **same Tailscale network**
  (there is one code for each). The code is the host's address packed into a few letters; there is no lobby server.
- **Over the internet without Tailscale (direct, peer to peer):** when hosting, the game asks the router to open
  UDP port 7777 itself (UPnP). The host uses **Esc → COPY INVITE LINK · INTERNET**, which also gives a 7-character
  code and says whether the router opened the port. If UPnP is off on the router (or the ISP uses carrier-grade NAT),
  forward UDP 7777 by hand or host *ONLINE* instead.
- **Online (Tailscale Funnel):** switch **CONNECTION** to *ONLINE*; the host needs [Tailscale](https://tailscale.com)
  with Funnel enabled and shares the invite link, friends need nothing extra.
- Invite links (`tectica://join/...`) and plain IP addresses still work in the JOIN row; Ctrl+V pastes.
- Join codes need the default port 7777. Windows asks once to allow TECTICA through the firewall: say yes on the host.
- Everyone must run the same version of the game.

### Weapon skins
Earn credits in play (kills, cleared waves, mission grades, PvP), then open supply packs in the **ARMORY** —
190 skins across 5 rarities. Credits can't be bought; there are no purchases.

## Run from source
> **Assets not in this repository.** The optional third-party packs under `assets/thirdparty/` (see Credits) and the
> sticker artwork under `assets/stickers/` are not redistributed here because their licenses don't allow it. The game
> runs without them: props, grenades and bodies fall back to the built-in procedural models, and the two pack weapons
> (MGP7, ZC57) need the Alstra pack copied into `assets/thirdparty/alstra_shooter_essentials/`.

Clone this repository, open the folder in Godot 4.7 and press F5, or:
```
git clone https://github.com/Ai-Sukmoren/TECTICA.git
godot --path TECTICA
```

## Controls
| Action | Keyboard / Mouse | Gamepad (Xbox layout) |
|---|---|---|
| Move | WASD | Left stick |
| Aim | Mouse | Right stick (twin-stick, light aim assist) |
| Fire / aim down sights | LMB / RMB | RT / LT |
| Sprint | Shift (hold) | L3 (toggle) |
| Vault low obstacle | Space (or sprint into it) | A (or sprint into it) |
| Bullet time (solo / vs AI, needs FOCUS) | Aim or fire while vaulting, sliding, jumping or kicking | LT / RT, same moves |
| Peek left / right | Q / E | LB / RB |
| Crouch (slide while sprinting) | C / Ctrl | B |
| Reload | R | X |
| Inspect weapon (aim/fire cancels immediately) | I | - |
| Switch weapon | 1 / 2 / X | Y |
| Frag grenade | G | D-pad down |
| Night vision goggles | N | - |
| Zombie shop (between waves) | B | - |
| First person on/off | F | R3 |
| Rotate camera | Z / V | D-pad left / right |
| Zoom | Mouse wheel | D-pad up (cycle) |
| Debug panel / pause | F1 / Esc | Back / Start |
| Graphics preset (Low/High/Ultra) / music | F2 / M | - |
| Restart (after mission) | Enter | A |

The game switches between mouse and gamepad automatically, depending on which you touched last. Gamepads also rumble on shots, hits and landings.

The title menu sets view mode, graphics and music. Music is generated at startup and crossfades from an ambient track to a combat track when enemies engage you.

Green ammo cans resupply ammo and +35 HP.


## Tactical systems
- **Frag grenades** for you (2 in Operation, 3 in Zombie; ammo cans give +1, each cleared wave gives +2) and for the enemy AI, which lobs them at your last known position when you hide behind cover. Blasts are blocked by walls and cover, and an incoming grenade triggers an on-screen warning with its direction.
- **Stealth by sound**: footsteps are audible. Sprinting near guards makes them suspicious, while walking, aiming or crouching is silent. Gunfire (unless suppressed) and explosions alert everyone nearby.
- **Health regeneration** after 5 s without taking damage (up to 100 in Operation, 70 in Zombie).
- **Feedback**: red arcs point toward whoever hit you; hit and kill sounds; a heartbeat, muffled audio and drained colour at low health.
- **Mission grade** (S/A/B/C) in Operation, scored on time, accuracy, headshots and damage taken.
- **Pause menu** (Resume / Settings / Restart / Quit to title) and **Settings** (sensitivity, first-person FOV, master/music/effects volume, camera shake, FPS counter, film grain, V-Sync), saved to `user://settings.cfg`.

## Campaign (chapters 1 and 2)

Pick a chapter under **MODE** on the title screen. Finishing Chapter 1 goes
straight into Chapter 2 (Enter / A). Best grades are saved to
`user://campaign.cfg`.

| Chapter | Time | Objectives |
|---|---|---|
| 1. TIMBERLINE | 08:00 → day | Infiltrate the logging camp → eliminate the garrison → **hold F** to download the intel → exfil to the river crossing |
| 2. NIGHTFALL | 20:36 → night | Infiltrate the radio outpost → plant a charge on the **generator** (all floodlights and the searchlight die) → blow up the **radio tower** (it topples) → reach the LZ → hold it against two enemy waves until the helicopter lands |

The current objective is shown at the top of the screen with an on-screen
waypoint, its distance, and a marker on the minimap.

## Pinewood Valley (the map)

A 200 × 200 m forest with:

- more than 1,100 pine and broadleaf trees, plus bushes, wind-blown grass,
  boulders and fallen logs;
- dirt roads, and a creek with a log bridge;
- the logging camp (cabins, sawmill, campfire, watchtower);
- the radio outpost (HESCO walls, a radio tower, a generator, a bunker,
  tents, a searchlight tower);
- two helicopter landing zones and a ruined hunter's cabin with supplies.

Trees and rocks stop bullets and give cover (the AI uses them too). Crouching
inside a bush makes you much harder to spot. In top-down view, treetops and
roofs near you turn see-through.

## Day / night

A real-time cycle (one in-game hour per real minute):

- the sun moves across the sky and turns golden at sunrise and sunset;
- at night a moon and stars come out, with morning mist;
- camp lamps, the campfire and the outpost floodlights switch on at dusk.

At night enemies see much less far, unless your flashlight (**T** / Back) is
on. Enemies carry weapon lights after dark. Zombie mode starts at a blood-red
dusk.

## Destructible environment

Crates, crate stacks, sandbags, barrels, concrete barriers, desks, shelving and
the map table can all be destroyed. Bullets chip them, knock loose small pieces
(bags, boards, ammo boxes) and make them sag. Frag grenades wreck them.
Sandbags shrug off most rifle fire, and concrete barriers need explosives.
Red barrels explode and chain-react. A destroyed prop bursts into physics
fragments, its AI cover points and radar outline are removed, and the
navigation mesh re-bakes so soldiers and zombies path through the gap.
Containers, the truck and walls stay solid.

## Settings

The Settings screen (title menu or pause menu) has three tabs:
**GAME / VIDEO / AUDIO**. Switch tabs with Q/E or LB/RB.

- **VIDEO:** quality preset (LOW, HIGH, ULTRA, or CUSTOM once you change an
  option), first-person FOV (60–110°), top-down FOV, render scale (FSR below
  100%), anti-aliasing (FXAA, MSAA 2x/4x, TAA), shadows, ambient occlusion,
  reflections, SSIL, global illumination, volumetric fog, bloom, brightness,
  retro CRT filter, film grain, display mode, frame-rate limit and V-Sync.
- Everything saves to `user://settings.cfg`.

## Retro theme

UI text uses pixel fonts: Pixelify Sans for body text and Press Start 2P for
headlines, both under the SIL Open Font License (see `assets/fonts/`). The UI
uses a phosphor-green / amber palette, and an optional CRT scanline overlay
sits on top of everything.

## Game modes
- **Training**: a guided course on THE RANGE that teaches the controls step by step, ending in a live-fire kill house.
- **Operation**: clear the compound of 10 hostiles. Enemies use cover, peek, flank and alert each other.
- **Zombie Survival**: endless waves of infected soldiers (walkers, runners from wave 2, armored brutes from wave 4).
  Each wave has 6 + 4n zombies with about 18% more health per wave. Spawns slow down when your HP is low.
  Between waves you get +35 HP and an ammo refill. The run ends when you die, and your best wave and score are recorded.

## Guns, attachments and classes
Pick **LOADOUT** on the title menu to open the **Gunsmith**. A/D on the menu row switches class.

| Primary | Type | Notes |
|---|---|---|
| M4A1 | Assault rifle | All-rounder |
| AK-47 | Assault rifle | Hard-hitting, heavy recoil |
| AS VAL | Assault rifle | Integrally suppressed |
| MP7 | SMG | Fast handling, fast fire rate |
| AWP | Sniper | Bolt-action, 120 damage, 8x scope with scope overlay |
| M870 | Shotgun | Pump-action, 8 pellets |
| M249 | LMG | 100-round box, bipod |

Secondaries: **MK23**, **Glock 18** (full auto).

Attachment slots (options depend on the gun):
- **Optic**: iron, red dot, holo, ACOG 4x, 8x scope
- **Muzzle**: suppressor, compensator, flash hider, muzzle brake, choke
- **Underbarrel**: vertical grip, angled grip, laser, bipod
- **Magazine**: extended, drum, fast
- **Stock**: light, heavy

Every attachment changes the real stats: damage, fire rate, range, accuracy, recoil, mobility, ADS speed, magazine size, reload time and noise.

**Attachment skins:** every attachment and the magazine can wear its own skin. In the Gunsmith, on an attachment row press
**Q / E** (LB / RB) or click its **SKIN** tag: *match the gun*, *factory*, or any finish you own on that gun. Other players see them.

Classes: ASSAULT, RIFLEMAN, RECON, CQB, BREACHER, SUPPORT, SPEC OPS. Each is fully editable and saved to `user://loadout.cfg`.

## Structure
```
project.godot             Godot 4.7 project (Forward+; the web build uses Compatibility)
export_presets.cfg        Windows Desktop and Web exports (to ../builds/)
scenes/                   main.tscn, loading screen
assets/                   icon, logo, fonts, skins; assets/thirdparty/ is local-only (see Assets)
scripts/
  main.gd                 bootstrap, environment, rules, signals
  core/                   input map + rebinding, settings, accounts, loadout, progression, platform (phones)
  characters/             soldier rig (procedural animation), player, AI enemies, infected, creatures
  weapons/                weapon data, procedural gun and knife models, hitscan + melee
  world/                  forest and town maps, terrain, nature, destructibles, time of day
  modes/                  campaign, zombie wave director
  net/                    multiplayer sync, join codes, open-room service client
  skins/                  weapon skins, outfits, stickers, charms, collection
  camera/  fx/  audio/    camera rig, effects + synthesized sounds, adaptive music
  ui/                     HUD, menus, armory, gunsmith, touch controls, kill cam
tests/                    automated tests (run them all with tools/run_tests.py)
  previews/               windowed screenshot / render tools (not run automatically)
  perf/                   benchmarks
tools/                    test runner, community server, asset helpers
docs/screenshots/         development screenshots
```

## Tests
```
python tools/run_tests.py            # every automated test, with a pass/fail summary
python tools/run_tests.py knife      # just the tests whose name contains "knife"
godot --headless --path . -s res://tests/smoke_test.gd    # one test by hand
```
Set the `GODOT` environment variable to the Godot 4.7 executable if `godot` is not on PATH.
Tests save into a separate sandbox (`user://test_sandbox/`), never into real accounts.

## Animation system
`soldier_rig.gd` animates a segmented rig procedurally instead of using AnimationPlayer clips:
- **Locomotion blend space** from local velocity: idle breathing, walk, strafe, backpedal, jog, sprint, crouch walk, turn-in-place shuffle.
- **Independent facing**: legs follow movement and the torso follows the aim, with the twist split between spine and chest.
- **Two-bone IK** for legs (gait cycle foot placement) and arms (hands locked to the weapon grip and handguard).
- **Planted-foot gait**: stance/swing phases with stride sized to ground speed (no foot sliding), heel-off and toe-lift, walk vs run hip bob.
- **Peek**: hips shift, spine/chest roll around the aim axis, head tilt and weapon cant; shots and enemy line-of-sight use the leaned position, clamped against walls.
- **Vault**: side vault with a left-hand plant on the obstacle (IK), tucked legs, rifle swung clear, landing dip and forward lurch.
- **First-person arms**: two-bone IK to the gun's grips, wrist limits, elbows kept out of view, forearm roll led by the hand; per-class weapon weight with spring inertia, breathing and landing.
- Weapon inertia (lags and cants when turning fast), acceleration/stop lean, hip bob and sway, spring recoil, hit-reaction springs, keyframed reload hand paths (mag drop on empty reload, retention on tactical), weapon lower/raise switching, a directional death fall and a dropped physics weapon.

To use mocap/Mixamo characters instead, replace the rig with an imported Skeleton3D + AnimationTree, and keep the same input properties (`move_velocity`, `aim_yaw`, `crouch_target`, `aim_target`, `sprint_target`).

## Responsiveness and performance
High is the default graphics preset; F2 cycles Low / High / Ultra. Ultra retains
screen-space indirect lighting and SDFGI for machines with more GPU headroom.
Mouse look uses unaccumulated, screen-relative input. First-person animation and
camera rendering share the same interpolated body position; ADS removes cosmetic
weapon bob and turning sway while preserving firing recoil.

Rendered checks (run without `--headless`):
```
godot --path . -s res://tests/perf/render_benchmark.gd -- 1
godot --path . --max-fps 144 -s res://tests/aim_stability_test.gd
```
The benchmark samples 360 frames after 120 warmup frames at the fixed title view;
it reports frame time, p95 and draw calls, not a combat FPS guarantee.

First-person impact feedback no longer rotates the eye or offsets the camera
projection; damage remains visible in the HUD and body reactions. Dynamic damage
lens fringing is disabled in first person. Weapon recoil and deliberate peeking
remain active. `tests/camera_motion_test.gd` exercises real player movement through
sprint, moving ADS and walking while injecting repeated impact feedback, and checks
the camera's effective render transform (including projection offsets).

The forest visual polish pass adds drifting cloud banks, anisotropic filtering
for nature materials, corrected terrain/water normal blending, and more readable
weapon metal. Film grain is subtler; disabling lens effects now fully bypasses
the lens pass when no desaturation is needed. Camera behavior is unchanged.

The river uses one continuous curved channel, a shallow recessed terrain bed,
flow-aligned ripple normals, translucent banks and broken shoreline foam.
The bridge crossing remains level. All cabins, the comms bunker, sawmill shed,
watchtower shelters, tent entrances and supply ruin have light fixtures. Interior
lights stay on during daytime; outpost interior lights follow generator power.
`tests/previews/river_lighting_check.gd` checks daytime/nighttime lamps, generator shutdown
and navigation across the river, and captures river/room previews.


## Infected roster and animation polish
- Crawler (from wave 3): low crouched silhouette, ground-reaching hands, smaller
  collider and lower health. Aim down at it before it closes the distance.
- Armored (from wave 5): blue-gray armor with a yellow chest stripe. Frontal torso
  hits deal 40% damage; headshots, legs and attacks from behind bypass the plate.
- Berserker (from wave 6): red uniform and shoulder growths that glow when health
  reaches 50%. Rage increases movement speed by 55% and melee damage by 30%.
  A groan and glowing growths announce rage; host snapshots replicate the state.
The original walker, runner and brute remain. New types replace part of the wave
mix rather than increasing the total enemy count. Wave callouts explain threats.
Zombies now check walls both before beginning melee and when the hit lands.

All procedural character rigs now share the same render interpolation path.
Movement samples are smoothed before acceleration drives torso lean. Animation
integration advances in small steps rather than discarding elapsed time below
30 FPS, keeping reload, switch, vault, attack and death clocks consistent. Air
pose blending uses the same timestep; aligned IK targets have a stable fallback.
First-person camera recoil rules and steady sight alignment remain intact.

Balance posture: all new unlocks, weights, stat multipliers and the 14/s animation
velocity smoothing rate are starting values, not playtest-certified difficulty.
Automated checks cover unlock eligibility, front/back/head damage, rage flags,
crawler collision, wall occlusion and attack timing at 15/30/60/144 FPS. Manual
acceptance: recognize each type before contact, evade a crawler, flank armor and
finish a wounded berserker without an unavoidable hit. If late waves become
unavoidable, reduce special-type weights/rage speed; if a type is irrelevant,
increase its weight before increasing damage. If starts/stops visibly lag the
body, increase the animation smoothing rate; reduce it if torso impulses remain.

Run `godot --headless --path . -s res://tests/zombie_variants_test.gd` for the
new behavior/timing checks. A client snapshot test covers rage state; a real
multi-computer multiplayer session still needs manual playtesting.

## Credits

- Characters: Quaternius — Ultimate Modular Characters / Universal Base Characters (CC0).
- Gunshots: *The Free Firearm Sound Library*, Still North Media (CC0); reload foley: *Gun reload sounds*, Joaken (CC0).
  Both via OpenGameArt; details in `assets/audio/sfx/CREDITS.md`.
- MGP7 SMG, ZC57 pistol, vertical foregrip, M67 grenade, sandbags, fuel barrels, ammo cans, med kits, radios and other props:
  **Alstra Infinite** — PPS Shooter Essentials (alstrainfinite.itch.io/pps-shooter-essentials),
  used under the Alstra Infinite license (alstrainfinite.com/fal).

- **Licence not yet verified** — these came as Sketchfab-style downloads without a licence file. Check each model's
  page and add its author and licence here before a public release (all are kept outside the repository):
  - Guns: low-poly HK33, AUG A1, UAR-10, AS VAL, Gepard SMG, Glock 17 Gen 6, B&T VP9, Marlin 1895, FN P90, FN SCAR-H, L96A1, Mosin-Nagant 91/30, Remington 700,
    AUG A4, CZ Bren 2, HK MP7 A1, Magpul PDR-C, Q Honey Badger, FN SCAR-SC, SIG MCX Spear Assaulter.
  - Attachments: low-poly collimator set (Aimpoint Comp M4, EOTech EXPS3, Holosun 403R, Holosun 510C, Vortex AMG UH-1),
    AN/PEQ-2, muzzle device set, AK hexagon handguard (hex tube and rail), GP-25 launcher and VOG-25 round, SureFire X300U,
    iron sight set (Magpul MBUS 3 used on the PDR-C and MCX), kitbash hex-cut angled foregrip (AFG).
  - Knives: karambit, PS1-style butterfly knife.
  - First-person arms: Low Poly Arm Rig (rigged arms, `assets/thirdparty/fps_arms/`).
  - Vehicles and props: Panzer I Ausf. A, Toyota Corolla E80, Tequila Zombie Café, "Everything Must Go" sign, low-poly UFO scene,
    Neo-Tokyo Arcade cabinet (the Zombie Survival shop).
  - Maps: neighbourhood city modular low-poly (NEIGHBOURHOOD), fps-map (WALLED VILLAGE),
    low-poly FPS TDM game map by **ResoForge** (WAREHOUSE), location underground laboratory (UNDERGROUND LAB),
    WIP City Scene Tokyo (TOKYO).
