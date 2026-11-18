# CH1 — TIMBERLINE: "The Beginning"

**Logline:** At 08:00 a lone operator, KILO-1, is flown into Pinewood Valley to take back a logging
camp the militia seized four hours earlier, and is left on the pad to do it quietly.
**Story facts used:** camp taken at 04:00, 08:00 start (`campaign.gd chapter_info`); intel download
and river-crossing exfil (`campaign.gd setup`); solo start on the south pad (`forest_level.gd
_define_mode`); OVERWATCH radio (the chapter's opening radio call).
**Length:** 46 s · **Hour:** 08:00 (held) · **Ends at:** `player_spawn`, `player_yaw`

## Beats
1. Establish the valley at dawn, mist in the trees — 2. Threat: the occupied camp through a long
lens — 3. Arrival: RAVEN-6 skims the treetops — 4. Character: KILO-1 in the door, checking his
rifle — 5. Stakes: alone, the helo leaves for the river — 6. Hand-over into the gameplay camera.

## Shot list
| # | Time | Len | Framing / lens | Move | Subject / focus | Sound | Line |
|---|------|-----|----------------|------|-----------------|-------|------|
| 1 | 0.0 | 8.5 | extreme wide aerial, fov 52->47 | slow push and drop over the treeline | camp (smoke) | wind, dawn birds; caption PINEWOOD VALLEY / LOGGING CAMP · 0800 | — |
| 2 | 8.5 | 5.0 | long lens from the treeline, fov 26->24 | creeping push, handheld 0.5 | camp centre, DOF | radio squelch | OVERWATCH: militia took the camp at 04:00 |
| 3 | 13.5 | 6.5 | tracking alongside, fov 50->44 | track, closing in | helicopter | rotor rises | OVERWATCH: pull everything off their system |
| 4 | 20.0 | 5.8 | low from the grass, fov 46 | slight drift, handheld | helicopter flares and lands, DOF | rotor, downdraft wind | — |
| 5 | 25.8 | 7.2 | medium close, fov 36->33 | slow push | KILO-1 crouched in the door, rifle check, DOF | rotor idle | RAVEN-6: I'll be at the river crossing · KILO-1: keep the rotors warm |
| 6 | 33.0 | 7.0 | over the shoulder, fov 48 | slight push | helicopter lifting away (focus), KILO-1 soft | rotor fading, birds return | OVERWATCH: camp's north, make it quiet |
| 7 | 40.0 | 6.0 | glide | crane into the gameplay camera | — | letterbox and grade ease out | — |

## Hand-over
`game_view` at 40.0 places KILO-1 on `player_spawn` (he has walked there on camera) and readies the
gameplay camera; shot 7 interpolates to its live pose. Skip: fades out, KILO-1 placed on the spawn.
The chapter's own opening (gunfire from the camp, `campaign.gd _opening`) follows on deploy.
