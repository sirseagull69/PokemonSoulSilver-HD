class_name Look
extends RefCounted
## Materialien und Licht-Stimmung (HD-2D-Look). Texturen kommen zur Laufzeit aus der ROM.

static var _mat_cache := {}


static func material(mat: Dictionary, img: Image) -> Material:
	var key := str(mat.get("name", "")) + str(img.get_instance_id() if img else 0)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = 0.9
	m.metallic_specular = 0.2
	if img:
		m.albedo_texture = ImageTexture.create_from_image(img)
		var p: int = mat.get("tex_param", 0)
		m.texture_repeat = (p >> 16) & 3 != 0
		if img.detect_alpha() != Image.ALPHA_NONE:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.5
	var alpha: int = mat.get("alpha", 31)
	if alpha > 0 and alpha < 31:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = alpha / 31.0
	# DS: Bit 6/7 = Vorder-/Rückseite zeichnen
	match mat.get("cull", 2):
		3: m.cull_mode = BaseMaterial3D.CULL_DISABLED
		1: m.cull_mode = BaseMaterial3D.CULL_FRONT
		_: m.cull_mode = BaseMaterial3D.CULL_BACK
	_mat_cache[key] = m
	return m


## Umgebung: Schatten, SSAO, Glow (Bloom), Farbstimmung, Tiefenschärfe.
static func environment(day := true) -> WorldEnvironment:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.72, 0.95) if day else Color(0.05, 0.07, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.95) if day else Color(0.25, 0.3, 0.55)
	env.ambient_light_energy = 0.55 if day else 0.35
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
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.06
	env.fog_enabled = true
	env.fog_light_color = env.background_color
	env.fog_density = 0.004
	we.environment = env
	return we


static func sun(day := true) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-52, -35, 0)
	l.light_color = Color(1.0, 0.94, 0.82) if day else Color(0.55, 0.65, 1.0)
	l.light_energy = 1.25 if day else 0.25
	l.shadow_enabled = true
	l.shadow_blur = 1.5
	l.directional_shadow_max_distance = 80.0
	return l


## Tilt-Shift wie bei HD-2D.
static func camera_attributes() -> CameraAttributesPractical:
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = 26.0
	ca.dof_blur_far_transition = 14.0
	ca.dof_blur_near_enabled = true
	ca.dof_blur_near_distance = 9.0
	ca.dof_blur_near_transition = 5.0
	ca.dof_blur_amount = 0.12
	return ca
