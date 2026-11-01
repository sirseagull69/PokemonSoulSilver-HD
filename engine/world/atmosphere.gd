class_name Atmosphere
extends Node3D
## Tageszeit, Wetter und Licht-Stimmung in einem Knoten.
## Alles wird weich überblendet; es gibt nur EINE WorldEnvironment.

enum Wetter { KLAR, WOLKIG, REGEN, NEBEL }
const WETTER_NAMEN := ["Klar", "Wolkig", "Regen", "Nebel"]

var time_of_day := 13.0          # 0..24
var _target_time := 13.0
var wetter := Wetter.KLAR
var effects := true
var _w := [1.0, 0.0, 0.0, 0.0]   # aktuelle Wetter-Gewichte (weich)

var env := Environment.new()
var _we := WorldEnvironment.new()
var sun := DirectionalLight3D.new()
var _clouds := Decal.new()
var _rain := GPUParticles3D.new()
var _lamps: Array[OmniLight3D] = []
var follow: Node3D               # Regen folgt diesem Knoten (Kamera-Fokus)


func _ready() -> void:
	_we.environment = env
	add_child(_we)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 80.0
	sun.light_volumetric_fog_energy = 1.6
	add_child(sun)
	_setup_env()
	_setup_clouds()
	_setup_rain()
	_apply(1.0)


func _setup_env() -> void:
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.95
	env.adjustment_enabled = true
	env.fog_enabled = true
	# Volumetrischer Nebel = sichtbare Sonnenstrahlen zwischen Bäumen und Häusern
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.15
	env.volumetric_fog_anisotropy = 0.6


## Wandernde Wolkenschatten: großes Decal mit Rauschen, das langsam driftet.
func _setup_clouds() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.006
	noise.fractal_octaves = 4
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 1))
	grad.add_point(0.45, Color(0, 0, 0, 0))
	grad.add_point(0.62, Color(0, 0, 0, 0.85))
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = grad
	_clouds.texture_albedo = tex
	_clouds.size = Vector3(220, 80, 220)
	_clouds.position = Vector3(0, 20, 0)
	_clouds.albedo_mix = 1.0
	_clouds.upper_fade = 0.0
	_clouds.lower_fade = 0.0
	add_child(_clouds)


func _setup_rain() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 0.5, 30)
	pm.direction = Vector3(0.15, -1, 0.05)
	pm.spread = 3.0
	pm.initial_velocity_min = 28.0
	pm.initial_velocity_max = 34.0
	pm.gravity = Vector3(0, -20, 0)
	var drop := QuadMesh.new()
	drop.size = Vector2(0.03, 0.7)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.75, 0.82, 0.95, 0.45)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	drop.material = dm
	_rain.draw_pass_1 = drop
	_rain.process_material = pm
	_rain.amount = 3500
	_rain.lifetime = 1.2
	_rain.visibility_aabb = AABB(Vector3(-35, -40, -35), Vector3(70, 45, 70))
	_rain.position = Vector3(0, 22, 0)
	_rain.emitting = false
	add_child(_rain)


## Warme Lichter vor den Gebäuden, nur nachts. Positionen aus den geladenen Gebäuden.
func add_lamps_for(town: Node3D) -> void:
	for c in town.get_children():
		var mi := c as MeshInstance3D
		if mi == null or not mi.name.begins_with("Gebaeude") or mi.mesh == null:
			continue
		var bb := mi.mesh.get_aabb()
		if bb.size.x < 3.0 or bb.size.y < 2.0:
			continue   # nur Häuser, keine Zäune/Schilder
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.4)
		l.omni_range = 5.5
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.position = mi.position + Vector3(bb.get_center().x, bb.position.y + 1.4, bb.end.z + 0.6)
		town.add_child(l)
		_lamps.append(l)


func toggle_day() -> void:
	_target_time = 22.0 if is_day() else 13.0


func is_day() -> bool:
	return _target_time > 6.0 and _target_time < 19.0


