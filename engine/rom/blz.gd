class_name Blz
extends RefCounted
## Rückwärts-LZ (BLZ), mit dem der ARM9-Code der ROM gepackt ist.


static func decompress_arm9(buf: PackedByteArray) -> PackedByteArray:
	# Der Fußbereich liegt am Ende des gepackten Teils; ggf. folgen 12 Bytes Nitro-Footer.
	for trim in [0, 12]:
		var b := buf.slice(0, buf.size() - trim)
		var out := _try(b)
		if out.size() > 0:
			return out
	return buf


static func _try(b: PackedByteArray) -> PackedByteArray:
	var n := b.size()
	if n < 8:
		return PackedByteArray()
	var footer := b.decode_u32(n - 8)
	var extra := b.decode_u32(n - 4)
	var hdr_len := footer >> 24
	var comp_len := footer & 0xFFFFFF
	if hdr_len < 8 or hdr_len > 0x0B or comp_len > n or comp_len == 0:
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(n + extra)
	for i in n:
		out[i] = b[i]
	var src := n - hdr_len
	var dst := n + extra
	var stop := n - comp_len
	while src > stop:
		src -= 1
		var flags := b[src]
		for _bit in 8:
			if src <= stop:
				break
			if flags & 0x80:
				src -= 2
				var v := b[src] | (b[src + 1] << 8)
				var disp := (v & 0x0FFF) + 3
				var length := (v >> 12) + 3
				for _k in length:
					dst -= 1
					out[dst] = out[dst + disp]
			else:
				src -= 1
				dst -= 1
				out[dst] = b[src]
			flags = (flags << 1) & 0xFF
	return out
