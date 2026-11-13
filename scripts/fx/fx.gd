extends RefCounted
## Combat visual effects: muzzle flash, tracers, impacts, blood, casings, decals.

const M = preload("res://scripts/core/materials.gd")
const ML = preload("res://scripts/core/mesh_lib.gd")
const Debris = preload("res://scripts/fx/debris.gd")
const Terrain = preload("res://scripts/world/terrain.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")

const MAX_DECALS := 120

static var _decals: Array = []
static var _mats: Dictionary = {}
static var _fade_curve: Curve


static func _root(ctx: Node) -> Node:
	if ctx == null or not ctx.is_inside_tree():
		return null
	var s := ctx.get_tree().current_scene
	return s if s != null else ctx.get_tree().root


static func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"tracer":
			m = M.glow(Color(1.0, 0.82, 0.5, 0.95))
		"tracer_dim":
			m = M.glow(Color(1.0, 0.85, 0.6, 0.35))
		"flash":
			m = M.glow(Color(1.0, 0.72, 0.32, 1.0))
		"spark":
			m = M.glow(Color(1.0, 0.75, 0.35, 1.0))
		"dust":
			var d := StandardMaterial3D.new()
			d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			d.vertex_color_use_as_albedo = true
			d.albedo_color = Color(0.55, 0.53, 0.5, 0.55)
			d.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m = d
		"blood":
			var b := StandardMaterial3D.new()
			b.albedo_color = Color(0.35, 0.02, 0.02)
			b.roughness = 0.3
			m = b
		"brass":
			m = M.solid(Color(0.78, 0.6, 0.25), 0.3, 0.9)
	_mats[key] = m
	return m


static func _curve() -> Curve:
	if _fade_curve == null:
		_fade_curve = Curve.new()
		_fade_curve.add_point(Vector2(0.0, 1.0))
		_fade_curve.add_point(Vector2(1.0, 0.0))
	return _fade_curve


static func muzzle_flash(muzzle: Node3D, strength: float) -> void:
	if muzzle == null or not muzzle.is_inside_tree():
		return
	var s := clampf(strength, 0.15, 1.5)
	var flash := Node3D.new()
	flash.rotation.z = randf() * TAU
	flash.scale = Vector3.ONE * s * randf_range(0.8, 1.2)
	muzzle.add_child(flash)
	# hot core plus three crossed petals: a star-shaped bloom instead of a blob
	var core := MeshInstance3D.new()
	core.mesh = ML.sphere(0.045, false, 8)
	core.material_override = _mat("flash")
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.scale = Vector3(1.0, 1.0, 2.2)
	core.position = Vector3(0, 0, -0.06)
	flash.add_child(core)
	for i in 3:
		var petal := MeshInstance3D.new()
		petal.mesh = ML.quad(Vector2(0.11, 0.4))
		petal.material_override = _mat("flash")
		petal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		petal.basis = Basis(Vector3.BACK, i * PI / 3.0) * Basis(Vector3.RIGHT, PI * 0.5)
		petal.position = Vector3(0, 0, -0.22)
		flash.add_child(petal)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 3.5 * s
	light.omni_range = 2.0 + 3.0 * s
	light.shadow_enabled = false
	muzzle.add_child(light)
	var tree := muzzle.get_tree()
	tree.create_timer(0.04).timeout.connect(flash.queue_free)
	tree.create_timer(0.05).timeout.connect(light.queue_free)
	# a wisp of propellant smoke drifting off the muzzle
	var root := _root(muzzle)
	if root != null and s > 0.3:
		var dir := -muzzle.global_transform.basis.z
		_particles(root, muzzle.global_position + dir * 0.15, dir, 3, 0.55, 0.5, 1.3, 20.0,
				ML.sphere(0.05, false, 6), _mat("dust"), Vector3(0, 0.5, 0), 0.7, 1.8)


