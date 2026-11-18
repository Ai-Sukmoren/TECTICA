extends "res://scripts/world/level.gd"
## THE RANGE: the training course (training.gd), one walled lane, 18 x 108 m,
## flat, open sky. South to north (north is -z):
##   z  32       start pad
##   z  24       walk marker, then the sprint lane to z 8
##   z   3       vault wall across the lane (0.9 m)
##   z  -2..-10  crouch / slide stretch
##   z -12       firing line (sandbags, ammo can); targets at 9-21 m;
##               grenade pit (sandbags, a crouched target) on the east side
##   z -41       second vault wall (bullet time), a target beyond it
##   z -52..-70  kill house: three rooms, door in the south wall
## Coordinates: x east, z south.

const Terrain = preload("res://scripts/world/terrain.gd")
const Nature = preload("res://scripts/world/nature.gd")

const HALF_W := 9.0
const SOUTH := 36.0
const NORTH := -72.0
const LOW_WALL_H := 0.9

# interface shared with the other maps (time of day, HUD, AI read these)
var mode := "training"
var night := 0.0
var outpost_powered := true
var lamp_lights: Array = []
var fireflies: Array = []
var interact_points: Dictionary = {}
var pvp_spawns: Array = []

## Course stations read by training.gd.
var walk_marker := Vector3(0, 0, 24)
var sprint_marker := Vector3(0, 0, 8)
var vault_z := 3.0
var past_vault := Vector3(0, 0, -3)
var firing_line := Vector3(0, 0, -12)
## Target spots are placed so every target is in clear view from the firing line;
## targets and hostiles face south, toward the operator coming up the lane.
var near_target := {"pos": Vector3(-4, 0, -20), "yaw": PI}
var far_targets := [{"pos": Vector3(-1, 0, -31), "yaw": PI}, {"pos": Vector3(3, 0, -33), "yaw": PI}]
var grenade_target := {"pos": Vector3(5.2, 0, -23.4), "yaw": PI, "crouch": true}
var bullet_z := -41.0
var bullet_target := {"pos": Vector3(-5, 0, -46), "yaw": PI}   # off to the side, clear of the kill house door
var house_door := Vector3(0, 0, -50)
var house_hostiles := [
	{"pos": Vector3(-5, 0, -58), "yaw": PI, "patrol": [Vector3(-5, 0, -58), Vector3(-6, 0, -55)]},
	{"pos": Vector3(5.5, 0, -61), "yaw": PI, "patrol": []},
	{"pos": Vector3(-1, 0, -67), "yaw": PI, "patrol": [Vector3(-1, 0, -67), Vector3(4, 0, -68)]},
]


func build() -> void:
	seed(7070)
	Terrain.clear()
	Water.clear()
	Nature.fade_materials = []
	_mat_wall = M.concrete("wall", Color(0.4, 0.41, 0.43), 0.4)
	_mat_wall_trim = M.solid(Color(0.2, 0.21, 0.23), 0.8)
	_mat_crate = M.wood("crate", Color(0.46, 0.4, 0.28))
	_mat_crate_frame = M.wood("crate_frame", Color(0.34, 0.29, 0.2))
	_mat_sandbag = M.fabric("sandbag", Color(0.52, 0.47, 0.36), 4.0)
	_mat_concrete = M.concrete("barrier", Color(0.58, 0.57, 0.54), 0.6)
	_mat_metal = M.painted_metal("metal_grey", Color(0.3, 0.32, 0.33))
	FX.ground_surface = "stone"
	player_spawn = Vector3(0, 0, 32)
	player_yaw = 0.0
	zombie_spawns = []

	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	add_child(nav_region)

	_build_floors()
	_build_walls()
	_build_lane()
	_build_range()
	_build_house()
	_bake_navigation()


func _build_floors() -> void:
	var length := SOUTH - NORTH
	var cz := (SOUTH + NORTH) * 0.5
	var floor_body := _body(Vector3(0, 0, cz))
	_box_shape(floor_body, Vector3(HALF_W * 2.0 + 4.0, 1, length + 4.0), Vector3(0, -0.5, 0))
	_mesh(floor_body, ML.plane(Vector2(HALF_W * 2.0 + 4.0, length + 4.0)),
			M.floor_grid("floor_range", Color(0.15, 0.165, 0.18), Color(0.24, 0.26, 0.29), 0.25), Vector3.ZERO)
	var paint := M.solid(Color(0.8, 0.66, 0.16), 0.7)
	# lane edges, the start pad and the firing line
	for x in [-HALF_W + 1.0, HALF_W - 1.0]:
		_floor_patch(Vector3(x, 0.006, (SOUTH - 4.0 + firing_line.z) * 0.5), Vector2(0.12, SOUTH - 4.0 - firing_line.z), paint)
	_floor_patch(Vector3(0, 0.007, player_spawn.z), Vector2(3.0, 3.0), M.floor_grid("pad", Color(0.2, 0.24, 0.26), Color(0.45, 0.52, 0.55), 0.5))
	_floor_patch(Vector3(0, 0.008, firing_line.z + 0.7), Vector2(HALF_W * 2.0 - 1.0, 0.15), paint)
	_floor_patch(Vector3(0, 0.008, house_door.z + 0.6), Vector2(3.4, 0.9), M.hazard_stripes())


