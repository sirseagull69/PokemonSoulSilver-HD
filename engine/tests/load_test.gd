extends SceneTree
## Headless-Test: lädt Neuborkia aus einer ROM und gibt nur Zahlen aus.
## Aufruf: godot --headless --path engine -s tests/load_test.gd -- /pfad/zur/rom.nds

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var rom := NdsRom.open(args[0])
	if rom == null:
		print("FEHLER: ROM"); quit(1); return
	print("Spielcode ", rom.game_code)
	var t0 := Time.get_ticks_msec()
	var loader := MapLoader.new(rom, Look.material)
	print("ARM9 ", loader._arm9.size(), " Bytes, Karten ", loader.map_names.size())
	var town := loader.load_town("T20", 1)
	var meshes := 0
	var tris := 0
	var surf := 0
	var notex := 0
	for c in town.get_children():
		var mi := c as MeshInstance3D
		if mi and mi.mesh:
			meshes += 1
			for s in mi.mesh.get_surface_count():
				surf += 1
				tris += mi.mesh.surface_get_array_len(s) / 3
				var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
				if m and m.albedo_texture == null: notex += 1
	print("Kopftabelle @", loader._headers_off, " Tileset ", loader._tileset_of(loader.header_id("T20")))
	print("Objekte ", meshes, " Flächen ", surf, " Dreiecke ", tris, " ohne Textur ", notex, " Zeit ", Time.get_ticks_msec() - t0, " ms")
	var det := Details.new()
	det.build(town)
	for c in det.get_children():
		if c.name == "Wasser": print("Wasser-Dreiecke ", (c as MeshInstance3D).mesh.surface_get_array_len(0) / 3)
		if c.name == "Gras": print("Grasbüschel ", (c as MultiMeshInstance3D).multimesh.instance_count)
	det.free()
	town.free()
	quit(0 if tris > 0 else 1)
