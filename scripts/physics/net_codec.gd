class_name NetCodec
extends RefCounted
## Compact encoding of physics body states for the host -> client stream.
##
## Packet: f32 host physics time, u8 count, then per body 12 bytes:
##   u8 net id, u8 flags (bit0 asleep, bit1 teleport, bits 3-7 epoch mod 32),
##   3 x s16 position (5 mm steps, +-163 m), u32 rotation (smallest three, 3 x 10 bits).

const POS_STEP := 0.005
const BODY_BYTES := 12
const HEADER_BYTES := 5
const FLAG_ASLEEP := 1
const FLAG_TELEPORT := 2
const QMAX := 0.70710678


static func begin(time: float, count: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(HEADER_BYTES + count * BODY_BYTES)
	out.encode_float(0, time)
	out.encode_u8(4, count)
	return out


static func write_body(out: PackedByteArray, index: int, net_id: int, flags: int, epoch: int, pos: Vector3, rot: Quaternion) -> void:
	var at := HEADER_BYTES + index * BODY_BYTES
	out.encode_u8(at, net_id)
	out.encode_u8(at + 1, (flags & 7) | ((epoch & 31) << 3))
	out.encode_s16(at + 2, _q(pos.x))
	out.encode_s16(at + 4, _q(pos.y))
	out.encode_s16(at + 6, _q(pos.z))
	out.encode_u32(at + 8, pack_quat(rot))


## Returns {"time": float, "bodies": [[net_id, flags, epoch, pos, rot], ...]} or {} if malformed.
static func read(data: PackedByteArray) -> Dictionary:
	if data.size() < HEADER_BYTES:
		return {}
	var count := data.decode_u8(4)
	if data.size() != HEADER_BYTES + count * BODY_BYTES:
		return {}
	var bodies := []
	for i in range(count):
		var at := HEADER_BYTES + i * BODY_BYTES
		var packed_flags := data.decode_u8(at + 1)
		var pos := Vector3(data.decode_s16(at + 2), data.decode_s16(at + 4), data.decode_s16(at + 6)) * POS_STEP
		bodies.append([data.decode_u8(at), packed_flags & 7, packed_flags >> 3, pos, unpack_quat(data.decode_u32(at + 8))])
	return {"time": data.decode_float(0), "bodies": bodies}


static func _q(v: float) -> int:
	return clampi(roundi(v / POS_STEP), -32767, 32767)


## Smallest-three quaternion: 2 bits for the dropped (largest) component, 10 bits each for the rest.
static func pack_quat(q: Quaternion) -> int:
	q = q.normalized()
	var c := [q.x, q.y, q.z, q.w]
	var largest := 0
	for i in range(1, 4):
		if absf(c[i]) > absf(c[largest]):
			largest = i
	var sign_fix := -1.0 if c[largest] < 0.0 else 1.0
	var bits := largest
	var shift := 2
	for i in range(4):
		if i == largest:
			continue
		var v: float = clampf(c[i] * sign_fix, -QMAX, QMAX)
		bits |= roundi((v + QMAX) / (2.0 * QMAX) * 1023.0) << shift
		shift += 10
	return bits


static func unpack_quat(bits: int) -> Quaternion:
	var largest := bits & 3
	var c := [0.0, 0.0, 0.0, 0.0]
	var shift := 2
	var sum := 0.0
	for i in range(4):
		if i == largest:
			continue
		var v := float((bits >> shift) & 1023) / 1023.0 * 2.0 * QMAX - QMAX
		c[i] = v
		sum += v * v
		shift += 10
	c[largest] = sqrt(maxf(0.0, 1.0 - sum))
	return Quaternion(c[0], c[1], c[2], c[3]).normalized()
