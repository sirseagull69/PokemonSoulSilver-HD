class_name Details
extends Node3D
## Liebe zum Detail – alles prozedural, nichts aus der ROM nachgezeichnet:
## animiertes Wasser auf Wasserkacheln, feines Gras auf grünem Boden (Farbe aus
## der Bodentextur darunter), Pollen am Tag, Glühwürmchen nachts, fallende Blätter.

const WATER_MIN := 0x10
const WATER_MAX := 0x1F
const TREE := 0x06

var atmo: Atmosphere
var _water_mat: ShaderMaterial
var _grass_mat: ShaderMaterial
var _pollen: GPUParticles3D
var _flies: GPUParticles3D
var _leaves: GPUParticles3D
var follow: Node3D


## Höhe der Geländeoberfläche an (x,z) per Strahl von oben auf die Dreiecke.
static func _height_at(faces: PackedVector3Array, p: Vector3) -> float:
	var best := -INF
	var from := Vector3(p.x, 100.0, p.z)
	for i in range(0, faces.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, faces[i], faces[i + 1], faces[i + 2])
		if hit != null and hit.y > best:
			best = hit.y
	return best


## Höhe UND Bodenfarbe (aus Textur × Vertexfarbe) an (x,z) bestimmen.
static func _ground(mi: MeshInstance3D, p: Vector3) -> Array:
	var best := -INF
	var col := Color.BLACK
	var from := Vector3(p.x, 100.0, p.z)
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
		for i in range(0, vs.size(), 3):
			var hit = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, vs[i], vs[i + 1], vs[i + 2])
			if hit == null or hit.y <= best:
				continue
			best = hit.y
			var bc := Geometry3D.get_triangle_barycentric_coords(hit, vs[i], vs[i + 1], vs[i + 2])
			var c := Color.WHITE
			if cols.size() > i + 2:
				c = cols[i] * bc.x + cols[i + 1] * bc.y + cols[i + 2] * bc.z
			if mat and mat.albedo_texture and uvs.size() > i + 2:
				var uv: Vector2 = uvs[i] * bc.x + uvs[i + 1] * bc.y + uvs[i + 2] * bc.z
				var img := mat.albedo_texture.get_image()
				var w := img.get_width()
				var h := img.get_height()
				var tx := posmod(int(floor(uv.x * w)), w)
				var ty := posmod(int(floor(uv.y * h)), h)
				# 3x3 mitteln, damit einzelne Pixel nicht dominieren
				var sum := Color(0, 0, 0, 0)
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						sum += img.get_pixel(posmod(tx + dx, w), posmod(ty + dy, h))
				c = c * (sum / 9.0)
			col = c
	return [best, col]


static func _is_green(c: Color) -> bool:
	return c.g > c.r * 1.08 and c.g > c.b * 1.15 and c.g > 0.25


func build(town: Node3D) -> void:
	_make_materials()
	var water_tiles: Array[Vector3] = []
	var grass_spots: Array[Vector3] = []
	var grass_cols: Array[Color] = []
	var tree_spots: Array[Vector3] = []
	for c in town.get_children():
		var mi := c as MeshInstance3D
		if mi == null or not mi.is_in_group("land") or not mi.has_meta("tiles"):
			continue
		var tiles: PackedByteArray = mi.get_meta("tiles")
		var faces := mi.mesh.get_faces()
		for y in 32:
			for x in 32:
				var o := (y * 32 + x) * 2
				if o + 1 >= tiles.size():
					continue
				var beh := tiles[o]
				var blocked := tiles[o + 1] & 0x80
				var local := Vector3(x - 16 + 0.5, 0, y - 16 + 0.5)
				if beh >= WATER_MIN and beh <= WATER_MAX:
					var h := _height_at(faces, local)
					if h > -INF:
						water_tiles.append(mi.position + Vector3(local.x, h + 0.05, local.z))
				elif beh == TREE:
					if (x + y) % 3 == 0:
						var h := _height_at(faces, local)
						if h > -INF:
							tree_spots.append(mi.position + Vector3(local.x, h, local.z))
				elif beh == 0 and blocked == 0:
					# Gras nur dort, wo der Boden darunter wirklich grün ist (je 2x2 Proben pro Kachel)
					for q in [Vector3(-0.25, 0, -0.25), Vector3(0.25, 0, -0.25), Vector3(-0.25, 0, 0.25), Vector3(0.25, 0, 0.25)]:
						var g := _ground(mi, local + q)
						if g[0] > -INF and _is_green(g[1]):
							grass_spots.append(mi.position + Vector3(local.x + q.x, g[0], local.z + q.z))
							grass_cols.append(g[1])
	_build_water(water_tiles)
	_build_grass(grass_spots, grass_cols)
	_build_particles(tree_spots)


