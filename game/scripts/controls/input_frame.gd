class_name InputFrame
extends RefCounted
## One boat's input for one tick (networking.md §4.1), stamped by PlayerControls at each tick boundary.

const SAIL_NONE := 0
const SAIL_DROP_FRONT := 255

const FLAG_LET_FLY := 1
const FLAG_AUTO_TRIM := 2
const FLAG_HAIL := 4
const FLAG_HAIL_REPLY := 8
const FLAG_PROTEST := 16

var tick := 0
var h_cmd := 0.0  # [-1, 1]
var sheet_cmd := 0.0  # [0, 1]
## 0 none, 1..15 hoist(sail index + 1), 255 drop_front()
var sail_req := SAIL_NONE
var flags := 0


func let_fly() -> bool:
	return flags & FLAG_LET_FLY != 0


func auto_trim() -> bool:
	return flags & FLAG_AUTO_TRIM != 0


func has(flag: int) -> bool:
	return flags & flag != 0


static func hoist_req(sail_index: int) -> int:
	return sail_index + 1


## the 6-byte encoding of networking.md §4.1 (int16 h_cmd, u16 sheet_cmd, u8 sail_req, u8 flags, little endian)
func encode() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(6)
	b.encode_s16(0, int(roundf(clampf(h_cmd, -1.0, 1.0) * 32767.0)))
	b.encode_u16(2, int(roundf(clampf(sheet_cmd, 0.0, 1.0) * 65535.0)))
	b.encode_u8(4, sail_req)
	b.encode_u8(5, flags)
	return b


static func decode(b: PackedByteArray, at_tick: int = 0) -> InputFrame:
	var f := InputFrame.new()
	f.tick = at_tick
	f.h_cmd = b.decode_s16(0) / 32767.0
	f.sheet_cmd = b.decode_u16(2) / 65535.0
	f.sail_req = b.decode_u8(4)
	f.flags = b.decode_u8(5)
	return f