static func tracer(ctx: Node, from: Vector3, to: Vector3, dim: bool) -> void:
	var root := _root(ctx)
	if root == null:
		return
	var length := from.distance_to(to)
	if length < 0.4:
		return
	var dir := (to - from) / length
	var seg := minf(2.6, length)
	var mi := MeshInstance3D.new()
	mi.mesh = ML.box(Vector3(0.022, 0.022, 1.0))
	mi.material_override = _mat("tracer_dim" if dim else "tracer")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(dir, up), from + dir * seg * 0.5)
	mi.scale = Vector3(1, 1, seg)
	var travel := maxf(length / 320.0, 0.03)
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", to - dir * seg * 0.5, travel)
	tw.tween_callback(mi.queue_free)


static func _particles(root: Node, pos: Vector3, normal: Vector3, amount: int, lifetime: float,
		vmin: float, vmax: float, spread: float, mesh: Mesh, mat: Material, gravity: Vector3,
		scale_min: float = 1.0, scale_max: float = 1.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.95
	p.mesh = mesh
	p.material_override = mat
	p.direction = normal
	p.spread = spread
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = gravity
	p.scale_amount_min = scale_min
	p.scale_amount_max = scale_max
	p.scale_amount_curve = _curve()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(lifetime + 0.4).timeout.connect(p.queue_free)
	return p


static func impact(ctx: Node, pos: Vector3, normal: Vector3) -> void:
	var root := _root(ctx)
	if root == null:
		return
	_particles(root, pos + normal * 0.02, normal, 9, 0.3, 2.5, 7.0, 40.0,
			ML.box(Vector3(0.012, 0.012, 0.05)), _mat("spark"), Vector3(0, -12, 0))
	_particles(root, pos + normal * 0.05, normal, 6, 0.7, 0.4, 1.6, 30.0,
			ML.sphere(0.07, false, 6), _mat("dust"), Vector3(0, 0.3, 0), 0.6, 1.6)
	_decal(root, pos, normal, 0.07, "hole", M.blot("hole", Color(0.03, 0.03, 0.03, 0.9)))


static func blood(ctx: Node, pos: Vector3, dir: Vector3) -> void:
	var root := _root(ctx)
	if root == null:
		return
	_particles(root, pos, (dir + Vector3.UP * 0.3).normalized(), 14, 0.5, 1.5, 4.5, 30.0,
			ML.sphere(0.018, false, 6), _mat("blood"), Vector3(0, -9.8, 0), 0.6, 1.4)
	var splat := Vector3(pos.x, 0.0, pos.z) + Vector3(dir.x, 0, dir.z).normalized() * randf_range(0.4, 1.2)
	splat = Terrain.snap(splat)
	_decal(root, splat, Terrain.normal(splat.x, splat.z), randf_range(0.25, 0.45), "blood",
			M.blot("blood_splat", Color(0.3, 0.01, 0.01, 0.85)))


static func blood_pool(ctx: Node, pos: Vector3) -> void:
	var root := _root(ctx)
	if root == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = ML.quad(Vector2.ONE)
	mi.material_override = M.blot("blood_pool", Color(0.24, 0.01, 0.01, 0.92))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var gn := Terrain.normal(pos.x, pos.z)
	mi.global_transform = Transform3D(Basis.looking_at(-gn, Vector3.FORWARD), Terrain.snap(pos) + gn * 0.012)
	mi.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	mi.scale = Vector3.ONE * 0.1
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * randf_range(1.3, 1.8), 6.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_track(mi)   # pools used to pile up forever (one per kill) and slowed long zombie runs


static func _decal(root: Node, pos: Vector3, normal: Vector3, size: float, _kind: String, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = ML.quad(Vector2.ONE)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.FORWARD
	var p := pos + normal * 0.012
	if normal.y > 0.8:
		p.y = maxf(p.y, Terrain.height(p.x, p.z) + 0.008 + randf() * 0.004)
	mi.global_transform = Transform3D(Basis.looking_at(-normal, up), p)
	mi.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	mi.scale = Vector3.ONE * size
	_track(mi)


## Keeps the total of ground marks (decals + blood pools) under MAX_DECALS.
static func _track(mi: Node) -> void:
	_decals.append(mi)
	while _decals.size() > MAX_DECALS:
		var old = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()


static func casing(ctx: Node, pos: Vector3, right: Vector3, pistol: bool) -> void:
	var root := _root(ctx)
	if root == null:
		return
	var d := Debris.new()
	var mi := MeshInstance3D.new()
	mi.mesh = ML.cylinder(0.0055, 0.0055, 0.022 if pistol else 0.035, 6)
	mi.material_override = _mat("brass")
	mi.rotation.x = PI * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	d.add_child(mi)
	d.velocity = right * randf_range(1.8, 3.0) + Vector3.UP * randf_range(1.5, 2.6)
	d.spin = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	d.life = 3.5
	d.radius = 0.006
	d.bounce_sound = "casing" if randf() < 0.35 else ""
	root.add_child(d)
	d.global_position = pos


static func dropped_mag(ctx: Node, mag: Node3D, xf: Transform3D) -> void:
	var root := _root(ctx)
	if root == null or mag == null:
		return
	var d := Debris.new()
	var copy := mag.duplicate() as Node3D
	copy.transform = Transform3D.IDENTITY
	copy.visible = true
	d.add_child(copy)
	d.velocity = Vector3(randf_range(-0.4, 0.4), -0.5, randf_range(-0.4, 0.4))
	d.spin = Vector3(randf_range(-4, 4), randf_range(-3, 3), randf_range(-4, 4))
	d.life = 12.0
	d.radius = 0.03
	d.bounce_sound = "casing"
	root.add_child(d)
	d.global_transform = xf


static func explosion(ctx: Node, pos: Vector3) -> void:
	var root := _root(ctx)
	if root == null:
		return
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.3)
	light.light_energy = 14.0
	light.omni_range = 14.0
	# a shadowed omni light renders the scene 6 more times: ULTRA shadows only
	light.shadow_enabled = int(preload("res://scripts/core/settings.gd").v.shadows) >= 3
	root.add_child(light)
	light.global_position = pos + Vector3.UP * 0.8
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.55).set_ease(Tween.EASE_OUT)
	lt.tween_callback(light.queue_free)
	var ball := MeshInstance3D.new()
	ball.mesh = ML.sphere(1.0, false, 16)
	var bm := M.glow(Color(1.0, 0.55, 0.2, 0.95))
	ball.material_override = bm
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ball)
	ball.global_position = pos + Vector3.UP * 0.5
	ball.scale = Vector3.ONE * 0.3
	var bt := ball.create_tween().set_parallel(true)
	bt.tween_property(ball, "scale", Vector3.ONE * 2.4, 0.22).set_ease(Tween.EASE_OUT)
	bt.tween_property(bm, "albedo_color:a", 0.0, 0.3)
	bt.chain().tween_callback(ball.queue_free)
	_particles(root, pos + Vector3.UP * 0.2, Vector3.UP, 46, 0.9, 6.0, 15.0, 80.0,
			ML.box(Vector3(0.02, 0.02, 0.09)), _mat("spark"), Vector3(0, -9.8, 0))
	var smoke := _particles(root, pos + Vector3.UP * 0.5, Vector3.UP, 26, 3.2, 1.0, 3.5, 70.0,
			ML.sphere(0.5, false, 8), _mat("dust"), Vector3(0, 0.5, 0), 1.2, 3.2)
	smoke.explosiveness = 0.8
	smoke.damping_min = 1.5
	smoke.damping_max = 3.0
	_particles(root, pos + Vector3.UP * 0.1, Vector3.UP, 14, 1.4, 3.0, 8.0, 70.0,
			ML.box(Vector3(0.05, 0.05, 0.05)), M.solid(Color(0.12, 0.11, 0.1), 0.9), Vector3(0, -9.8, 0))
	_decal(root, Terrain.snap(pos), Terrain.normal(pos.x, pos.z), 3.2, "scorch", M.blot("scorch", Color(0.03, 0.025, 0.02, 0.85)))


