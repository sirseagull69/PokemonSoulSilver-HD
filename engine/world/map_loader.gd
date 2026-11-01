class_name MapLoader
extends RefCounted
## Baut aus der ROM des Nutzers eine Overworld-Szene (Gelände + Gebäude).
## Pfade gelten für HeartGold/SoulSilver (alle Sprachversionen).

const BLOCK := 32.0   # Kacheln pro Kartenblock

var rom: NdsRom
var land: Narc
var matrices: Narc
var buildings: Narc
var areas: Narc
var tilesets: Narc
var map_names := PackedStringArray()
var _headers_off := -1
var _arm9: PackedByteArray
var _tileset_cache := {}
var _bld_cache := {}
var look: Callable   # (mat: Dictionary, img: Image) -> Material


func _init(r: NdsRom, look_fn: Callable) -> void:
	rom = r
	look = look_fn
	land = Narc.parse(rom.file("a/0/6/5"))
	matrices = Narc.parse(rom.file("a/0/4/1"))
	buildings = Narc.parse(rom.file("a/0/4/0"))
	areas = Narc.parse(rom.file("a/0/4/2"))
	tilesets = Narc.parse(rom.file("a/0/4/4"))
	var names := rom.file("fielddata/maptable/mapname.bin")
	for i in range(0, names.size(), 16):
		map_names.append(names.slice(i, i + 16).get_string_from_ascii())
	_arm9 = rom.arm9()


func header_id(internal_name: String) -> int:
	return map_names.find(internal_name)


## Kartenkopf-Tabelle im ARM9 finden. Es gibt zwei Kandidaten im Abstand von
## einem Eintrag; der richtige ist der, dessen Tileset zur Karte passt.
func _header_candidates() -> Array:
	var n := map_names.size()
	var out := []
	var size := _arm9.size() - n * 24
	var b := 0
	while b < size:
		var ok := true
		for i in n:
			var e := b + i * 24
			if _arm9[e + 1] >= areas.files.size() or _arm9.decode_u16(e + 4) >= matrices.files.size():
				ok = false
				break
		if ok:
			out.append(b)
		b += 4
	return out


func _area_of(hdr: int) -> int:
	return _arm9[_headers_off + hdr * 24 + 1]


func _tileset_of(hdr: int) -> int:
	return areas.files[_area_of(hdr)].decode_u16(2)


func _tileset(idx: int) -> Tex0:
	if not _tileset_cache.has(idx):
		_tileset_cache[idx] = Tex0.from_file(tilesets.files[idx])
	return _tileset_cache[idx]


## Matrix 0 (Overworld) lesen.
func _matrix(id: int) -> Dictionary:
	var mx := matrices.files[id]
	var w := mx[0]
	var h := mx[1]
	var has_h := mx[2]
	var has_a := mx[3]
	var o := 5 + mx[4]
	var n := w * h
	var hdr := []
	var alt := []
	var blk := []
	for i in n:
		hdr.append(mx.decode_u16(o + i * 2) if has_h else -1)
	o += 2 * n * has_h
	for i in n:
		alt.append(mx[o + i] if has_a else 0)
	o += n * has_a
	for i in n:
		blk.append(mx.decode_u16(o + i * 2))
	return {"w": w, "h": h, "hdr": hdr, "alt": alt, "blk": blk}


func _land_model(block: int) -> PackedByteArray:
	var ld := land.files[block]
	var perm := ld.decode_u32(0)
	var bld := ld.decode_u32(4)
	var mdl := ld.decode_u32(8)
	var extra := ld.decode_u16(0x12)
	var mo := 0x14 + extra + perm + bld
	return ld.slice(mo, mo + mdl)


func _land_buildings(block: int) -> Array:
	var ld := land.files[block]
	var perm := ld.decode_u32(0)
	var bld := ld.decode_u32(4)
	var extra := ld.decode_u16(0x12)
	var b0 := 0x14 + extra + perm
	var out := []
	for i in range(0, bld, 48):
		var o := b0 + i
		out.append({"id": ld.decode_u32(o),
			"pos": Vector3(ld.decode_s32(o + 4), ld.decode_s32(o + 8), ld.decode_s32(o + 12)) / 4096.0 * G3d.SCALE})
	return out


func _building_mesh(id: int) -> ArrayMesh:
	if not _bld_cache.has(id):
		var b := buildings.files[id]
		_bld_cache[id] = G3d.build_mesh(b, Tex0.from_file(b), look)
	return _bld_cache[id]


## Lädt die Stadt mit dem internen Namen (z.B. "T20" = Neuborkia) plus Nachbarblöcke.
## Gibt Node3D zurück; Mittelpunkt der Stadt liegt bei (0,0,0).
func load_town(internal_name: String, radius := 1) -> Node3D:
	var root := Node3D.new()
	root.name = internal_name
	var hid := header_id(internal_name)
	if hid < 0:
		push_error("Karte %s nicht gefunden" % internal_name)
		return root
	var mx := _matrix(0)
	var cell: int = mx["hdr"].find(hid)
	if cell < 0:
		push_error("Karte %s nicht in Matrix 0" % internal_name)
		return root
	var cx: int = cell % mx["w"]
	var cy: int = cell / mx["w"]

	# Richtige Kopf-Tabelle wählen: Tileset muss alle Texturen des Stadtblocks haben.
	var need := G3d.needed_textures(_land_model(mx["blk"][cell]))
	for cand in _header_candidates():
		_headers_off = cand
		if _tileset(_tileset_of(hid)).has_all(need):
			break

	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= mx["w"] or y >= mx["h"]:
				continue
			var i: int = y * mx["w"] + x
			var blk: int = mx["blk"][i]
			if blk >= land.files.size():
				continue
			var h: int = mx["hdr"][i]
			var tex := _tileset(_tileset_of(h if h > 0 else hid))
			var origin := Vector3(dx * BLOCK, mx["alt"][i] * 0.5, dy * BLOCK)
			var mi := MeshInstance3D.new()
			mi.name = "Block_%d_%d" % [x, y]
			mi.mesh = G3d.build_mesh(_land_model(blk), tex, look)
			mi.position = origin
			# Kachel-Attribute (32x32, je 2 Byte: Bodenart, Kollision) für Details wie Wasser/Gras
			var ld := land.files[blk]
			var ex := ld.decode_u16(0x12)
			mi.set_meta("tiles", ld.slice(0x14 + ex, 0x14 + ex + ld.decode_u32(0)))
			mi.add_to_group("land")
			root.add_child(mi)
			for b in _land_buildings(blk):
				if b["id"] >= buildings.files.size():
					continue
				var bi := MeshInstance3D.new()
				bi.name = "Gebaeude_%d" % b["id"]
				bi.mesh = _building_mesh(b["id"])
				bi.position = origin + b["pos"]
				root.add_child(bi)
	return root
