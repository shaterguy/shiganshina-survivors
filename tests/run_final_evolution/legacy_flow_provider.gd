extends RefCounted
# Test-only immutable dev4 evolution definitions. This proves the existing
# legacy Core contract; it is not production save routing or a reset policy.
const Current = preload("res://tests/core/current_combat_provider.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
static func inputs() -> Dictionary:
	var result := {}
	for path in Core.GAMEPLAY_PATHS:
		var source: String = "res://tests/run_final_evolution/fixtures/dev4-evolutions.json" if path == "data/evolutions.json" else "res://"+path
		result[path] = JSON.parse_string(FileAccess.get_file_as_string(source))
	return result
func load_chapter(id: String) -> Dictionary:
	var result: Dictionary = Current.new().load_chapter(id)
	if not result.get("ok",false): return result
	var definitions := inputs()
	result.chapter.evolution_ids = definitions["data/evolutions.json"].items.keys()
	result.chapter.evolution_ids.sort()
	for path in Core.GAMEPLAY_PATHS: result.chapter.content_definition_hashes[path] = Chapters.new().definition_digest(definitions[path])
	result.chapter.content_identity_kind = "legacy_final_evolution_test_definitions"
	result.chapter.content_fingerprint = Chapters.new().definition_digest({"legacy_evolution_test":1,"chapter":result.chapter})
	return result
