extends RefCounted
# Explicit CURRENT gameplay in a finite test world. Historical fixture files and
# finite_chapter_provider.gd keep their frozen definitions and identities.
const Chapters = preload("res://game/director/chapter_catalog.gd")
func load_chapter(id: String) -> Dictionary:
	var result: Dictionary = Chapters.new().load_chapter(id)
	if not result.get("ok",false): return result
	var source_fingerprint: String = result.chapter.content_fingerprint
	result.chapter.world_mode = "finite_test"
	result.chapter.content_identity_kind = "current_finite_combat_definitions"
	result.chapter.content_fingerprint = Chapters.new().definition_digest({"identity_version":1,"base_definition_fingerprint":source_fingerprint,"world_mode":"finite_test","chapter":result.chapter})
	return result
