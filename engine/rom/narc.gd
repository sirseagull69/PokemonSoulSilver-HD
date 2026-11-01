class_name Narc
extends RefCounted
## NARC-Archiv: Liste von Unterdateien.

var files: Array[PackedByteArray] = []


static func parse(buf: PackedByteArray) -> Narc:
	var n := Narc.new()
	var fatb := 0x10
	var count := buf.decode_u32(fatb + 8)
	var fntb := fatb + buf.decode_u32(fatb + 4)
	var fimg := fntb + buf.decode_u32(fntb + 4)
	for i in count:
		var s := buf.decode_u32(fatb + 12 + i * 8)
		var e := buf.decode_u32(fatb + 16 + i * 8)
		n.files.append(buf.slice(fimg + 8 + s, fimg + 8 + e))
	return n
