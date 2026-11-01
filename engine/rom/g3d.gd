class_name G3d
extends RefCounted
## Liest NNS-G3D-Modelle (BMD0/MDL0) und Texturen (TEX0) aus der ROM und baut
## daraus Godot-Meshes. Alles passiert zur Laufzeit auf dem Gerät.

const SCALE := 1.0 / 16.0   # 16 Modell-Einheiten = 1 Kachel = 1 Godot-Meter


static func blocks(buf: PackedByteArray, base := 0) -> Dictionary:
	var n := buf.decode_u16(base + 0x0E)
	var out := {}
	for i in n:
		var o := base + buf.decode_u32(base + 0x10 + i * 4)
		out[buf.slice(o, o + 4).get_string_from_ascii()] = o
	return out


## NNS-Wörterbuch: Array von [name, offset_der_daten]
static func dict(buf: PackedByteArray, off: int) -> Array:
	var num := buf[off + 1]
	var e := off + buf.decode_u16(off + 6)
	var unit := buf.decode_u16(e)
	var ofs_name := buf.decode_u16(e + 2)
	var out := []
	for i in num:
		var nm := buf.slice(e + ofs_name + i * 16, e + ofs_name + (i + 1) * 16).get_string_from_ascii()
		out.append([nm, e + 4 + i * unit])
	return out


static func _s(v: int, bits: int) -> int:
	return v - (1 << bits) if v & (1 << (bits - 1)) else v


const _NPARAM := {0x10: 1, 0x12: 1, 0x13: 1, 0x14: 1, 0x16: 16, 0x17: 12, 0x18: 16, 0x19: 12,
	0x1A: 9, 0x1B: 3, 0x1C: 3, 0x20: 1, 0x21: 1, 0x22: 1, 0x23: 2, 0x24: 1, 0x25: 1, 0x26: 1,
	0x27: 1, 0x28: 1, 0x29: 1, 0x2A: 1, 0x2B: 1, 0x30: 1, 0x31: 1, 0x32: 1, 0x33: 1, 0x34: 32,
	0x40: 1, 0x50: 1, 0x60: 1, 0x70: 3, 0x71: 2, 0x72: 1}


## Führt eine GX-Displayliste aus und hängt Dreiecke an st (SurfaceTool) an.
static func run_dl(buf: PackedByteArray, start: int, size: int, pos_scale: float,
		tex_size: Vector2, st: SurfaceTool) -> int:
	var verts := []
	var prim := 0
	var cur := Vector3.ZERO
	var nrm := Vector3.UP
	var uv := Vector2.ZERO
	var col := Color.WHITE
	var ntri := 0
	var p := start
	var end := start + size
	var k := pos_scale * SCALE
	while p + 4 <= end:
		var cmds := [buf[p], buf[p + 1], buf[p + 2], buf[p + 3]]
		p += 4
		for c in cmds:
			var n: int = _NPARAM.get(c, 0)
			var a := buf.decode_u32(p) if n > 0 else 0
			var b := buf.decode_u32(p + 4) if n > 1 else 0
			p += 4 * n
			var is_vtx := false
			match c:
				0x40:
					ntri += _flush(verts, prim, st)
					prim = a & 3
				0x41:
					ntri += _flush(verts, prim, st)
				0x20:
					col = Color((a & 31) / 31.0, ((a >> 5) & 31) / 31.0, ((a >> 10) & 31) / 31.0)
				0x21:
					nrm = Vector3(_s(a & 0x3FF, 10), _s((a >> 10) & 0x3FF, 10), _s((a >> 20) & 0x3FF, 10)) / 512.0
				0x22:
					uv = Vector2(_s(a & 0xFFFF, 16), _s(a >> 16, 16)) / 16.0
				0x23:
					cur = Vector3(_s(a & 0xFFFF, 16), _s(a >> 16, 16), _s(b & 0xFFFF, 16)) / 4096.0
					is_vtx = true
				0x24:
					cur = Vector3(_s(a & 0x3FF, 10), _s((a >> 10) & 0x3FF, 10), _s((a >> 20) & 0x3FF, 10)) / 64.0
					is_vtx = true
				0x25:
					cur = Vector3(_s(a & 0xFFFF, 16) / 4096.0, _s(a >> 16, 16) / 4096.0, cur.z)
					is_vtx = true
				0x26:
					cur = Vector3(_s(a & 0xFFFF, 16) / 4096.0, cur.y, _s(a >> 16, 16) / 4096.0)
					is_vtx = true
				0x27:
					cur = Vector3(cur.x, _s(a & 0xFFFF, 16) / 4096.0, _s(a >> 16, 16) / 4096.0)
					is_vtx = true
				0x28:
					cur += Vector3(_s(a & 0x3FF, 10), _s((a >> 10) & 0x3FF, 10), _s((a >> 20) & 0x3FF, 10)) / 4096.0
					is_vtx = true
			if is_vtx:
				verts.append([cur * k, nrm, Vector2(uv.x / tex_size.x, uv.y / tex_size.y), col])
	ntri += _flush(verts, prim, st)
	return ntri


