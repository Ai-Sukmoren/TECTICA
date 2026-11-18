extends RefCounted
## The campaign's two story cutscenes, staged on Pinewood Valley's real
## landmarks (forest_level.gd) and the established story (campaign.gd):
##
##   CH1 TIMBERLINE  08:00  militia took the logging camp at 04:00. The operator
##       (KILO-1) is flown in alone to the south landing pad by RAVEN-6, who will
##       wait at the river crossing (the chapter's exfil). OVERWATCH wants
##       everything on the militia's system (the intel download).
##   CH2 NIGHTFALL  20:36  twelve hours later, at the river crossing. The camp still
##       burns. The drive from the camp points to the radio outpost relaying the
##       enemy's orders; the helo can't come in while its tower stands. Cut the
##       power, drop the tower, meet the helo at the north LZ.
##
## Each definition is data for cutscene_director.gd (see its header). Storyboards
## and shot lists: docs/cutscenes/. Built per level so every position sits on the
## real ground.

static func build(chapter: String, main) -> Dictionary:
	if chapter == "ch2":
		return _ch2(main)
	if chapter == "ch1":
		return _ch1(main)
	return {}


static func has_cutscene(chapter: String) -> bool:
	return chapter in ["ch1", "ch2"]


## A point `h` metres above the ground at (x, z).
static func _g(lvl, p: Vector3, h: float = -1.0) -> Vector3:
	var y: float = lvl.ground_y(p.x, p.z) if lvl.has_method("ground_y") else 0.0
	return Vector3(p.x, y + (p.y if h < 0.0 else h), p.z)


static func _yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))


static func _actor(n: String, off: Vector3 = Vector3.ZERO, local: bool = false) -> Dictionary:
	return {"actor": n, "offset": off, "local": local}


# ======================================================================= CH1

