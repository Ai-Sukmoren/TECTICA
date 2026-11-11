extends Node
## Real-time day / night cycle. One in-game hour lasts `seconds_per_hour`
## real seconds. Drives the sun / moon light, sky shader, ambient light, fog,
## exposure, camp lamps, the outpost floodlights + searchlight sweep and the
## night fireflies. `night` (0..1) is shared with gameplay (enemy eyesight).

const Nature = preload("res://scripts/world/nature.gd")
const Settings = preload("res://scripts/core/settings.gd")

const SUNRISE := 6.0
const SUNSET := 19.5

var hour := 12.0
var seconds_per_hour := 60.0
var running := true
var night := 0.0
var red_tint := 0.0      # zombie mode: blood-red dusk
var base_exposure := 1.0

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var level
var _t := 0.0


func setup(p_env: Environment, p_sun: DirectionalLight3D, p_level, start_hour: float) -> void:
	env = p_env
	sun = p_sun
	level = p_level
	hour = start_hour
	sky_mat = Nature.sky_material()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	base_exposure = env.tonemap_exposure
	apply_now()


func clock_string() -> String:
	var h := int(hour) % 24
	var m := int(fposmod(hour, 1.0) * 60.0)
	return "%02d:%02d" % [h, m]


func apply_now() -> void:
	_apply(0.0)


func _process(delta: float) -> void:
	_t += delta
	if running and not get_tree().paused:
		hour = fposmod(hour + delta / seconds_per_hour, 24.0)
	_apply(delta)


func _sun_dir(elev_deg: float, az_deg: float) -> Vector3:
	var e := deg_to_rad(elev_deg)
	var a := deg_to_rad(az_deg)
	# az 0 = east (+x), 180 = west; north is -z
	return Vector3(cos(e) * cos(a), sin(e), -cos(e) * sin(a) * 0.35 - cos(e) * 0.25).normalized()


func _apply(delta: float) -> void:
	if env == null:
		return
	var day_t := (hour - SUNRISE) / (SUNSET - SUNRISE)
	var elev: float
	if day_t >= 0.0 and day_t <= 1.0:
		elev = sin(day_t * PI) * 58.0
	else:
		# below the horizon at night, deepest at local midnight
		var nt := fposmod(hour - SUNSET, 24.0) / (24.0 - (SUNSET - SUNRISE))
		elev = -sin(nt * PI) * 40.0
	var az := lerpf(0.0, 180.0, clampf(day_t, 0.0, 1.0))
	var sun_dir := _sun_dir(elev, az)
	var moon_dir := Vector3(-0.35, 0.72, -0.6).normalized()
	night = 1.0 - smoothstep(-7.0, 5.0, elev)
	var golden := (1.0 - smoothstep(4.0, 22.0, elev)) * (1.0 - night)

	# --- key light: the sun by day, the moon by night
	var day_col := Color(1.0, 0.93, 0.82).lerp(Color(1.0, 0.56, 0.28), golden)
	var moon_col := Color(0.55, 0.66, 1.0)
	var sun_k := smoothstep(-3.0, 8.0, elev)
	if elev > -3.5:
		sun.basis = Basis.looking_at(-sun_dir, Vector3.UP)
		sun.light_color = day_col
		sun.light_energy = 1.75 * sun_k + 0.0001
	else:
		sun.basis = Basis.looking_at(-moon_dir, Vector3.UP)
		sun.light_color = moon_col
		sun.light_energy = 0.2 * night
	sun.light_volumetric_fog_energy = lerpf(0.9, 0.4, night)

	# --- sky
	var top_day := Color(0.22, 0.42, 0.72)
	var hor_day := Color(0.66, 0.74, 0.8)
	var top := top_day.lerp(Color(0.2, 0.22, 0.38), golden).lerp(Color(0.012, 0.018, 0.045), night)
	var hor := hor_day.lerp(Color(0.95, 0.55, 0.32), golden).lerp(Color(0.04, 0.055, 0.1), night)
	if red_tint > 0.0:
		top = top.lerp(Color(0.12, 0.02, 0.02), red_tint * 0.6)
		hor = hor.lerp(Color(0.55, 0.12, 0.06), red_tint * 0.7)
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", hor)
	sky_mat.set_shader_parameter("ground_color", hor.darkened(0.7))
	sky_mat.set_shader_parameter("sun_color", day_col)
	sky_mat.set_shader_parameter("night", night)
	sky_mat.set_shader_parameter("sun_vis", smoothstep(-4.0, 1.0, elev))

	# --- ambient, fog, exposure
	var amb_day := Color(0.6, 0.66, 0.74)  # cool sky fill so sun and shade read apart
	var amb := amb_day.lerp(Color(0.75, 0.55, 0.45), golden).lerp(Color(0.16, 0.22, 0.42), night)
	if red_tint > 0.0:
		amb = amb.lerp(Color(0.6, 0.3, 0.28), red_tint * 0.5)
	env.ambient_light_color = amb
	env.ambient_light_energy = lerpf(0.72, 0.5, night)
	var morning := clampf(1.0 - absf(hour - 6.8) / 2.0, 0.0, 1.0)
	env.volumetric_fog_density = 0.004 + morning * 0.006 + night * 0.007 + red_tint * 0.012
	env.volumetric_fog_albedo = hor.lerp(amb, 0.5).lerp(Color(0.8, 0.78, 0.7), 0.35 * (1.0 - night))
	env.fog_light_color = hor
	var bright := float(Settings.v.get("brightness", 1.0))
	env.tonemap_exposure = base_exposure * bright * lerpf(1.0, 1.75, night)
	if level == null:
		return

	# --- lamps
	level.night = night
	var lamp_on := smoothstep(0.25, 0.6, night)
	for e in level.lamp_lights:
		var l: Light3D = e.light
		if not is_instance_valid(l):
			continue
		var g: String = e.group
		var on := lamp_on
		if g in ["interior", "outpost_interior"]:
			on = 1.0
		elif g == "fire":
			on = lerpf(0.55, 1.0, lamp_on)
		elif g == "beacon":
			on = 1.0 if fmod(_t, 1.6) < 0.25 else 0.0
		if g in ["outpost", "beacon", "outpost_interior"] and not level.outpost_powered:
			on = 0.0
		var energy := float(e.base) * on
		if e.get("flicker", false):
			energy *= 0.8 + 0.2 * sin(_t * 13.0) * sin(_t * 7.3 + 1.0)
		l.light_energy = energy
		l.visible = energy > 0.01
		var bulb = e.get("bulb")
		if bulb != null and is_instance_valid(bulb):
			bulb.visible = on > 0.05
		if e.get("sweep", false):
			l.rotation.y = sin(_t * 0.35) * 1.4
	for f in level.fireflies:
		var show := night > 0.5
		if f.visible != show:
			f.visible = show
			f.emitting = show
