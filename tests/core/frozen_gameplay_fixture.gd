extends RefCounted
# Explicit historical inputs for frozen grabber-era checkpoint tests. Current
# Core still verifies every digest against the unchanged historical provider.
const Core = preload("res://game/core/run_simulation.gd")
const Finite = preload("res://tests/core/finite_chapter_provider.gd")
const ROOT := "res://tests/fantasy_skills/legacy_inputs/"
static func inputs() -> Dictionary:
	var result := {}
	for path in Core.GAMEPLAY_PATHS:
		result[path] = JSON.parse_string(FileAccess.get_file_as_string(ROOT+path.get_file()))
	return result
static func simulation():
	return Core.new(Finite.new(),null,inputs())
static func chapter() -> Dictionary:
	return Finite.new().load_chapter("chapter_01_shiganshina").chapter