func _build_walls() -> void:
	_wall_x(SOUTH, -HALF_W - 0.2, HALF_W + 0.2)
	_wall_x(NORTH, -HALF_W - 0.2, HALF_W + 0.2)
	_wall_z(-HALF_W, NORTH, SOUTH)
	_wall_z(HALF_W, NORTH, SOUTH)


## A full-width low wall: the only way on is over it.
func _low_wall(z: float) -> void:
	var b := solid_box(Vector3(0, 0, z), Vector3(HALF_W * 2.0, LOW_WALL_H, 0.5), _mat_concrete)
	_mesh(b, ML.box(Vector3(HALF_W * 2.0, 0.08, 0.3)), M.hazard_stripes(), Vector3(0, LOW_WALL_H + 0.04, 0))


func _build_lane() -> void:
	_low_wall(vault_z)
	# set dressing along the walls, out of the running line
	crate(Vector3(-7.4, 0, 28.5), Vector3(1.2, 1.0, 1.2), 0.2)
	crate_stack(Vector3(7.3, 0, 18.0), -0.1)
	barrel(Vector3(-7.6, 0, 12.5), Color(0.25, 0.3, 0.42))
	barrel(Vector3(-7.7, 0, 11.7), Color(0.25, 0.3, 0.42))
	crate(Vector3(7.4, 0, -6.0), Vector3(1.0, 0.8, 1.0), -0.3)


func _build_range() -> void:
	# firing line: low sandbags with a gap in the middle, resupply behind it
	sandbags(Vector3(-5.2, 0, firing_line.z - 0.9), 5.0, 0.0, 2)
	sandbags(Vector3(5.2, 0, firing_line.z - 0.9), 5.0, 0.0, 2)
	ammo_crates.append(firing_line + Vector3(-2.2, 0, 1.6))
	# a backstop behind each target (bullets stop, the targets read against it)
	for t in [near_target] + far_targets:
		var p: Vector3 = t.pos
		var plate := solid_box(p + Vector3(0, 0, -1.6), Vector3(2.2, 2.2, 0.3), _mat_metal)
		_mesh(plate, ML.box(Vector3(2.0, 0.06, 0.32)), M.hazard_stripes(), Vector3(0, 2.23, 0))
	# grenade pit: a sandbag wall with a crouched target behind it
	var gp: Vector3 = grenade_target.pos
	sandbags(gp + Vector3(0, 0, 1.2), 3.2, 0.0, 4)
	sandbags(gp + Vector3(-1.8, 0, 0.0), 1.8, PI * 0.5, 4)
	# the second low wall, with a target beyond it for bullet time
	_low_wall(bullet_z)
	var bp: Vector3 = bullet_target.pos
	solid_box(bp + Vector3(0, 0, -1.6), Vector3(2.2, 2.2, 0.3), _mat_metal)


func _build_house() -> void:
	var z0 := house_door.z - 2.0   # south wall of the house
	_wall_x(z0, -HALF_W, HALF_W, [[-1.3, 1.3]])
	# rooms: west, east and a back room across the north end
	_wall_z(-1.5, z0 - 11.0, z0, [[z0 - 6.5, z0 - 4.5]])
	_wall_x(z0 - 11.0, -HALF_W, HALF_W, [[-5.5, -3.5], [3.0, 5.0]])
	crate(Vector3(-4.0, 0, z0 - 3.5), Vector3(1.2, 1.0, 1.2), 0.2)
	crate(Vector3(4.5, 0, z0 - 7.0), Vector3(2.0, 1.0, 1.2), 0.0)
	sandbags(Vector3(1.8, 0, z0 - 14.0), 2.6, 0.0, 3)
	crate(Vector3(-6.5, 0, z0 - 16.5), Vector3(1.2, 1.1, 1.4), -0.2)
	barrel(Vector3(7.5, 0, z0 - 18.0), Color(0.6, 0.2, 0.15))
	ammo_crates.append(house_door + Vector3(3.0, 0, 3.0))
