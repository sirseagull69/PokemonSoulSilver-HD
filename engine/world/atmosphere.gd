class_name Atmosphere
extends Node3D
## Tageszeit, Wetter und Licht-Stimmung in einem Knoten.
## Wetter = Mischung aus Wolken, Regen, Nebel, Wind, Gewitter und Wärme.
## Alles wird weich überblendet; es gibt nur EINE WorldEnvironment.

# Wolken, Regen, Nebel, Wind, Gewitter, Wärme (0..1)
const PRESETS := [
	["Sonnig",            [0.05, 0.0, 0.0, 0.2, 0.0, 1.0]],
	["Klar",              [0.2, 0.0, 0.0, 0.3, 0.0, 0.5]],
	["Wolkig",            [0.7, 0.0, 0.1, 0.5, 0.0, 0.0]],
	["Nebel",             [0.5, 0.0, 1.0, 0.1, 0.0, 0.0]],
	["Nebel + Niesel",    [0.8, 0.35, 0.8, 0.2, 0.0, 0.0]],
	["Regen",             [0.9, 0.75, 0.25, 0.6, 0.0, 0.0]],
	["Gewitter",          [1.0, 1.0, 0.3, 0.85, 1.0, 0.0]],
	["Sturm",             [0.85, 0.5, 0.15, 1.0, 0.3, 0.0]],
]

var time_of_day := 13.0          # 0..24
var _target_time := 13.0
var preset := 1
var effects := true
# aktuelle (weich laufende) Werte
var clouds := 0.2
var rain := 0.0
var fog := 0.0
var wind := 0.3
var storm := 0.0
var warmth := 0.5
var wetness := 0.0               # sammelt sich bei Regen, trocknet danach

var env := Environment.new()
var _we := WorldEnvironment.new()
var sun := DirectionalLight3D.new()
var _clouds := Decal.new()
var _puddles := Decal.new()
var _rain := GPUParticles3D.new()
var _rain_pm := ParticleProcessMaterial.new()
var _lamps: Array[OmniLight3D] = []
var _flash := 0.0
var _next_flash := 4.0
var _cloud_off := Vector2.ZERO
var follow: Node3D               # Regen folgt diesem Knoten (Kamera-Fokus)
var quality := 2                 # 2 = voll, 1 = mittel, 0 = sparsam (automatisch)
var _fps_low := 0.0
var _fps_high := 0.0


func _ready() -> void:
	_we.environment = env
	add_child(_we)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 80.0
	sun.light_volumetric_fog_energy = 1.6
	add_child(sun)
	_setup_env()
	_setup_puddles()
	_setup_rain()
	_apply(0.0)


func _setup_env() -> void:
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.tonemap_white = 1.4
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.42
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.15
	env.adjustment_enabled = true
	env.fog_enabled = true
	env.fog_height = 1.5             # Bodennebel unterhalb dieser Höhe dichter
	env.volumetric_fog_enabled = true
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.25
	env.volumetric_fog_anisotropy = 0.6
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 1.5


static func _noise_tex(freq: float, a: float, b: float, alpha_max: float, size := 512) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = freq
	noise.fractal_octaves = 4
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, alpha_max))
	grad.add_point(a, Color(0, 0, 0, 0))
	grad.add_point(b, Color(0, 0, 0, alpha_max))
	var tex := NoiseTexture2D.new()
	tex.width = size
	tex.height = size
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = grad
	return tex


## Wandernde Wolkenschatten.
func _setup_clouds() -> void:
	_clouds.texture_albedo = _noise_tex(0.006, 0.45, 0.62, 0.85)
	_clouds.size = Vector3(220, 80, 220)
	_clouds.position = Vector3(0, 20, 0)
	_clouds.upper_fade = 0.0
	_clouds.lower_fade = 0.0
	add_child(_clouds)


