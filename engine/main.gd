extends Node3D
## Startpunkt: ROM wählen, Stadt laden, frei herumschauen.
## Steuerung (Gamepad): linker Stick bewegen, rechter Stick drehen/zoomen,
## A = Tag/Nacht, B = Effekte an/aus. Tastatur: WASD, Q/E, Pfeile, T, F.

const CFG := "user://settings.cfg"
const ROM_DIRS := ["/storage/emulated/0/ROMs", "/storage/emulated/0/Roms", "/storage/emulated/0/roms",
	"/storage/emulated/0/Download", "/storage/emulated/0/Documents", "/storage/emulated/0"]

var _focus := Node3D.new()
var _cam := Camera3D.new()
var _yaw := 0.0
var _pitch := -48.0
var _dist := 16.0
var _env: WorldEnvironment
var _sun: DirectionalLight3D
var _day := true
var _fx := true
var _label := Label.new()


func _ready() -> void:
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 22)
	var layer := CanvasLayer.new()
	layer.add_child(_label)
	add_child(layer)
	if OS.get_name() == "Android":
		OS.request_permissions()
	_status("Suche ROM …")
	await get_tree().process_frame
	var path := _find_rom()
	if path == "":
		_pick_rom()
	else:
		_start(path)


func _status(t: String) -> void:
	_label.text = t


func _find_rom() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(CFG) == OK:
		var p: String = cfg.get_value("rom", "path", "")
		if p != "" and FileAccess.file_exists(p):
			return p
	for d in ROM_DIRS:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			if f.to_lower().ends_with(".nds"):
				var full: String = d.path_join(f)
				if _is_hgss(full):
					return full
	return ""


func _is_hgss(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	f.seek(0x0C)
	var code := f.get_buffer(3).get_string_from_ascii()
	return code == "IPG" or code == "IPK"   # SoulSilver / HeartGold


func _pick_rom() -> void:
	_status("Keine SoulSilver-/HeartGold-ROM gefunden.\nBitte die .nds-Datei auswählen.")
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.filters = PackedStringArray(["*.nds ; NDS-ROM"])
	fd.file_selected.connect(func(p: String) -> void: _start(p))
	add_child(fd)
	fd.popup_centered_ratio(0.8)


func _start(path: String) -> void:
	_status("Lade ROM …")
	await get_tree().process_frame
	var rom := NdsRom.open(path)
	if rom == null or not rom.has_file("a/0/6/5"):
		_status("Das ist keine HeartGold/SoulSilver-ROM.")
		return
	var cfg := ConfigFile.new()
	cfg.set_value("rom", "path", path)
	cfg.save(CFG)
	_status("Baue Neuborkia …")
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var loader := MapLoader.new(rom, Look.material)
	var town := loader.load_town("T20", 1)
	add_child(town)
	_env = Look.environment(_day)
	add_child(_env)
	_sun = Look.sun(_day)
	add_child(_sun)
	add_child(_focus)
	_cam.attributes = Look.camera_attributes()
	_cam.fov = 32.0
	_focus.add_child(_cam)
	_cam.make_current()
	# Neutraler Marker als Bildmitte (kein Spiel-Sprite)
	var marker := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.25
	cap.height = 1.0
	marker.mesh = cap
	marker.position = Vector3(0, 1.0, 0)
	_focus.add_child(marker)
	_status("Neuborkia geladen (%d ms). A: Tag/Nacht · B: Effekte" % (Time.get_ticks_msec() - t0))


func _process(delta: float) -> void:
	if _cam == null or not _cam.is_inside_tree():
		return
	var mv := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	mv += Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if mv.length() > 0.15:
		var fwd := Vector3(sin(deg_to_rad(_yaw)), 0, cos(deg_to_rad(_yaw)))
		var right := Vector3(fwd.z, 0, -fwd.x)
		_focus.position += (right * -mv.x + fwd * -mv.y) * 8.0 * delta
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if Input.is_key_pressed(KEY_Q): rx -= 1
	if Input.is_key_pressed(KEY_E): rx += 1
	if abs(rx) > 0.15: _yaw -= rx * 90.0 * delta
	if abs(ry) > 0.15: _dist = clamp(_dist + ry * 12.0 * delta, 6.0, 40.0)
	var basis := Basis.from_euler(Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0))
	_cam.transform = Transform3D(basis, basis * Vector3(0, 0, _dist))
	var ca := _cam.attributes as CameraAttributesPractical
	if ca:
		ca.dof_blur_far_distance = _dist + 10.0
		ca.dof_blur_near_distance = max(_dist - 7.0, 1.0)


func _unhandled_input(e: InputEvent) -> void:
	if _env == null:
		return
	if e.is_action_pressed("ui_accept") or (e is InputEventKey and e.pressed and e.keycode == KEY_T):
		_day = not _day
		_env.queue_free(); _sun.queue_free()
		_env = Look.environment(_day); _sun = Look.sun(_day)
		add_child(_env); add_child(_sun)
		_env.environment.ssao_enabled = _fx
	elif e.is_action_pressed("ui_cancel") or (e is InputEventKey and e.pressed and e.keycode == KEY_F):
		_fx = not _fx
		var env := _env.environment
		env.ssao_enabled = _fx
		env.glow_enabled = _fx
		env.adjustment_enabled = _fx
		_sun.shadow_enabled = _fx
		var ca := _cam.attributes as CameraAttributesPractical
		ca.dof_blur_far_enabled = _fx
		ca.dof_blur_near_enabled = _fx
		_status("Effekte " + ("an" if _fx else "aus"))