static func _ch1(main) -> Dictionary:
	var lvl = main.level
	var pad: Vector3 = lvl.lz_south
	var camp: Vector3 = lvl.camp
	var spawn: Vector3 = _g(lvl, lvl.player_spawn, 0.0)
	# the helo sets down on the pad's far side: the operator walks clear of it to his start spot
	var land := _g(lvl, pad + Vector3(-1.0, 0, -6.0), 0.0)
	var door := _g(lvl, land + Vector3(1.4, 0, 0.6), 0.0)   # the right-hand cabin door
	var to_bridge := Vector3(lvl.bridge.x - land.x, 0, lvl.bridge.z - land.z).normalized()
	var away := _yaw_to(Vector3.ZERO, to_bridge)
	var shots := [
		# 1. establishing: high over the treeline, drifting toward the camp's smoke
		{"t": 0.0, "dur": 8.5, "type": "move", "from": _g(lvl, pad + Vector3(14, 0, 40), 34.0), "to": _g(lvl, pad + Vector3(18, 0, 12), 25.0),
				"look_from": _g(lvl, camp, 3.0), "look_to": _g(lvl, camp, 1.0), "fov": [52.0, 47.0], "hand": 0.12},
		# 2. the threat: long lens on the occupied camp from the treeline
		{"t": 8.5, "dur": 5.0, "type": "move", "from": _g(lvl, camp + Vector3(-30, 0, 26), 3.4), "to": _g(lvl, camp + Vector3(-28, 0, 24), 3.3),
				"look_from": _g(lvl, camp, 1.6), "fov": [26.0, 24.0], "focus": _g(lvl, camp, 1.5), "dof": 0.08, "hand": 0.5},
		# 3. RAVEN-6 skims the treetops: a tracking shot alongside
		{"t": 13.5, "dur": 6.5, "type": "track", "subject": _actor("heli"), "off_from": Vector3(-16, 2.0, 14), "off_to": Vector3(-10, 0.0, 8),
				"look_off": Vector3(0, 1.6, 0), "fov": [50.0, 44.0], "hand": 0.25},
		# 4. from the grass at the pad's edge, the helo flares and settles
		{"t": 20.0, "dur": 5.8, "type": "move", "from": _g(lvl, land + Vector3(8, 0, 9), 1.1), "to": _g(lvl, land + Vector3(7.4, 0, 8.2), 1.0),
				"look_from": _actor("heli", Vector3(0, 2.0, 0)), "fov": [46.0, 44.0], "focus": _actor("heli"), "dof": 0.05, "hand": 0.35},
		# 5. KILO-1 in the door: a close shot while he checks his rifle
		{"t": 25.8, "dur": 7.2, "type": "move", "from": door + Vector3(2.3, 1.25, -1.5), "to": door + Vector3(1.9, 1.2, -1.2),
				"look_from": _actor("player", Vector3(0, 1.2, 0)), "fov": [36.0, 33.0], "focus": _actor("player"), "dof": 0.13, "hand": 0.35},
		# 6. over his shoulder as RAVEN-6 lifts away toward the river
		{"t": 33.0, "dur": 7.0, "type": "move", "from": spawn + Vector3(0.75, 1.72, 1.7), "to": spawn + Vector3(0.6, 1.66, 1.45),
				"look_from": _actor("heli", Vector3(0, 1.5, 0)), "fov": [48.0, 46.0], "focus": _actor("heli"), "dof": 0.06, "hand": 0.3},
		# 7. the camera glides into the gameplay view
		{"t": 40.0, "dur": 5.4, "type": "to_game"},   # settles 0.6 s before the end
	]
	var arrive := [
		[0.0, _g(lvl, pad + Vector3(70, 0, 85), 30.0), 0.72, -0.18],
		[5.0, _g(lvl, pad + Vector3(32, 0, 40), 16.0), 0.62, -0.2],
		[9.0, _g(lvl, land + Vector3(7, 0, 9), 7.0), 0.2, 0.08],
		[11.5, land + Vector3(0, 1.6, 0), 0.0, 0.06],
		[13.0, land, 0.0, 0.0],
	]
	var leave := [
		[0.0, land, 0.0, 0.0],
		[2.5, land + Vector3(0, 4.0, 0), away * 0.3, -0.04],
		[6.0, land + to_bridge * 22.0 + Vector3(0, 14, 0), away, -0.2],
		[11.0, land + to_bridge * 80.0 + Vector3(0, 26, 0), away, -0.2],
	]
	var events := [
		[0.0, "fade", {"to": 0.0, "dur": 2.5}],
		[0.0, "letterbox", {"to": 1.0, "dur": 0.0}],
		[0.0, "grade", {"contrast": 1.12, "saturation": 0.8, "brightness": 0.97, "dur": 0.0}],
		[0.0, "fog", {"to": 0.012, "dur": 0.0}],
		[0.0, "music", {"master": 0.15}],
		[0.0, "loop", {"name": "wind", "vol": -16.0, "fade": 3.0}],
		[0.0, "loop", {"name": "birds", "vol": -17.0, "fade": 4.0}],
		[0.0, "place", {"actor": "player", "pos": door, "yaw": -PI * 0.5, "visible": false}],
		[1.2, "caption", {"lines": ["PINEWOOD VALLEY", "LOGGING CAMP  ·  0800 HRS"], "dur": 6.0}],
		[9.0, "line", {"who": "OVERWATCH", "text": "Kilo-One, Overwatch. Militia took the logging camp at zero-four-hundred.", "dur": 4.2, "radio": true}],
		[11.5, "heli", {"pos": arrive[0][1], "yaw": 0.72, "rotor": 1.0}],
		[11.5, "path", {"actor": "heli", "keys": arrive}],
		[11.5, "loop", {"name": "rotor", "vol": -2.0, "fade": 3.0, "at": _actor("heli", Vector3(0, 2, 0))}],
		[14.2, "line", {"who": "OVERWATCH", "text": "Whatever they're running through that camp, we want it. Pull everything off their system.", "dur": 5.0, "radio": true}],
		[19.5, "loop", {"name": "wind", "vol": -9.0, "fade": 2.0}],
		[24.3, "rotor", {"to": 0.72, "dur": 1.5}],
		[25.6, "place", {"actor": "player", "pos": door, "yaw": -PI * 0.5, "visible": true}],
		[25.6, "crouch", {"actor": "player", "on": true}],
		[26.4, "anim", {"actor": "player", "name": "inspect"}],
		[27.0, "line", {"who": "RAVEN-6", "text": "You're on the ground, Kilo-One. I'll be at the river crossing when you're done.", "dur": 4.0, "radio": true}],
		[30.0, "crouch", {"actor": "player", "on": false}],
		[30.3, "walk", {"actor": "player", "to": spawn, "speed": 1.9}],
		[31.4, "line", {"who": "KILO-1", "text": "Copy. Keep the rotors warm.", "dur": 2.2}],
		[33.2, "rotor", {"to": 1.0, "dur": 1.0}],
		[33.5, "path", {"actor": "heli", "keys": leave}],
		[33.6, "look", {"actor": "player", "at": _actor("heli"), "rate": 2.0}],
		[35.5, "loop", {"name": "wind", "vol": -16.0, "fade": 4.0}],
		[36.3, "line", {"who": "OVERWATCH", "text": "Camp's north of you, through the trees. Make it quiet.", "dur": 3.6, "radio": true}],
		[38.5, "loop", {"name": "rotor", "vol": -70.0, "fade": 5.0}],
		[40.0, "game_view", {}],
		[41.0, "letterbox", {"to": 0.0, "dur": 3.0}],
		[41.0, "grade_restore", {"dur": 4.0}],
		[41.0, "fog", {"to": 0.0, "dur": 4.0}],
		[41.0, "music", {"master": 1.0}],
		[43.5, "loop", {"name": "birds", "vol": -22.0, "fade": 2.0}],
	]
	return {"id": "ch1", "length": 46.0, "hour": 8.0, "shots": shots, "events": events,
			"player_end": {"pos": spawn, "yaw": float(lvl.player_yaw)}}


