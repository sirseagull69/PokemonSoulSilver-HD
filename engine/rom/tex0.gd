class_name Tex0
extends RefCounted
## TEX0-Block: dekodiert DS-Texturen zur Laufzeit in Godot-Images.

var buf: PackedByteArray
var tdata := 0
var t4 := 0
var t4p := 0
var pdata := 0
var texs := {}   # name -> param
var pals := {}   # name -> offset (>>3)
var _cache := {}


static func from_block(b: PackedByteArray, off: int) -> Tex0:
	var t := Tex0.new()
	t.buf = b
	t.tdata = off + b.decode_u32(off + 0x14)
	t.t4 = off + b.decode_u32(off + 0x24)
	t.t4p = off + b.decode_u32(off + 0x28)
	t.pdata = off + b.decode_u32(off + 0x38)
	for e in G3d.dict(b, off + b.decode_u16(off + 0x0E)):
		t.texs[e[0]] = b.decode_u32(e[1])
	for e in G3d.dict(b, off + b.decode_u32(off + 0x34)):
		t.pals[e[0]] = b.decode_u16(e[1])
	return t


static func from_file(b: PackedByteArray) -> Tex0:
	var bl := G3d.blocks(b)
	if not bl.has("TEX0"):
		return null
	return from_block(b, bl["TEX0"])


func has_all(names: PackedStringArray) -> bool:
	for n in names:
		if not texs.has(n):
			return false
	return true


static func _rgb(c: int) -> Color:
	return Color8((c & 31) * 255 / 31, ((c >> 5) & 31) * 255 / 31, ((c >> 10) & 31) * 255 / 31)


func decode(name: String, pal_name: String) -> Image:
	var key := name + "|" + pal_name
	if _cache.has(key):
		return _cache[key]
	if not texs.has(name):
		return null
	var param: int = texs[name]
	var fmt := (param >> 26) & 7
	var w := 8 << ((param >> 20) & 7)
	var h := 8 << ((param >> 23) & 7)
	var c0t := (param >> 29) & 1
	var off := (param & 0xFFFF) << 3
	var po: int = pdata + ((pals[pal_name] << 3) if pals.has(pal_name) else 0)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	# Lambdas teilen Objekte (Image) per Referenz – PackedByteArray würde kopiert
	var put := func(i: int, c: Color, a: int) -> void:
		img.set_pixel(i % w, i / w, Color(c.r, c.g, c.b, a / 255.0))
	var n := w * h
	if fmt == 7:
		for i in n:
			var c := buf.decode_u16(tdata + off + i * 2)
			put.call(i, _rgb(c), 255 if c & 0x8000 else 0)
	elif fmt == 5:
		var d := t4 + off
		var pi := t4p + (off >> 1)
		var bw := w / 4
		for by in h / 4:
			for bx in bw:
				var k := by * bw + bx
				var bits := buf.decode_u32(d + k * 4)
				var pidx := buf.decode_u16(pi + k * 2)
				var mode := pidx >> 14
				var pb: int = pdata + ((pals[pal_name] << 3) if pals.has(pal_name) else 0) + (pidx & 0x3FFF) * 4
				var cs := [_rgb(buf.decode_u16(pb)), _rgb(buf.decode_u16(pb + 2)),
					_rgb(buf.decode_u16(pb + 4)), _rgb(buf.decode_u16(pb + 6))]
				var al := [255, 255, 255, 255]
				match mode:
					0: al[3] = 0
					1:
						cs[2] = cs[0].lerp(cs[1], 0.5); al[3] = 0
					3:
						cs[2] = cs[0].lerp(cs[1], 3.0 / 8.0)
						cs[3] = cs[0].lerp(cs[1], 5.0 / 8.0)
				for yy in 4:
					for xx in 4:
						var v := (bits >> ((yy * 4 + xx) * 2)) & 3
						put.call((by * 4 + yy) * w + bx * 4 + xx, cs[v], al[v])
	else:
		var d := tdata + off
		for i in n:
			var c := Color.MAGENTA
			var a := 255
			match fmt:
				1:
					var b := buf[d + i]
					c = _rgb(buf.decode_u16(po + (b & 31) * 2))
					var a3 := b >> 5
					a = (a3 * 4 + a3 / 2) * 255 / 31
				6:
					var b := buf[d + i]
					c = _rgb(buf.decode_u16(po + (b & 7) * 2))
					a = (b >> 3) * 255 / 31
				2:
					var v := (buf[d + i / 4] >> ((i % 4) * 2)) & 3
					c = _rgb(buf.decode_u16(po + v * 2)); a = 0 if (c0t and v == 0) else 255
				3:
					var v := (buf[d + i / 2] >> ((i % 2) * 4)) & 15
					c = _rgb(buf.decode_u16(po + v * 2)); a = 0 if (c0t and v == 0) else 255
				4:
					var v := buf[d + i]
					c = _rgb(buf.decode_u16(po + v * 2)); a = 0 if (c0t and v == 0) else 255
			put.call(i, c, a)
	_cache[key] = img
	return img
