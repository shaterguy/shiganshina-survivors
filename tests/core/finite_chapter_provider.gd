extends RefCounted
# Current recovery finite test-only provider. Source21 .2 and Source22 .5 JSON remain preserved.
# The separate fixture is exported from the actual .6 catalog; finite_test identity is derived below.
const Chapters = preload("res://game/director/chapter_catalog.gd")
const PATH := "res://tests/fixtures/c4/finite_chapter_definition_grabber.json"
func load_chapter(id: String) -> Dictionary:
	if id != "chapter_01_shiganshina": return {"ok":false,"error_code":"unknown_chapter"}
	var value = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not value is Dictionary or not value.get("content_fingerprint") is String: return {"ok":false,"error_code":"invalid_chapter"}
	var source_fingerprint: String = value.content_fingerprint
	value.world_mode = "finite_test"
	value.content_identity_kind = "frozen_finite_test_definitions"
	value.content_fingerprint = Chapters.new().definition_digest({"identity_version":1,"base_definition_fingerprint":source_fingerprint,"world_mode":"finite_test","chapter":value})
	return {"ok":true,"chapter":value}