## Material-coloured chips + dust puff (bullet hits on props, prop collapses).
static func chips(ctx: Node, pos: Vector3, normal: Vector3, color: Color, amount: int = 8, size: float = 0.03,
		dust_amount: int = 5, dust_scale: float = 1.0) -> void:
	var root := _root(ctx)
	if root == null:
		return
	var key := "chip_" + color.to_html(false)
	if not _mats.has(key):
		_mats[key] = M.solid(color, 0.9)
	_particles(root, pos + normal * 0.03, normal, amount, 0.8, 1.5, 5.0, 55.0,
			ML.box(Vector3(size, size * 0.6, size * 1.6)), _mats[key], Vector3(0, -9.8, 0), 0.5, 1.3)
	if dust_amount > 0:
		var d := _particles(root, pos + normal * 0.06, normal, dust_amount, 1.2 * dust_scale, 0.3, 1.4 * dust_scale, 60.0,
				ML.sphere(0.09 * dust_scale, false, 6), _mat("dust"), Vector3(0, 0.25, 0), 0.7, 1.8)
		d.color = Color(color.lightened(0.35), 0.6)


## Knife swing: a thin crescent that sweeps from the wind-up side across the
## front and fades in a blink. `side` is the slash direction (+1 / -1).
static func slash_trail(ctx: Node, center: Vector3, fwd: Vector3, side: float, hit: bool, heavy: bool) -> void:
	var root := _root(ctx)
	if root == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 14
	var span := deg_to_rad(125.0)
	var r_out := 1.25 if heavy else 1.1
	var r_in := r_out - (0.42 if heavy else 0.3)
	var base_a := atan2(fwd.x, fwd.z)
	var col := Color(1.0, 0.55, 0.5) if hit else Color(0.85, 0.92, 1.0)
	var prev := []
	for i in n + 1:
		var t := float(i) / n
		# from the wind-up side (+side) to the far side; the head (t = 1) is brightest
		var a := base_a + side * span * (0.5 - t)
		var dir := Vector3(sin(a), 0, cos(a))
		var h := lerpf(0.16, -0.18, t)
		var thick := sin(t * PI) * 0.8 + 0.2
		var inner := dir * lerpf(r_out, r_in, thick) + Vector3.UP * h
		var outer := dir * r_out + Vector3.UP * (h + 0.02)
		var alpha := pow(t, 1.6)
		var cur := [inner, outer, Color(col, alpha * 0.25), Color(col, alpha)]
		if not prev.is_empty():
			for v in [[prev[0], prev[2]], [prev[1], prev[3]], [cur[1], cur[3]], [prev[0], prev[2]], [cur[1], cur[3]], [cur[0], cur[2]]]:
				st.set_color(v[1])
				st.add_vertex(v[0])
		prev = cur
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1, 1, 1, 0.95 if heavy else 0.75)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = center
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.16 if heavy else 0.12).set_ease(Tween.EASE_IN)
	tw.tween_property(mi, "scale", Vector3.ONE * 1.08, 0.14)
	tw.chain().tween_callback(mi.queue_free)


## Blood thrown along the cut (knife hits): a fast fan sideways off the blade.
static func knife_spray(ctx: Node, pos: Vector3, cut_dir: Vector3, heavy: bool) -> void:
	var root := _root(ctx)
	if root == null:
		return
	_particles(root, pos, (cut_dir + Vector3.UP * 0.25).normalized(), 26 if heavy else 16, 0.55, 2.5, 6.5, 22.0,
			ML.sphere(0.02, false, 6), _mat("blood"), Vector3(0, -9.8, 0), 0.5, 1.5)