# ======================================================================= CH2

static func _ch2(main) -> Dictionary:
	var lvl = main.level
	var camp: Vector3 = lvl.camp
	var outpost: Vector3 = lvl.outpost
	var spawn: Vector3 = _g(lvl, lvl.player_spawn, 0.0)
	var tower: Vector3 = lvl.radio_tower.global_position if lvl.radio_tower else outpost + Vector3(-9, 0, -8)
	var gen: Vector3 = lvl.generator.global_position if lvl.generator else outpost
	var lamp_tower := _g(lvl, outpost + Vector3(15, 0, 13), 0.0)   # the searchlight tower
	var face_outpost := _yaw_to(spawn, outpost)
	var shots := [
		# 1. twelve hours later: the camp still burns under the moon
		{"t": 0.0, "dur": 8.0, "type": "move", "from": _g(lvl, camp + Vector3(-34, 0, 42), 20.0), "to": _g(lvl, camp + Vector3(-22, 0, 30), 14.0),
				"look_from": _g(lvl, camp + Vector3(-4, 0, -4), 2.0), "look_to": _g(lvl, camp + Vector3(-6, 0, -6), 1.0), "fov": [50.0, 46.0], "hand": 0.15},
		# 2. the river crossing: KILO-1 waiting low by the water
		{"t": 8.0, "dur": 7.5, "type": "move", "from": spawn + Vector3(-2.4, 0.55, 1.6), "to": spawn + Vector3(-2.0, 0.6, 1.1),
				"look_from": _actor("player", Vector3(0, 1.0, 0)), "fov": [38.0, 36.0], "focus": _actor("player"), "dof": 0.12, "hand": 0.35},
		# 3. the reveal: the outpost on the ridge, tilting up its radio tower to the beacon
		# (above the treeline: from the ground the forest hides it)
		{"t": 15.5, "dur": 7.5, "type": "move", "from": _g(lvl, outpost + Vector3(34, 0, 40), 24.0), "to": _g(lvl, outpost + Vector3(24, 0, 28), 20.0),
				"look_from": tower + Vector3(0, 4, 0), "look_to": tower + Vector3(0, 18, 0), "fov": [40.0, 34.0], "hand": 0.15},
		# 4. a sentry on his rounds by the generator
		{"t": 23.0, "dur": 6.0, "type": "track", "subject": _actor("guard"), "off_from": Vector3(3.5, 1.7, 3.0), "off_to": Vector3(2.8, 1.6, 2.4),
				"look_off": Vector3(0, 1.4, 0), "fov": [40.0, 38.0], "focus": _actor("guard"), "dof": 0.1, "hand": 0.35},
		# 5. the searchlight tower he has to get past, its beam sweeping the ground
		{"t": 29.0, "dur": 6.0, "type": "move", "from": _g(lvl, lamp_tower + Vector3(7.5, 0, 9.5), 2.3), "to": _g(lvl, lamp_tower + Vector3(6.4, 0, 8.3), 2.5),
				"look_from": lamp_tower + Vector3(0, 3.5, 0), "look_to": lamp_tower + Vector3(0, 4.5, 0), "fov": [42.0, 38.0], "focus": lamp_tower, "dof": 0.05, "hand": 0.3},
		# 6. close: he checks his magazine and switches his light on
		{"t": 35.0, "dur": 6.5, "type": "move", "from": spawn + Vector3(1.6, 1.05, -1.6), "to": spawn + Vector3(1.3, 1.0, -1.3),
				"look_from": _actor("player", Vector3(0, 1.0, 0)), "fov": [34.0, 32.0], "focus": _actor("player"), "dof": 0.14, "hand": 0.3},
		# 7. into the gameplay view
		{"t": 41.5, "dur": 5.9, "type": "to_game"},
	]
	var burned := _g(lvl, camp + Vector3(-9, 0, -8), 0.0)      # the cabin the intel came out of
	var events := [
		[0.0, "fade", {"to": 0.0, "dur": 3.0}],
		[0.0, "letterbox", {"to": 1.0, "dur": 0.0}],
		# a filmic "night": lifted so faces and shapes read, cool and desaturated
		[0.0, "grade", {"contrast": 1.12, "saturation": 0.75, "brightness": 1.35, "dur": 0.0}],
		[0.0, "fog", {"to": 0.006, "dur": 0.0}],
		[0.0, "music", {"master": 0.1}],
		[0.0, "fire", {"pos": burned + Vector3(0, 0.5, 0), "persist": true}],
		[0.0, "fire", {"pos": _g(lvl, camp + Vector3(10, 0, -7), 0.5), "persist": true}],
		[0.0, "loop", {"name": "insects", "vol": -14.0, "fade": 3.0}],
		[0.0, "loop", {"name": "wind", "vol": -22.0, "fade": 3.0}],
		[0.0, "loop", {"name": "fire", "vol": -4.0, "fade": 2.0, "at": burned + Vector3(0, 1, 0)}],
		[0.0, "place", {"actor": "player", "pos": spawn, "yaw": face_outpost, "visible": true}],
		[0.0, "crouch", {"actor": "player", "on": true}],
		[1.2, "caption", {"lines": ["PINEWOOD VALLEY", "THE LOGGING CAMP  ·  TWELVE HOURS LATER"], "dur": 6.2}],
		[7.5, "loop", {"name": "fire", "vol": -60.0, "fade": 2.0}],
		[9.0, "line", {"who": "OVERWATCH", "text": "Kilo-One, Overwatch. We cracked the drive you pulled from the camp.", "dur": 4.0, "radio": true}],
		[13.4, "line", {"who": "KILO-1", "text": "Go ahead.", "dur": 1.4}],
		[15.0, "loop", {"name": "generator", "vol": -2.0, "fade": 3.0, "at": gen + Vector3(0, 1, 0)}],
		[15.8, "line", {"who": "OVERWATCH", "text": "Radio logs. Every unit in this valley takes its orders through that outpost on the ridge.", "dur": 5.4, "radio": true}],
		[22.9, "bind_enemy", {"near": gen, "as": "guard"}],
		[23.6, "line", {"who": "OVERWATCH", "text": "And after this morning, they're listening for us. The helo can't come in while that tower stands.", "dur": 5.4, "radio": true}],
		[28.5, "loop", {"name": "drone", "vol": -12.0, "fade": 3.0}],
		[28.5, "loop", {"name": "generator", "vol": -60.0, "fade": 2.0}],
		[29.5, "look", {"actor": "player", "at": lamp_tower, "rate": 1.5}],
		[32.2, "line", {"who": "KILO-1", "text": "Then I take it down.", "dur": 2.2}],
		[35.6, "anim", {"actor": "player", "name": "reload"}],
		[36.2, "line", {"who": "OVERWATCH", "text": "Cut the power first. The floodlights die with it. Then the tower. The helo meets you at the north LZ.", "dur": 5.0, "radio": true}],
		[40.3, "flashlight", {"on": true}],
		[41.2, "crouch", {"actor": "player", "on": false}],
		[41.5, "game_view", {}],
		[42.0, "letterbox", {"to": 0.0, "dur": 3.0}],
		[42.0, "grade_restore", {"dur": 4.0}],
		[42.0, "fog", {"to": 0.0, "dur": 4.0}],
		[42.0, "music", {"master": 1.0}],
		[44.0, "loop", {"name": "drone", "vol": -70.0, "fade": 3.0}],
		[45.0, "loop", {"name": "insects", "vol": -22.0, "fade": 2.0}],
	]
	return {"id": "ch2", "length": 48.0, "hour": 20.6, "shots": shots, "events": events,
			"player_end": {"pos": spawn, "yaw": float(lvl.player_yaw)}}
