class_name WorldDeltaCodec
extends RefCounted
const Address = preload("res://game/world/world_address.gd")
const MAX_BYTES := 64*1024
const MAX_RECORDS := 16
const MAX_DIRTY := 64
const MAX_JSON_INTEGER: int = 9007199254740991
static func encode(page: Dictionary) -> Dictionary:
	var normalized := normalize(page)
	if not normalized.ok: return normalized
	var bytes := JSON.stringify(normalized.page,"",true,true).to_utf8_buffer()
	if bytes.size() > MAX_BYTES: return fail("world_page_oversize")
	return {"ok":true,"bytes":bytes,"hash":digest(bytes)}
static func decode(bytes: PackedByteArray, expected_hash: String) -> Dictionary:
	if bytes.size() > MAX_BYTES: return fail("world_page_oversize")
	if not valid_hash(expected_hash) or digest(bytes) != expected_hash: return fail("world_hash_mismatch")
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary: return fail("world_page_invalid")
	var normalized := normalize(parser.data)
	if not normalized.ok: return normalized
	# Reject duplicate/extra keys, noncanonical numbers, whitespace and key ordering.
	if JSON.stringify(normalized.page,"",true,true).to_utf8_buffer() != bytes: return fail("world_page_invalid")
	return normalized
static func normalize(page: Dictionary) -> Dictionary:
	if not integer(page.get("format_revision")) or page.format_revision != 1: return fail("world_page_invalid")
	var kind = page.get("kind")
	if kind in ["leaf","collision"]:
		if not exact_keys(page,["format_revision","kind","records"] + (["next_hash"] if kind == "collision" else [])): return fail("world_page_invalid")
		var records := normalize_records(page.get("records"),MAX_RECORDS)
		if not records.ok: return records
		var result := {"format_revision":1,"kind":kind,"records":records.records}
		if kind == "collision":
			if not page.next_hash is String or (page.next_hash != "" and not valid_hash(page.next_hash)) or records.records.is_empty(): return fail("world_page_invalid")
			result.next_hash = page.next_hash
		return {"ok":true,"page":result}
	if kind == "branch":
		if not exact_keys(page,["format_revision","kind","depth","children"]) or not integer(page.depth) or page.depth > 63 or not page.children is Array or page.children.is_empty() or page.children.size() > 16: return fail("world_page_invalid")
		var seen := {}
		var children := []
		for child in page.children:
			if not child is Dictionary or not exact_keys(child,["nibble","hash"]) or not integer(child.nibble) or child.nibble > 15 or not valid_hash(child.hash) or seen.has(int(child.nibble)): return fail("world_page_invalid")
			seen[int(child.nibble)] = true
			children.append({"nibble":int(child.nibble),"hash":child.hash})
		children.sort_custom(func(a,b): return a.nibble < b.nibble)
		return {"ok":true,"page":{"format_revision":1,"kind":"branch","depth":int(page.depth),"children":children}}
	return fail("world_page_invalid")
static func normalize_records(raw: Variant, limit: int = MAX_DIRTY) -> Dictionary:
	if not raw is Array or raw.size() > limit: return fail("world_page_invalid")
	var records := []
	var seen := {}
	for record in raw:
		if not record is Dictionary or not exact_keys(record,["chunk","props"]) or not record.chunk is Array or not Address.parse(record.chunk).ok or not record.props is Array or record.props.size() > 12: return fail("world_page_invalid")
		var key: String = Address.key(record.chunk)
		if seen.has(key): return fail("world_page_invalid")
		seen[key] = true
		var props := []
		var slots := {}
		for prop in record.props:
			if not prop is Dictionary or not exact_keys(prop,["slot_id","hp","destroyed"]) or not prop.slot_id is String or prop.slot_id.is_empty() or not integer(prop.hp) or prop.hp > MAX_JSON_INTEGER or not prop.destroyed is bool or slots.has(prop.slot_id): return fail("world_page_invalid")
			slots[prop.slot_id] = true
			props.append({"slot_id":prop.slot_id,"hp":int(prop.hp),"destroyed":prop.destroyed})
		props.sort_custom(func(a,b): return a.slot_id < b.slot_id)
		records.append({"chunk":record.chunk.duplicate(),"props":props})
	records.sort_custom(func(a,b): return Address.less(a.chunk,b.chunk))
	return {"ok":true,"records":records}
static func changes_digest(dirty_chunks: Array) -> Dictionary:
	var normalized := normalize_records(dirty_chunks)
	if not normalized.ok: return normalized
	# Bound dirty memory even when a slot identifier is maliciously huge.
	var bytes := JSON.stringify(normalized.records,"",true,true).to_utf8_buffer()
	if bytes.size() > MAX_BYTES*4: return fail("world_page_oversize")
	return {"ok":true,"hash":digest(bytes)}
static func empty_root() -> Dictionary:
	return {"format_revision":1,"root_hash":encode({"format_revision":1,"kind":"leaf","records":[]}).hash}
static func valid_root(root: Dictionary) -> Dictionary:
	if not exact_keys(root,["format_revision","root_hash"]) or not integer(root.get("format_revision")): return fail("world_page_invalid")
	if root.format_revision > 1: return fail("unsupported_schema")
	if root.format_revision != 1 or not valid_hash(root.root_hash): return fail("world_page_invalid")
	return {"ok":true}
static func integer(value: Variant) -> bool:
	if value is int: return value >= 0
	return value is float and is_finite(value) and value >= 0 and value < 9223372036854775807.0 and value == floor(value)
static func exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size(): return false
	for key in keys:
		if not value.has(key): return false
	return true
static func valid_hash(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for c in value:
		if not c in "0123456789abcdef": return false
	return true
static func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
static func fail(code: String) -> Dictionary:
	return {"ok":false,"error_code":code}
