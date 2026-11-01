class_name NdsRom
extends RefCounted
## Liest das Dateisystem (FNT/FAT) einer NDS-ROM. Die ROM bleibt beim Nutzer,
## es wird nichts davon gespeichert oder weitergegeben.

var data: PackedByteArray
var game_code := ""
var _paths := {}   # "a/0/6/5" -> file id
var _fat_off := 0


static func open(path: String) -> NdsRom:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("ROM nicht lesbar: %s" % path)
		return null
	var r := NdsRom.new()
	r.data = f.get_buffer(f.get_length())
	if r.data.size() < 0x200:
		return null
	r.game_code = r.data.slice(0x0C, 0x10).get_string_from_ascii()
	r._parse_fs()
	return r


func u8(o: int) -> int: return data[o]
func u16(o: int) -> int: return data.decode_u16(o)
func u32(o: int) -> int: return data.decode_u32(o)


func _parse_fs() -> void:
	var fnt := u32(0x40)
	_fat_off = u32(0x48)
	_walk_dir(fnt, 0xF000, "")


func _walk_dir(fnt: int, dir_id: int, prefix: String) -> void:
	var entry := fnt + (dir_id & 0xFFF) * 8
	var sub := fnt + u32(entry)
	var file_id := u16(entry + 4)
	var p := sub
	while true:
		var t := u8(p)
		p += 1
		if t == 0:
			break
		var ln := t & 0x7F
		var name := data.slice(p, p + ln).get_string_from_ascii()
		p += ln
		if t & 0x80:
			var child := u16(p)
			p += 2
			_walk_dir(fnt, child, prefix + name + "/")
		else:
			_paths[prefix + name] = file_id
			file_id += 1


func has_file(path: String) -> bool:
	return _paths.has(path)


func file(path: String) -> PackedByteArray:
	var id: int = _paths[path]
	var s := u32(_fat_off + id * 8)
	var e := u32(_fat_off + id * 8 + 4)
	return data.slice(s, e)


func arm9() -> PackedByteArray:
	var off := u32(0x20)
	var size := u32(0x2C)
	var raw := data.slice(off, off + size)
	return Blz.decompress_arm9(raw)
