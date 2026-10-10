class_name WorldAddress
extends RefCounted
const CHUNK_SIZE := 768
const MAX_RELATIVE_CHUNKS := 8
const MAX_INT: int = 9223372036854775807
const MIN_INT: int = -9223372036854775807 - 1
static func parse(chunk: Array) -> Dictionary:
	if chunk.size() != 2: return _error("invalid_chunk_address")
	var values: Array[int] = []
	for raw in chunk:
		if not raw is String or raw.is_empty(): return _error("invalid_chunk_address")
		var negative: bool = raw.begins_with("-")
		var digits: String = raw.substr(1) if negative else raw
		if digits.is_empty() or (digits.length() > 1 and digits.begins_with("0")) or (negative and digits == "0"): return _error("invalid_chunk_address")
		for c in digits:
			if c < "0" or c > "9": return _error("invalid_chunk_address")
		var limit := "9223372036854775808" if negative else "9223372036854775807"
		if digits.length() > 19 or (digits.length() == 19 and digits > limit): return _error("address_overflow")
		values.append(raw.to_int())
	return {"ok":true,"x":values[0],"y":values[1]}
static func key(chunk: Array) -> String:
	return chunk[0]+","+chunk[1] if parse(chunk).ok else ""
static func add(value: int, offset: int) -> Dictionary:
	if (offset > 0 and value > MAX_INT-offset) or (offset < 0 and value < MIN_INT-offset): return _error("address_overflow")
	return {"ok":true,"value":value+offset}
static func normalize(chunk: Array, local: Vector2) -> Dictionary:
	var p := parse(chunk)
	if not p.ok: return p
	if not is_finite(local.x) or not is_finite(local.y) or absf(local.x) > CHUNK_SIZE*64 or absf(local.y) > CHUNK_SIZE*64: return _error("invalid_local_position")
	var dx := int(floor(local.x/CHUNK_SIZE))
	var dy := int(floor(local.y/CHUNK_SIZE))
	var x := add(p.x,dx)
	var y := add(p.y,dy)
	if not x.ok or not y.ok: return _error("address_overflow")
	var offset := Vector2(dx*CHUNK_SIZE,dy*CHUNK_SIZE)
	return {"ok":true,"chunk":[str(x.value),str(y.value)],"local":local-offset,"offset":offset}
static func relative(chunk: Array, local: Vector2, origin: Array) -> Dictionary:
	var p := parse(chunk)
	var o := parse(origin)
	if not p.ok or not o.ok: return _error("invalid_chunk_address")
	if not is_finite(local.x) or not is_finite(local.y): return _error("invalid_local_position")
	var dx := _bounded_difference(p.x,o.x)
	var dy := _bounded_difference(p.y,o.y)
	if not dx.ok or not dy.ok: return _error("outside_working_set")
	return {"ok":true,"local":Vector2(dx.value*CHUNK_SIZE,dy.value*CHUNK_SIZE)+local}
static func _bounded_difference(a: int, b: int) -> Dictionary:
	# Never subtract arbitrary signed endpoints: their difference may overflow.
	for distance in range(-MAX_RELATIVE_CHUNKS,MAX_RELATIVE_CHUNKS+1):
		var candidate := add(b,distance)
		if candidate.ok and candidate.value == a: return {"ok":true,"value":distance}
	return _error("outside_working_set")
static func domain_digest(seed: int, chunk: Array, domain: String) -> String:
	if seed < 0 or seed > 2147483647 or not parse(chunk).ok or domain.is_empty(): return ""
	for c in domain:
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"): return ""
	var bytes := ("city_v1|%d|%s|%s|%s" % [seed,chunk[0],chunk[1],domain]).to_utf8_buffer()
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(bytes)
	return hash_context.finish().hex_encode()
static func less(a: Array, b: Array) -> bool:
	var aa := parse(a)
	var bb := parse(b)
	return aa.y < bb.y or (aa.y == bb.y and aa.x < bb.x)
static func _error(code: String) -> Dictionary:
	return {"ok":false,"error_code":code}
