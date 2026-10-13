extends RefCounted
const F = preload("res://tests/dev5_legacy_compatibility/legacy_fixture.gd")
func run(t) -> void:
	var path := "res://game/director/run_content_router.gd"
	t.check(ResourceLoader.exists(path),"production exact two-version content router exists")
	if not ResourceLoader.exists(path): return
	var router = load(path).new()
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(F.ROOT+"active_save/game_save.json"))
	var old: Dictionary = router.resolve(source.checkpoint)
	t.check(old.get("ok",false) and old.get("rules_version") == "dev4","known exact dev4 checkpoint selects explicit legacy rules")
	if not old.get("ok",false): return
	t.check(F.same(old.immutable_inputs,F.inputs()) and old.provider.rules_version() == "dev4","router supplies all exact legacy immutable definitions and behavior mode")
	var current: Dictionary = router.resolve({})
	t.check(current.get("ok",false) and current.get("rules_version") == "dev5" and current.provider.rules_version() == "dev5","empty route selects current new-run behavior")
	var capture: Dictionary = old.provider.capture_validation_inputs()
	t.check(capture.get("ok",false) and capture.sources.size() == 13,"legacy provider captures the exact frozen source set")
	if capture.get("ok",false):
		var original: Dictionary = old.provider.definitions_from_capture(capture)
		t.check(original.get("ok",false) and original.chapter.content_fingerprint == F.FINGERPRINT,"legacy capture derives original content fingerprint")
		capture.sources["data/evolutions.json"] = FileAccess.get_file_as_bytes("res://data/evolutions.json")
		t.check(not old.provider.definitions_from_capture(capture).get("ok",false),"legacy capture refuses edited source bytes even under a retained capture hash")
	var changed: Dictionary = source.checkpoint.duplicate(true)
	changed.rules.content_fingerprint = "0".repeat(64)
	t.check(router.resolve(changed).get("error_code") == "content_mismatch","router rejects unrecognized fingerprint rather than guessing a catalog")
	changed = source.checkpoint.duplicate(true)
	changed.world.content_fingerprint = "0".repeat(64)
	t.check(router.resolve(changed).get("error_code") == "content_mismatch","router rejects rules/world content disagreement")
	changed = source.checkpoint.duplicate(true)
	changed.content_revision = "future-content"
	t.check(router.resolve(changed).get("error_code") == "content_mismatch","router does not accept known fingerprint with changed content revision")