## Pfützen: dunkle, glatte Flecken, die bei Nässe auftauchen und spiegeln (SSR).
func _setup_puddles() -> void:
	var mask := _noise_tex(0.02, 0.58, 0.66, 0.55, 512)
	# ORM: R=AO, G=Rauheit, B=Metall – glatt in den Pfützen
	var orm_noise := FastNoiseLite.new()
	orm_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	orm_noise.frequency = 0.02
	orm_noise.fractal_octaves = 4
	var og := Gradient.new()
	og.set_color(0, Color(1, 0.9, 0, 0))
	og.set_color(1, Color(1, 0.02, 0, 1))
	og.add_point(0.55, Color(1, 0.6, 0, 0.6))
	og.add_point(0.62, Color(1, 0.02, 0, 1))
	var orm := NoiseTexture2D.new()
	orm.width = 512
	orm.height = 512
	orm.seamless = true
	orm.noise = orm_noise
	orm.color_ramp = og
	_puddles.texture_albedo = mask
	_puddles.texture_orm = orm
	_puddles.size = Vector3(110, 30, 110)
	_puddles.position = Vector3(0, 8, 0)
	_puddles.upper_fade = 0.0
	_puddles.lower_fade = 0.0
	_puddles.normal_fade = 0.6       # nur auf flachem Boden, nicht an Wänden
	_puddles.albedo_mix = 0.6
	add_child(_puddles)


func _setup_rain() -> void:
	_rain_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_pm.emission_box_extents = Vector3(22, 0.5, 22)
	_rain_pm.direction = Vector3(0.15, -1, 0.05)
	_rain_pm.spread = 3.0
	_rain_pm.initial_velocity_min = 28.0
	_rain_pm.initial_velocity_max = 34.0
	_rain_pm.gravity = Vector3(0, -20, 0)
	var drop := QuadMesh.new()
	drop.size = Vector2(0.035, 0.9)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.75, 0.82, 0.95, 0.45)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	drop.material = dm
	_rain.draw_pass_1 = drop
	_rain.process_material = _rain_pm
	_rain.amount = 1800
	_rain.lifetime = 1.2
	_rain.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 45, 80))
	_rain.position = Vector3(0, 22, 0)
	_rain.emitting = false
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)


## Warme Lichter vor den Gebäuden, nur nachts / bei Schlechtwetter.
func add_lamps_for(town: Node3D) -> void:
	for c in town.get_children():
		var mi := c as MeshInstance3D
		if mi == null or not mi.name.begins_with("Gebaeude") or mi.mesh == null:
			continue
		var bb := mi.mesh.get_aabb()
		if bb.size.x < 3.0 or bb.size.y < 2.0:
			continue
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.4)
		l.omni_range = 5.5
		l.light_energy = 0.0
		l.position = mi.position + Vector3(bb.get_center().x, bb.position.y + 1.4, bb.end.z + 0.6)
		town.add_child(l)
		_lamps.append(l)


func toggle_day() -> void:
	_target_time = 22.0 if is_day() else 13.0


func is_day() -> bool:
	return _target_time > 6.0 and _target_time < 19.0


func next_weather() -> String:
	preset = (preset + 1) % PRESETS.size()
	return PRESETS[preset][0]


func weather_name() -> String:
	return PRESETS[preset][0]


func set_effects(on: bool) -> void:
	effects = on
	env.ssao_enabled = on
	env.glow_enabled = on
	env.adjustment_enabled = on
	env.volumetric_fog_enabled = on
	sun.shadow_enabled = on
	_puddles.visible = on


