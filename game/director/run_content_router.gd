extends RefCounted
# Two explicit production identities. Selection never edits saved authority.
# Current identity is derived from current files; only dev4 is pinned forever.
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
var _current
var _legacy = City.new("dev4")
func _init(current_provider = null) -> void:
	_current = City.new() if current_provider == null else current_provider
func resolve(snapshot: Dictionary = {}) -> Dictionary:
	var version := "dev5"
	if not snapshot.is_empty():
		if snapshot.get("chapter_id") != Chapters.CHAPTER_ID or snapshot.get("content_revision") != Chapters.CONTENT_REVISION: return _fail()
		if not snapshot.get("rules") is Dictionary or not snapshot.get("world") is Dictionary: return _fail()
		var fingerprint: Variant = snapshot.rules.get("content_fingerprint")
		if not fingerprint is String or fingerprint.length() != 64 or snapshot.world.get("content_fingerprint") != fingerprint: return _fail()
		if fingerprint == City.DEV4_FINGERPRINT: version = "dev4"
	var provider = _legacy if version == "dev4" else _current
	if provider.get_script() != City or provider.rules_version() != version: return _fail()
	var capture: Dictionary = provider.capture_validation_inputs()
	if not capture.get("ok",false): return _fail()
	var parsed: Dictionary = provider.definitions_from_capture(capture)
	if not parsed.get("ok",false): return _fail()
	if not snapshot.is_empty() and snapshot.rules.content_fingerprint != parsed.chapter.content_fingerprint: return _fail()
	return {"ok":true,"provider":provider,"immutable_inputs":parsed.definitions,"chapter":parsed.chapter,"rules_version":version,"capture":capture}
func _fail() -> Dictionary:
	return {"ok":false,"error_code":"content_mismatch"}