static func _flush(verts: Array, prim: int, st: SurfaceTool) -> int:
	var n := verts.size()
	var idx := []
	match prim:
		0:
			for i in range(0, n - 2, 3): idx.append([i, i + 1, i + 2])
		1:
			for i in range(0, n - 3, 4): idx.append_array([[i, i + 1, i + 2], [i, i + 2, i + 3]])
		2:
			for i in range(n - 2): idx.append([i, i + 1, i + 2] if i % 2 == 0 else [i + 1, i, i + 2])
		3:
			for i in range(0, n - 3, 2): idx.append_array([[i, i + 1, i + 3], [i, i + 3, i + 2]])
	for t in idx:
		# DS gegen den Uhrzeigersinn, Godot im Uhrzeigersinn -> Reihenfolge drehen
		for j in [t[0], t[2], t[1]]:
			var v: Array = verts[j]
			st.set_color(v[3])
			st.set_normal(v[1])
			st.set_uv(v[2])
			st.add_vertex(v[0])
	verts.clear()
	return idx.size()


## Material-Infos eines Modells.
static func _materials(buf: PackedByteArray, base: int) -> Array:
	var ofs_tex := buf.decode_u16(base)
	var ofs_pal := buf.decode_u16(base + 2)
	var mats := []
	for e in dict(buf, base + 4):
		var mo := base + buf.decode_u32(e[1])
		var poly_attr := buf.decode_u32(mo + 12)
		var tex_param := buf.decode_u32(mo + 20)
		mats.append({"name": e[0], "alpha": (poly_attr >> 16) & 31, "cull": (poly_attr >> 6) & 3,
			"tex_param": tex_param, "diff": buf.decode_u32(mo + 4), "tex": "", "pal": ""})
	for pair in [["tex", ofs_tex], ["pal", ofs_pal]]:
		for e in dict(buf, base + pair[1]):
			var lo := buf.decode_u16(e[1])
			var num := buf[e[1] + 2]
			for k in num:
				mats[buf[base + lo + k]][pair[0]] = e[0]
	return mats


static func _sbc(buf: PackedByteArray, start: int, end: int) -> Dictionary:
	var p := start
	var mat := -1
	var out := {}
	while p < end:
		var op := buf[p]
		var cmd := op & 0x1F
		var flg := op >> 5
		if cmd == 0x01:
			break
		if cmd == 0x04:
			mat = buf[p + 1]
		elif cmd == 0x05:
			out[buf[p + 1]] = mat
		var ln := 1
		match cmd:
			0x02: ln = 3
			0x03, 0x04, 0x05: ln = 2
			0x06: ln = 4 + (1 if flg & 1 else 0) + (1 if flg & 2 else 0)
			0x07, 0x08: ln = 2 + (1 if flg & 1 else 0) + (1 if flg & 2 else 0)
			0x09: ln = 3 + buf[p + 2] * 3
			0x0A: ln = 9
			0x0C, 0x0D: ln = 3
		p += ln
	return out


## Liest alle Texturnamen, die ein Modell braucht.
static func needed_textures(buf: PackedByteArray) -> PackedStringArray:
	var out := PackedStringArray()
	var mdl0: int = blocks(buf)["MDL0"]
	for e in dict(buf, mdl0 + 8):
		var m := mdl0 + buf.decode_u32(e[1])
		for mat in _materials(buf, m + buf.decode_u32(m + 8)):
			if mat["tex"] != "" and not out.has(mat["tex"]):
				out.append(mat["tex"])
	return out


## Baut ein Mesh. tex_buf/tex_off: wo der TEX0-Block liegt (eigener oder Tileset).
static func build_mesh(buf: PackedByteArray, tex: Tex0, look: Callable) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var mdl0: int = blocks(buf)["MDL0"]
	for e in dict(buf, mdl0 + 8):
		var m := mdl0 + buf.decode_u32(e[1])
		var ofs_sbc := buf.decode_u32(m + 4)
		var ofs_mat := buf.decode_u32(m + 8)
		var ofs_shp := buf.decode_u32(m + 12)
		var pos_scale := buf.decode_s32(m + 0x1C) / 4096.0
		var mats := _materials(buf, m + ofs_mat)
		var bind := _sbc(buf, m + ofs_sbc, m + ofs_mat)
		var shp := dict(buf, m + ofs_shp)
		for si in shp.size():
			var s := m + ofs_shp + buf.decode_u32(shp[si][1])
			var dl_off := s + buf.decode_u32(s + 8)
			var dl_size := buf.decode_u32(s + 12)
			var mi: int = bind.get(si, -1)
			var mat: Dictionary = mats[mi] if mi >= 0 and mi < mats.size() else {}
			var img: Image = null
			if not mat.is_empty() and mat["tex"] != "" and tex != null:
				img = tex.decode(mat["tex"], mat["pal"])
			var tsize := Vector2(img.get_width(), img.get_height()) if img else Vector2(8, 8)
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			if run_dl(buf, dl_off, dl_size, pos_scale, tsize, st) == 0:
				continue
			st.set_material(look.call(mat, img))
			st.commit(mesh)
	return mesh