func _auto_quality(delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	if fps > 0 and fps < 48:
		_fps_low += delta
		_fps_high = 0.0
	elif fps >= 58:
		_fps_high += delta
		_fps_low = 0.0
	if _fps_low > 1.5 and quality > 0:
		quality -= 1
		_fps_low = 0.0
	elif _fps_high > 12.0 and quality < 2:
		quality += 1
		_fps_high = 0.0


func _process(delta: float) -> void:
	_auto_quality(delta)
	var d := _target_time - time_of_day
	time_of_day += clamp(d, -delta * 3.0, delta * 3.0)
	var p: Array = PRESETS[preset][1]
	var k := delta * 0.5
	clouds = move_toward(clouds, p[0], k)
	rain = move_toward(rain, p[1], k)
	fog = move_toward(fog, p[2], k * 0.7)
	wind = move_toward(wind, p[3], k)
	storm = move_toward(storm, p[4], k)
	warmth = move_toward(warmth, p[5], k)
	# Nässe: steigt bei Regen (~10 s bis nass), trocknet langsam (~1 min)
	if rain > 0.1:
		wetness = min(wetness + delta * rain * 0.12, 1.0)
	else:
		wetness = max(wetness - delta * 0.018, 0.0)
	# Blitze
	_flash = max(_flash - delta * 6.0, 0.0)
	if storm > 0.5 and effects:
		_next_flash -= delta
		if _next_flash <= 0.0:
			_flash = 1.0
			_next_flash = randf_range(2.5, 9.0)
		elif _next_flash < 0.12 and _next_flash > 0.05:
			_flash = max(_flash, 0.6)   # Doppelblitz
	if follow:
		_rain.global_position = follow.global_position + Vector3(0, 22, 0)
	_cloud_off += Vector2(1.4, 0.6) * (0.5 + wind * 3.0) * delta
	_apply(delta)


func _apply(_delta: float) -> void:
	var t := time_of_day
	var daylight: float = clamp(sin((t - 6.0) / 12.0 * PI), 0.0, 1.0)
	var dusk: float = clamp(1.0 - abs(daylight - 0.25) * 4.0, 0.0, 1.0)
	var night := 1.0 - daylight
	var grau: float = clamp(clouds * 0.45 + rain * 0.5 + fog * 0.4 + storm * 0.3, 0.0, 1.0)

	var elev: float = lerp(8.0, 58.0, daylight)
	sun.rotation_degrees = Vector3(-elev, -35.0 + (t - 12.0) * 6.0, 0)
	var sun_day := Color(1.0, 0.94, 0.82).lerp(Color(1.0, 0.86, 0.6), warmth * 0.5).lerp(Color(1.0, 0.62, 0.38), dusk)
	var sun_col := sun_day.lerp(Color(0.55, 0.65, 1.0), night).lerp(Color(0.8, 0.82, 0.88), grau)
	sun.light_color = sun_col.lerp(Color(0.85, 0.9, 1.0), _flash)
	sun.light_energy = lerp(0.2, 1.0 + warmth * 0.08, daylight) * (1.0 - grau * 0.6) + _flash * 4.0

	var sky_day := Color(0.55, 0.72, 0.95).lerp(Color(0.48, 0.7, 1.0), warmth * 0.4).lerp(Color(0.95, 0.6, 0.45), dusk * 0.7)
	var storm_sky := Color(0.32, 0.34, 0.4).lerp(Color(0.2, 0.21, 0.26), storm)
	var sky := sky_day.lerp(Color(0.04, 0.06, 0.14), night).lerp(storm_sky * (0.35 + daylight * 0.65), grau)
	sky = sky.lerp(Color(0.8, 0.85, 1.0), _flash * 0.7)
	env.background_color = sky
	env.ambient_light_color = Color(0.75, 0.8, 0.95).lerp(Color(0.25, 0.3, 0.55), night).lerp(Color(0.68, 0.7, 0.75), grau)
	env.ambient_light_energy = lerp(0.32, 0.45, daylight) + grau * 0.18 + _flash * 1.5
	env.adjustment_saturation = lerp(1.08 + warmth * 0.05, 0.8, grau)
	env.adjustment_contrast = lerp(1.06, 0.97, grau)

	# Nebel: Fern-Nebel + dichter Bodennebel + volumetrisch (Lichtstrahlen)
	env.fog_light_color = sky.lerp(Color(0.8, 0.82, 0.86), fog * 0.5)
	env.fog_density = 0.003 + fog * 0.055 + rain * 0.012
	env.fog_height_density = fog * 0.9
	env.fog_aerial_perspective = 0.3
	env.volumetric_fog_density = 0.01 + fog * 0.06 + rain * 0.012
	env.volumetric_fog_albedo = Color(0.9, 0.92, 1.0)


	# Regen: Menge, Schräglage durch Wind
	_rain.emitting = rain > 0.15 and effects
	_rain.amount_ratio = clamp(rain, 0.05, 1.0) * [0.45, 0.75, 1.0][quality]
	# Volumetrischer Nebel ist bei Regen am teuersten: sparsam -> aus, normaler Nebel bleibt
	env.volumetric_fog_enabled = effects and quality > 0
	env.ssao_enabled = effects and quality > 0
	_rain_pm.direction = Vector3(0.15 + wind * 0.9, -1, 0.05 + wind * 0.3)

	# Pfützen + spiegelnder Boden
	_puddles.modulate = Color(1, 1, 1, wetness)
	env.ssr_enabled = false

	var lamp_e: float = clamp(night * 1.6 + grau * 0.5, 0.0, 1.6)
	for l in _lamps:
		l.light_energy = lamp_e