func next_weather() -> String:
	wetter = (wetter + 1) % 4
	return WETTER_NAMEN[wetter]


func set_effects(on: bool) -> void:
	effects = on
	env.ssao_enabled = on
	env.glow_enabled = on
	env.adjustment_enabled = on
	env.volumetric_fog_enabled = on
	sun.shadow_enabled = on
	_clouds.visible = on


func _process(delta: float) -> void:
	# Zeit weich zum Ziel laufen lassen (~3 s für einen Wechsel)
	var d := _target_time - time_of_day
	time_of_day += clamp(d, -delta * 3.0, delta * 3.0)
	for i in 4:
		_w[i] = move_toward(_w[i], 1.0 if i == wetter else 0.0, delta * 0.6)
	if follow:
		_rain.global_position = follow.global_position + Vector3(0, 22, 0)
	_clouds.position.x = fmod(_clouds.position.x + delta * 1.4, 220.0)
	_clouds.position.z = fmod(_clouds.position.z + delta * 0.6, 220.0)
	_apply(delta)


func _apply(_delta: float) -> void:
	# Tageslicht 0 (Nacht) .. 1 (Mittag), mit Dämmerung
	var t := time_of_day
	var daylight: float = clamp(sin((t - 6.0) / 12.0 * PI), 0.0, 1.0)
	var dusk: float = clamp(1.0 - abs(daylight - 0.25) * 4.0, 0.0, 1.0)   # Abend-/Morgenrot
	var night := 1.0 - daylight

	var wolkig: float = _w[1]
	var regen: float = _w[2]
	var nebel: float = _w[3]
	var grau: float = clamp(wolkig * 0.5 + regen * 0.9 + nebel * 0.6, 0.0, 1.0)

	# Sonne: Winkel folgt der Uhrzeit, nachts Mondlicht
	var elev: float = lerp(8.0, 58.0, daylight)
	sun.rotation_degrees = Vector3(-elev, -35.0 + (t - 12.0) * 6.0, 0)
	var sun_day := Color(1.0, 0.94, 0.82).lerp(Color(1.0, 0.62, 0.38), dusk)
	var sun_col := sun_day.lerp(Color(0.55, 0.65, 1.0), night)
	sun.light_color = sun_col.lerp(Color(0.8, 0.82, 0.88), grau)
	sun.light_energy = lerp(0.22, 1.3, daylight) * (1.0 - grau * 0.65)

	var sky_day := Color(0.55, 0.72, 0.95).lerp(Color(0.95, 0.6, 0.45), dusk * 0.7)
	var sky := sky_day.lerp(Color(0.04, 0.06, 0.14), night).lerp(Color(0.5, 0.53, 0.58) * (0.3 + daylight * 0.7), grau)
	env.background_color = sky
	env.ambient_light_color = Color(0.75, 0.8, 0.95).lerp(Color(0.25, 0.3, 0.55), night).lerp(Color(0.7, 0.72, 0.76), grau)
	env.ambient_light_energy = lerp(0.35, 0.55, daylight) + grau * 0.15
	env.adjustment_saturation = lerp(1.15, 0.85, grau)
	env.adjustment_contrast = lerp(1.06, 0.98, grau)

	env.fog_light_color = sky
	env.fog_density = 0.004 + nebel * 0.03 + regen * 0.01
	env.volumetric_fog_density = 0.012 + nebel * 0.03 + regen * 0.01
	env.volumetric_fog_albedo = Color(0.9, 0.92, 1.0)

	_clouds.modulate = Color(1, 1, 1, clamp(0.18 + wolkig * 0.45 + regen * 0.3, 0.0, 0.75) * daylight)
	_rain.emitting = regen > 0.3 and effects
	_rain.amount_ratio = clamp(regen, 0.05, 1.0)

	var lamp_e: float = clamp(night * 1.6 + grau * 0.4, 0.0, 1.6)
	for l in _lamps:
		l.light_energy = lamp_e