static func _next_to(tiles: PackedByteArray, x: int, y: int, beh: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if nx >= 0 and ny >= 0 and nx < 32 and ny < 32 and tiles[(ny * 32 + nx) * 2] == beh:
			return true
	return false


func _make_materials() -> void:
	var ws := Shader.new()
	ws.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
uniform vec3 deep : source_color = vec3(0.08, 0.28, 0.42);
uniform vec3 shallow : source_color = vec3(0.25, 0.62, 0.72);
uniform sampler2D depth_tex : hint_depth_texture;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

float wave(vec2 p, float t) {
	return sin(p.x * 1.7 + t * 1.3) * 0.5 + sin(p.y * 2.3 - t * 1.1) * 0.35 + sin((p.x + p.y) * 3.1 + t * 2.0) * 0.15;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += wave(w.xz, TIME) * 0.04;
}

void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float e = 0.05;
	float hx = wave(w.xz + vec2(e, 0.0), TIME) - wave(w.xz - vec2(e, 0.0), TIME);
	float hz = wave(w.xz + vec2(0.0, e), TIME) - wave(w.xz - vec2(0.0, e), TIME);
	vec3 n = normalize(vec3(-hx * 0.6, 1.0, -hz * 0.6));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	// Tiefe hinter dem Wasser -> flach am Ufer, mit Schaum
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 wp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float behind = -wp.z / wp.w + VERTEX.z;
	float depth = clamp(behind / 1.5, 0.0, 1.0);
	vec3 refr = texture(screen_tex, SCREEN_UV + n.xz * 0.01).rgb;
	vec3 col = mix(shallow, deep, depth);
	col = mix(refr * shallow * 1.6, col, 0.35 + depth * 0.55);
	float foam = smoothstep(0.25, 0.0, behind) * (0.6 + 0.4 * sin(TIME * 2.0 + w.x * 4.0));
	ALBEDO = mix(col, vec3(0.95), foam * 0.7);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.8;
	ALPHA = 0.88;
}
"""
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = ws

	var gs := Shader.new()
	gs.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform float wind = 1.0;
varying float h;
varying vec3 ground;
void vertex() {
	h = UV.y;                      // 1 = unten, 0 = Spitze
	ground = COLOR.rgb;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bend = (1.0 - h) * (1.0 - h);
	float sway = sin(TIME * 1.6 + w.x * 0.6 + w.z * 0.4) * 0.07 + sin(TIME * 3.7 + w.z * 1.8 + w.x) * 0.02;
	VERTEX.x += sway * bend * wind;
	VERTEX.z += sway * 0.5 * bend * wind;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz;   // wie der Boden beleuchtet
}
void fragment() {
	vec3 base = ground * 0.82;
	vec3 tip = ground * vec3(1.18, 1.22, 1.0) + vec3(0.04, 0.04, 0.0);
	ALBEDO = mix(tip, base, h);
	ROUGHNESS = 0.9;
	BACKLIGHT = ground * 0.35;
	AO = mix(1.0, 0.7, h);
	AO_LIGHT_AFFECT = 0.4;
}
"""
	_grass_mat = ShaderMaterial.new()
	_grass_mat.shader = gs


