extends RefCounted
const Codec = preload("res://game/world/world_delta_codec.gd")
var pages := {}
var reads := 0
var writes := 0
var _write_sequence: HashingContext
var _observed_write_calls := 0
func _init() -> void:
	write_page({"format_revision":1,"kind":"leaf","records":[]})
func read_page(hash: String) -> Dictionary:
	reads += 1
	return Codec.decode(pages[hash],hash) if pages.has(hash) else Codec.fail("world_page_missing")
func write_page(page: Dictionary) -> Dictionary:
	var encoded := Codec.encode(page)
	if not encoded.ok: return encoded
	writes += 1
	pages[encoded.hash] = encoded.bytes
	if _write_sequence != null:
		_write_sequence.update((encoded.hash+"\n").to_utf8_buffer())
		_observed_write_calls += 1
	return {"ok":true,"hash":encoded.hash}

func begin_write_sequence() -> void:
	_write_sequence = HashingContext.new()
	_write_sequence.start(HashingContext.HASH_SHA256)
	_write_sequence.update("world_delta_write_sequence_v1\n".to_utf8_buffer())
	_observed_write_calls = 0
func finish_write_sequence() -> Dictionary:
	var result := {"page_write_calls":_observed_write_calls,"sequence_digest":_write_sequence.finish().hex_encode()}
	_write_sequence = null
	return result
