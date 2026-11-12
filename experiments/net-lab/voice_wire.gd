extends RefCounted
## Fixed 20 ms, mono 16 kHz PCM16 frames. No object decoding or audio files.
const SAMPLES := 320
const HEADER := 24
const SIZE := HEADER + SAMPLES * 2
const MAGIC := [68, 86, 48, 49] # DV01

static func tag(epoch: String) -> PackedByteArray:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(epoch.to_utf8_buffer())
	return hashing.finish().slice(0, 8)

static func is_voice(data: PackedByteArray) -> bool:
	return data.size() >= 4 and Array(data.slice(0, 4)) == MAGIC

static func frame(epoch: String, channel: int, burst: int, sequence: int, samples: PackedFloat32Array) -> PackedByteArray:
	if samples.size() != SAMPLES:
		return PackedByteArray()
	var data := PackedByteArray()
	data.resize(SIZE)
	for index in range(4):
		data[index] = MAGIC[index]
	var epoch_tag := tag(epoch)
	for index in range(8):
		data[4 + index] = epoch_tag[index]
	data[12] = 255 # Server replaces this with authenticated speaker slot.
	data[13] = channel
	data.encode_u32(14, burst)
	data.encode_u32(18, sequence)
	data.encode_u16(22, SAMPLES)
	for index in range(SAMPLES):
		var sample := int(clampf(samples[index], -1, 1) * 32767.0)
		data.encode_u16(HEADER + index * 2, sample & 65535)
	return data

static func valid(data: PackedByteArray, epoch: String) -> bool:
	return data.size() == SIZE and is_voice(data) and data.slice(4, 12) == tag(epoch) and data[13] <= 1 and data.decode_u32(14) > 0 and data.decode_u32(18) > 0 and data.decode_u16(22) == SAMPLES

static func samples(data: PackedByteArray) -> PackedVector2Array:
	var output := PackedVector2Array()
	output.resize(SAMPLES)
	for index in range(SAMPLES):
		var sample := int(data.decode_u16(HEADER + index * 2))
		if sample > 32767:
			sample -= 65536
		var value := float(sample) / 32768.0
		output[index] = Vector2(value, value)
	return output