func _build_water(tiles: Array[Vector3]) -> void:
	if tiles.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tiles:
		# je Kachel 4x4 Unterteilung, damit die Wellen sichtbar werden
		for sy in 4:
			for sx in 4:
				var a := t + Vector3(-0.5 + sx * 0.25, 0, -0.5 + sy * 0.25)
				var b := a + Vector3(0.25, 0, 0)
				var c := a + Vector3(0.25, 0, 0.25)
				var d := a + Vector3(0, 0, 0.25)
				for v in [a, b, c, a, c, d]:
					st.set_normal(Vector3.UP)
					st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "Wasser"
	mi.mesh = st.commit()
	mi.material_override = _water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_grass(spots: Array[Vector3], cols: Array[Color]) -> void:
	if spots.is_empty():
		return
	# Feines Büschel: 10 schmale, leicht gebogene Halme (je 2 Segmente)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in 10:
		var ang := rng.randf() * TAU
		var off := Vector3(rng.randf_range(-0.16, 0.16), 0, rng.randf_range(-0.16, 0.16))
		var side := Vector3(cos(ang), 0, sin(ang)) * 0.018
		var lean := Vector3(-side.z, 0, side.x).normalized() * rng.randf_range(0.03, 0.08)
		var hgt := rng.randf_range(0.14, 0.26)
		var p0 := off
		var p1 := off + Vector3(0, hgt * 0.55, 0) + lean * 0.35
		var p2 := off + Vector3(0, hgt, 0) + lean
		# untere Hälfte (Viereck)
		for v in [[p0 - side, 1.0], [p0 + side, 1.0], [p1 + side * 0.6, 0.45], [p0 - side, 1.0], [p1 + side * 0.6, 0.45], [p1 - side * 0.6, 0.45]]:
			st.set_uv(Vector2(0, v[1])); st.set_normal(Vector3.UP); st.add_vertex(v[0])
		# Spitze
		for v in [[p1 - side * 0.6, 0.45], [p1 + side * 0.6, 0.45], [p2, 0.0]]:
			st.set_uv(Vector2(0, v[1])); st.set_normal(Vector3.UP); st.add_vertex(v[0])
	var tuft := st.commit()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = tuft
	mm.instance_count = spots.size()
	for i in spots.size():
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.25))
		var j := Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12))
		mm.set_instance_transform(i, Transform3D(basis, spots[i] + j))
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Gras"
	mmi.multimesh = mm
	mmi.material_override = _grass_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _particle(amount: int, life: float, color: Color, size: float, extent: Vector3, emissive: float) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extent
	pm.gravity = Vector3.ZERO
	pm.direction = Vector3(1, 0.2, 0.3)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 3.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	var dg := Gradient.new()
	dg.set_color(0, Color(1, 1, 1, 1))
	dg.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = dg
	m.albedo_texture = dot
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emissive
	q.material = m
	var p := GPUParticles3D.new()
	p.draw_pass_1 = q
	p.process_material = pm
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.visibility_aabb = AABB(-extent - Vector3.ONE * 4, extent * 2 + Vector3.ONE * 8)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _build_particles(tree_spots: Array[Vector3]) -> void:
	_pollen = _particle(260, 8.0, Color(1.0, 0.97, 0.85, 0.7), 0.06, Vector3(14, 3, 14), 0.4)
	_flies = _particle(90, 6.0, Color(0.85, 1.0, 0.45, 1.0), 0.09, Vector3(14, 1.5, 14), 6.0)
	_flies.position.y = 1.0
	# Blätter: rieseln langsam aus den Baumreihen
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	var pts := PackedVector3Array()
	for t in tree_spots:
		pts.append(t + Vector3(0, 3.0, 0))
	if pts.is_empty():
		pts.append(Vector3(0, 3, 0))
	var img := Image.create_empty(pts.size(), 1, false, Image.FORMAT_RGBF)
	for i in pts.size():
		img.set_pixel(i, 0, Color(pts[i].x, pts[i].y, pts[i].z))
	pm.emission_point_texture = ImageTexture.create_from_image(img)
	pm.emission_point_count = pts.size()
	pm.gravity = Vector3(0.3, -0.35, 0.1)
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	var leaf := QuadMesh.new()
	leaf.size = Vector2(0.12, 0.08)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.5, 0.62, 0.22)
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	lm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	leaf.material = lm
	_leaves = GPUParticles3D.new()
	_leaves.draw_pass_1 = leaf
	_leaves.process_material = pm
	_leaves.amount = 160
	_leaves.lifetime = 9.0
	_leaves.preprocess = 9.0
	_leaves.visibility_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 30, 120))
	add_child(_leaves)


func _process(_delta: float) -> void:
	if atmo == null:
		return
	var day: float = clamp(sin((atmo.time_of_day - 6.0) / 12.0 * PI), 0.0, 1.0)
	var on := atmo.effects
	if follow:
		_pollen.global_position = follow.global_position + Vector3(0, 1.5, 0)
		_flies.global_position = follow.global_position + Vector3(0, 0.8, 0)
	_pollen.emitting = on and day > 0.3 and atmo.rain < 0.2 and atmo.fog < 0.6
	_flies.emitting = on and day < 0.15 and atmo.rain < 0.2
	_leaves.emitting = on
	# Wind treibt Gras und Blätter; bei Sturm deutlich mehr
	_grass_mat.set_shader_parameter("wind", 0.6 + atmo.wind * 2.4)
	var lpm := _leaves.process_material as ParticleProcessMaterial
	lpm.gravity = Vector3(0.3 + atmo.wind * 4.0, -0.35, 0.1 + atmo.wind * 1.2)
	_leaves.amount_ratio = clamp(0.3 + atmo.wind, 0.0, 1.0)
